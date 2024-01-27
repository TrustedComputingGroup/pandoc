-- If a table has the "landscape" class on it, wrap it in sidewaystable.

function Table(el)
    if el.classes:find('landscape') then
        return {
            pandoc.RawBlock('latex', '\\begin{landscape}'),
            el,
            pandoc.RawBlock('latex', '\\end{landscape}')
        }
    end
    return el
  end