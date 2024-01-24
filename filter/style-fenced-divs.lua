-- style fenced divs according to the class

-- This table lists all the supported classes and the color of the box for each.
div_classes =
{
  ["informative"] = {
    -- Informative has special-casing for its labels.
    ["background"] = "informative-background",
    ["header"] = "informative-header",
    ["foreground"] = "informative-foreground",
  },
  ["note"] = {
    ["label"] = "Note:",
    ["background"] = "informative-background",
    ["header"] = "informative-header",
    ["foreground"] = "informative-foreground",
  },
  ["example"] = {
    ["label"] = "Example:",
    ["background"] = "informative-background",
    ["header"] = "informative-header",
    ["foreground"] = "informative-foreground",
  },
  ["caveat"] = {
    ["label"] = "Caveat:",
    ["background"] = "orange-background",
    ["header"] = "orange-header",
    ["foreground"] = "orange-foreground",
  },
  ["tip"] = {
    ["label"] = "Tip:",
    ["background"] = "green-background",
    ["header"] = "green-header",
    ["foreground"] = "green-foreground",
  },
  ["warning"] = {
    ["label"] = "Warning:",
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
        local hdr_label = label
        local foot_label = nil
        if(string.lower(class) == "informative") then
          hdr_label = "Start of informative comment"
          foot_label = "End of informative comment"
        end

        local result = pandoc.List({
          pandoc.RawBlock('latex', '\\vskip 0.5em'),
          pandoc.RawBlock('latex', string.format('\\begin{mdframed}[linewidth=0pt,backgroundcolor=%s,skipabove=\\parskip,nobreak=true]', color_bg)),
          pandoc.RawBlock('latex', string.format('\\textbf{\\textit{\\textcolor{%s}{\\small %s}}}', color_hdr, hdr_label)),
          pandoc.RawBlock('latex', string.format('\\color{%s}', color_fg)),
          el
        })
        if(foot_label) then
          result:insert(pandoc.RawBlock('latex', string.format('\\textbf{\\textit{\\textcolor{%s}{\\small %s}}}', color_hdr, foot_label)))
        end
        result:insert(pandoc.RawBlock('latex', '\\end{mdframed}'))
        return result
      end
    end
    return el
  end