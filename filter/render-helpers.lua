-- Turn [text]{.btick} into `text`, rendered without changing the font.

backtick_chars =
{
    ["latex"] = "\\textasciigrave{}",
    ["default"] = "`"
}

function backtick(el)
  local backtick_char = backtick_chars[FORMAT] or backtick_chars["default"]

  local new_inlines = {}

  table.insert(new_inlines, pandoc.RawInline(FORMAT, backtick_char))
  for _, inline_el in ipairs(el.content) do
      table.insert(new_inlines, inline_el)
  end
  table.insert(new_inlines, pandoc.RawInline(FORMAT, backtick_char))

  return new_inlines
end

function Span(el)
  if el.classes:includes('btick') then
    return backtick(el)
  else
    return el
  end
end
