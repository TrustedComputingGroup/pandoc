-- style fenced divs according to the class

-- This table lists all the supported classes and the color of the box for each.
div_classes =
{
  ["informative"] = {
    ["label"] = "Informative comment",
    ["background"] = "informative-background",
    ["header"] = "informative-header",
    ["foreground"] = "informative-foreground",
  },
  ["note"] = {
    ["label"] = "Note",
    ["background"] = "informative-background",
    ["header"] = "informative-header",
    ["foreground"] = "informative-foreground",
  },
  ["example"] = {
    ["label"] = "Example",
    ["background"] = "informative-background",
    ["header"] = "informative-header",
    ["foreground"] = "informative-foreground",
  },
  ["caveat"] = {
    ["label"] = "Caveat",
    ["background"] = "orange-background",
    ["header"] = "orange-header",
    ["foreground"] = "orange-foreground",
  },
  ["tip"] = {
    ["label"] = "Tip",
    ["background"] = "green-background",
    ["header"] = "green-header",
    ["foreground"] = "green-foreground",
  },
  ["warning"] = {
    ["label"] = "Warning",
    ["background"] = "red-background",
    ["header"] = "red-header",
    ["foreground"] = "red-foreground",
  }
}

function Div(el)
  local class = el.classes[1]
  if(class) then
    local class_spec = div_classes[string.lower(class)]
    if(class_spec) then
      local color_bg = class_spec["background"]
      local color_hdr = class_spec["header"]
      local color_fg = class_spec["foreground"]
      local label = class_spec["label"]

      return{
        pandoc.RawBlock('latex', '\\vskip 0.5em'),
        pandoc.RawBlock('latex', string.format('\\begin{mdframed}[linewidth=0pt,backgroundcolor=%s,skipabove=\\parskip,nobreak=true]', color_bg)),
        pandoc.RawBlock('latex', string.format('\\textbf{\\textit{\\textcolor{%s}{\\small\\BeginDemarcated{%s}}}}', color_hdr, label)),
        pandoc.RawBlock('latex', string.format('\\color{%s}', color_fg)),
        el,
        pandoc.RawBlock('latex', string.format('\\EndDemarcated{%s}', label)),
        pandoc.RawBlock('latex', '\\end{mdframed}')
      }
    end
  end
  return el
end