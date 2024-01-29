-- Mermaid-filter doesn't support arbitrary classes on the code block.
-- As a hack, we preprocess mermaid code blocks by tacking all the classes
-- to the end of the identifier just before running mermaid-filter, then extract
-- those classes from the identifier immediately afterward.

-- Preprocess code blocks by appending the classes to the identifier.

function CodeBlock(el)
    local isMermaid = false
    local classSuffix = '__CLASSES__'
    for i, class in ipairs(el.classes) do
        if class == 'mermaid' then
            isMermaid = true
        else
            classSuffix = classSuffix .. string.format("%s_", class)
        end
    end
    if isMermaid then
        el.identifier = el.identifier .. classSuffix
    end
    return el
end
