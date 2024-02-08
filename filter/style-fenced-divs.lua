-- style fenced divs according to the class

-- This table lists all the supported classes and the color of the box for each.
div_classes =
{
  ["informative"] = {
    ["label"] = "Informative comment",
  },
  ["note"] = {
    ["label"] = "Note",
  },
  ["example"] = {
    ["label"] = "Example",
  },
}

function Div(el)
  local class = el.classes[1]
  if(class) then
    local class_spec = div_classes[string.lower(class)]
    if(class_spec) then
      local label = class_spec["label"]

      return{
        pandoc.RawBlock('latex', string.format('\\BeginInformative{%s}\n', label)),
        el,
        pandoc.RawBlock('latex', string.format('\\EndInformative{%s}', label)),
      }
    end
  end
  return el
end