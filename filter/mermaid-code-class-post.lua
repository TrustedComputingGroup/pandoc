-- Mermaid-filter doesn't support arbitrary classes on the code block.
-- As a hack, we preprocess mermaid code blocks by tacking all the classes
-- to the end of the identifier just before running mermaid-filter, then extract
-- those classes from the identifier immediately afterward.

-- Postprocess image blocks by decomposing the classes out of the identifier again.

function Image(el)
    if el.classes then
    end
    if el.identifier then
        local id, classes = el.identifier:match('(.*)__CLASSES__(.*)')
        -- If the ID had this weird suffix, strip the suffix and add the classes.
        if id then
            el.identifier = id
            -- Split classes on _ characters
            for class in classes:gmatch('([^_]+)_') do
                el.classes:insert(class)
            end
        end
    end
    return el
end
