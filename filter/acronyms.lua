-- acronyms-auto.lua
-- Expands configured acronyms found in normal body text.
-- Does not process document metadata, headings, or TOC Divs.
--
-- The acronyms file path is read from the document's front matter:
--
--   ---
--   acronyms: my_acronyms.yaml
--   ---
--
-- If the 'acronyms' key is missing or the file cannot be opened,
-- the filter degrades to a no-op (with a warning on stderr)
-- instead of aborting the build.

-- ---------- YAML loading ----------

local function load_yaml(path)
  local f, err = io.open(path, "r")
  if not f then
    error(("acronym-filter: cannot open '%s': %s"):format(path, err))
  end

  local content = f:read("*a")
  f:close()

  local doc = pandoc.read("---\n" .. content .. "\n---\n", "markdown")

  local out = {}
  for key, val in pairs(doc.meta) do
    if type(val) == "table" then
      local entry = {}
      for k, v in pairs(val) do
        entry[k] = pandoc.utils.stringify(v)
      end
      out[key] = entry
    else
      out[key] = pandoc.utils.stringify(val)
    end
  end

  return out
end

local function normalize(raw)
  local out = {}

  for key, val in pairs(raw) do
    if type(val) == "table"
      and type(val.long) == "string"
      and val.long ~= "" then

      out[key] = {
        key         = key,
        short       = (val.short ~= "" and val.short) or key,
        long        = val.long,
        shortplural = (val.shortplural ~= "" and val.shortplural) or nil,
        longplural  = (val.longplural ~= "" and val.longplural) or nil,
        description = (val.description ~= "" and val.description) or nil,
      }
    else
      io.stderr:write(
        ("acronym-filter: entry '%s' ignored "
          .. "(expected a mapping with a 'long' field)\n"):format(key)
      )
    end
  end

  return out
end

-- ---------- State (initialized lazily from document metadata) ----------

local seen = {}

local trigger_map = {}
local disabled_triggers = {}
local triggers = {}

-- ---------- Search triggers ----------

local function add_trigger(text, entry, plural)
  if type(text) ~= "string" or text == "" or disabled_triggers[text] then
    return
  end

  local existing = trigger_map[text]

  if not existing then
    trigger_map[text] = {
      text = text,
      entry = entry,
      plural = plural,
    }
    return
  end

  -- Singular and plural may intentionally be identical, e.g. "SMS".
  if existing.entry.key == entry.key then
    if existing.plural and not plural then
      trigger_map[text] = {
        text = text,
        entry = entry,
        plural = plural,
      }
    end
    return
  end

  io.stderr:write(
    ("acronym-filter: automatic trigger '%s' is ambiguous "
      .. "(%s, %s); it will not be expanded automatically\n"):format(
        text,
        existing.entry.key,
        entry.key
    )
  )

  trigger_map[text] = nil
  disabled_triggers[text] = true
end

-- Build the trigger table from the file given in document metadata.
-- Called from Meta(), before Pandoc() runs.
local function setup_from_meta(meta)
  local file = meta.acronyms and pandoc.utils.stringify(meta.acronyms)

  if not file or file == "" then
    io.stderr:write(
      "acronym-filter: no 'acronyms' metadata key, "
        .. "acronym expansion disabled\n"
    )
    return
  end

  -- Resolve relative to the input file's directory if not found as-is.
  local f = io.open(file, "r")
  if not f and PANDOC_STATE.input_files[1] then
    local dir = pandoc.path.directory(PANDOC_STATE.input_files[1])
    local candidate = pandoc.path.join({ dir, file })
    local f2 = io.open(candidate, "r")
    if f2 then
      file = candidate
      f = f2
    end
  end

  if not f then
    io.stderr:write(
      ("acronym-filter: cannot open '%s', "
        .. "acronym expansion disabled\n"):format(file)
    )
    return
  end
  f:close()

  local acronyms = normalize(load_yaml(file))

  trigger_map = {}
  disabled_triggers = {}

  for _, entry in pairs(acronyms) do
    add_trigger(entry.short, entry, false)

    local plural = entry.shortplural or (entry.short .. "s")
    add_trigger(plural, entry, true)
  end

  triggers = {}
  for _, trigger in pairs(trigger_map) do
    triggers[#triggers + 1] = trigger
  end

  -- Prefer longer forms, so "APIs" is found before "API".
  table.sort(triggers, function(a, b)
    if #a.text == #b.text then
      return a.text < b.text
    end
    return #a.text > #b.text
  end)

  io.stderr:write(
    ("acronym-filter: loaded %d acronym entries from '%s'\n")
      :format(#acronyms, file)
  )
end

-- ---------- Matching and rendering ----------

local function is_word_byte(b)
  if not b then
    return false
  end

  return (b >= 48 and b <= 57)   -- 0-9
    or (b >= 65 and b <= 90)    -- A-Z
    or (b >= 97 and b <= 122)   -- a-z
    or b == 95                  -- _
end

local function match_at(text, pos)
  for _, candidate in ipairs(triggers) do
    local last = pos + #candidate.text - 1

    if last <= #text and text:sub(pos, last) == candidate.text then
      local before = pos > 1 and text:byte(pos - 1) or nil
      local after = last < #text and text:byte(last + 1) or nil

      if not is_word_byte(before) and not is_word_byte(after) then
        return candidate, last
      end
    end
  end

  return nil, nil
end

local function acronym_span(candidate)
  local entry = candidate.entry
  local already = seen[entry.key] == true
  seen[entry.key] = true

  local short
  local long

  if candidate.plural then
    short = entry.shortplural or (entry.short .. "s")
    long = entry.longplural or (entry.long .. "s")
  else
    short = entry.short
    long = entry.long
  end

  local rendered = already and short or (long .. " (" .. short .. ")")
  local attributes = already and {} or { ["data-key"] = entry.key }

  return pandoc.Span(
    rendered,
    pandoc.Attr("", { "acronym" }, attributes)
  )
end

local function replace_str(el)
  if #triggers == 0 then
    return nil
  end

  local text = el.text
  local result = {}
  local pos = 1
  local unchanged_from = 1
  local changed = false

  while pos <= #text do
    local candidate, last = match_at(text, pos)

    if candidate then
      if unchanged_from < pos then
        result[#result + 1] = pandoc.Str(
          text:sub(unchanged_from, pos - 1)
        )
      end

      result[#result + 1] = acronym_span(candidate)

      pos = last + 1
      unchanged_from = pos
      changed = true
    else
      pos = pos + 1
    end
  end

  if not changed then
    return nil
  end

  if unchanged_from <= #text then
    result[#result + 1] = pandoc.Str(text:sub(unchanged_from))
  end

  return result
end

-- ---------- Protected areas ----------

local function has_class(classes, wanted)
  for _, class in ipairs(classes) do
    if class == wanted then
      return true
    end
  end
  return false
end

local function is_toc_div(el)
  local id = el.identifier or ""

  return id == "toc"
    or id == "TOC"
    or id == "table-of-contents"
    or has_class(el.classes, "toc")
    or has_class(el.classes, "TOC")
    or has_class(el.classes, "table-of-contents")
end

-- This filter is applied only within body paragraphs/plain blocks.
local inline_filter = {
  traverse = "topdown",

  Header = function(el)
    return el, false
  end,

  Div = function(el)
    if is_toc_div(el) then
      return el, false
    end
  end,

  -- Avoid processing spans created by this filter or prior runs.
  Span = function(el)
    if has_class(el.classes, "acronym") then
      return el, false
    end
  end,

  Str = replace_str,
}

local body_filter = {
  traverse = "topdown",

  Header = function(el)
    return el, false
  end,

  Div = function(el)
    if is_toc_div(el) then
      return el, false
    end
  end,

  Para = function(el)
    return pandoc.walk_block(el, inline_filter), false
  end,

  Plain = function(el)
    return pandoc.walk_block(el, inline_filter), false
  end,
}

-- Only walk document blocks, not metadata. Therefore YAML titles are ignored.
return {
  {
    -- Load the acronyms file from document metadata before walking.
    Meta = function(meta)
      setup_from_meta(meta)
      return meta
    end,

    Pandoc = function(doc)
      -- Reset first-use tracking for each document.
      seen = {}

      -- Put all document blocks under one root, then walk that root.
      local root = pandoc.Div(doc.blocks)
      root = pandoc.walk_block(root, body_filter)

      doc.blocks = root.content
      return doc
    end,
  },
}