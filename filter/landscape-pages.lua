-- If a table has the "landscape" class on it, wrap it in the landscape environment.

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

-- Support figures as well. Pandoc's Mermaid filter doesn't seem to support ingesting classes into the AST,
-- so as a small hack, we also let the user tag figures for landscape mode using the identifier.

function Figure(el)
    if el.identifier:find('_landscape_') or pandoc.utils.stringify(el.classes):find('landscape') then
        return {
            pandoc.RawBlock('latex', '\\begin{landscape}'),
            el,
            pandoc.RawBlock('latex', '\\end{landscape}')
        }
    end
    return el
  end
