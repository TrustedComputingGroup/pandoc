-- Correct backtick rendering in Latex. Without this, escaped backticks are displayed as curly open single quote marks.

function Str(el)
  local new_inlines = {}
  local current_text = ""

  if FORMAT ~= "latex" or not el.text:match("`") then
    return el
  end

  for i = 1, #el.text do
    local char = el.text:sub(i, i)

    if char == "`" then
      if current_text ~= "" then
        table.insert(new_inlines, pandoc.Str(current_text))
        current_text = ""
      end
      table.insert(new_inlines, pandoc.RawInline('latex', '\\textasciigrave{}'))
    else
      current_text = current_text .. char
    end
  end

  if current_text ~= "" then
    table.insert(new_inlines, pandoc.Str(current_text))
  end

  return new_inlines
end
