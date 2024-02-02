-- Mermaid-filter doesn't support arbitrary classes on the code block.
-- Preprocess Mermaid diagram code blocks by enclosing them in figures.

function CodeBlock(el)
    local isMermaid = false
    local figure_classes = pandoc.List({})
    for i, class in ipairs(el.classes) do
        if class == 'mermaid' then
            isMermaid = true
        else
            figure_classes:insert(class)
        end
    end
    if isMermaid then
        local caption = {long = pandoc.Plain(pandoc.Str(el.attributes.caption))}
        local attrs = pandoc.Attr(el.identifier, figure_classes)
        el.identifier = nil
        el.classes = {'mermaid'}
        return pandoc.Figure(el, caption, attrs)
    end
    return el
end
