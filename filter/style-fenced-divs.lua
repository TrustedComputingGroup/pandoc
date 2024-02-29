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

      if FORMAT == 'latex' then
        return{
          pandoc.RawBlock('latex', string.format('\\BeginInformative{%s}\n', label)),
          el,
          pandoc.RawBlock('latex', string.format('\\EndInformative{%s}', label)),
        }
      end

      if FORMAT == 'docx' then
        local caption = {}
        local colspecs = {{'AlignLeft', 1.0}}
        local head = pandoc.TableHead()
        local bodies = {{
          attr = pandoc.Attr(nil, nil, {['custom-style'] = 'Informative'}),
          body = {pandoc.Row({pandoc.Cell(
            {
              pandoc.Para(pandoc.Span(string.format("Start of %s", label), pandoc.Attr("", {}, {["custom-style"] = "Emphasis"}))),
              el,
              pandoc.Para(pandoc.Span(string.format("End of %s", label), pandoc.Attr("", {}, {["custom-style"] = "Emphasis"})))
            }
          )})},
          head = {},
          row_head_columns = 0,
        }}
        local foot = pandoc.TableFoot()
        return pandoc.Div(
          pandoc.Table(caption, colspecs, head, bodies, foot),
          {['custom-style'] = 'TCG Informative'}
        )
      end
    end
  end
  return el
end