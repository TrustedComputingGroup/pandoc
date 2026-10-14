-- acronym-list.lua
-- Collects the spans tagged by acronyms.lua
-- (class "acronym", attribute "data-key") and replaces
-- a Div with id="acronyms" by a table.
-- Without such a Div, the table is appended at the end of the document.
--
-- The acronyms file path is read from the document's front matter:
--
--   ---
--   acronyms: my_acronyms.yaml
--   ---
--
-- If the 'acronyms' key is missing or the file cannot be opened,
-- this filter is a complete no-op (warning on stderr).

-- ---------- YAML loading (identical to acronyms.lua) ----------

local function load_yaml(path)
  local f, err = io.open(path, "r")
  if not f then
    error(("acronym-list: cannot open '%s': %s"):format(path, err))
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

-- ---------- State (initialized lazily from document metadata) ----------

local acronyms = nil  -- nil = not loaded / disabled

local function setup_from_meta(meta)
  local file = meta.acronyms and pandoc.utils.stringify(meta.acronyms)

  if not file or file == "" then
    io.stderr:write(
      "acronym-list: no 'acronyms' metadata key, "
        .. "acronym list disabled\n"
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
      ("acronym-list: cannot open '%s', "
        .. "acronym list disabled\n"):format(file)
    )
    return
  end
  f:close()

  acronyms = load_yaml(file)

  io.stderr:write(
    ("acronym-list: loaded %d acronym entries from '%s'\n")
      :format((function()
        local n = 0
        for _ in pairs(acronyms) do n = n + 1 end
        return n
      end)(), file)
  )
end

-- ---------- Build table from Markdown ----------

local function build_table(keys)
  if #keys == 0 then
    return pandoc.Para({ pandoc.Str("") })
  end

  -- Sort by short form (case-insensitive)
  table.sort(keys, function(a, b)
    local sa = (acronyms[a] and acronyms[a].short or a):lower()
    local sb = (acronyms[b] and acronyms[b].short or b):lower()
    return sa < sb
  end)

  local md = "| Acronym | Meaning | Description |\n"
          .. "|:--------|:--------|:------------|\n"
  for _, k in ipairs(keys) do
    local e = acronyms[k] or {}
    local short = (e.short or k):gsub("|", "\\|")
    local long  = (e.long  or ""):gsub("|", "\\|")
    local desc  = (e.description or ""):gsub("|", "\\|")
    md = md .. ("| %s | %s | %s |\n"):format(short, long, desc)
  end

  local doc = pandoc.read(md, "markdown")
  return doc.blocks[1]
end

-- ---------- Filter ----------

return {
  {
    -- Load the acronyms file from document metadata before Pandoc runs.
    Meta = function(meta)
      setup_from_meta(meta)
      return meta
    end,

    Pandoc = function(doc)
      -- No acronyms configured -> complete no-op.
      if not acronyms then
        return doc
      end

      -- 1) Collect used keys in order of first appearance
      local ordered, set = {}, {}
      doc = doc:walk({
        Span = function(el)
          if not el.classes:includes("acronym") then return nil end
          local key = el.attributes["data-key"]
          if key and not set[key] then
            set[key] = true
            ordered[#ordered+1] = key
          end
          return nil -- leave the marker untouched
        end,
      })

      -- 2) Replace the \listofacronyms marker
      local replaced = false

      doc = doc:walk({
        -- plain paragraph containing just the literal marker text
        Para = function(el)
          local s = pandoc.utils.stringify(el)
          if s == "\\listofacronyms" then
            replaced = true
            return { build_table(ordered) }
          end
        end,
        -- raw TeX / raw block variant, in case a different reader
        -- produced a RawBlock instead of a Para
        RawBlock = function(el)
          local t = el.text:gsub("%s+$", "")
          if t == "\\listofacronyms" then
            replaced = true
            return { build_table(ordered) }
          end
        end,
        -- keep the Div variant working as a fallback
        Div = function(el)
          if el.identifier == "acronyms" then
            replaced = true
            return { build_table(ordered) }
          end
        end,
      })

      -- 3) Fallback: no marker found -> append at end of document
      if not replaced then
        doc.blocks:insert(pandoc.Header(1, "Acronyms Used"))
        doc.blocks:insert(build_table(ordered))
      end

      return doc
    end,
  },
}