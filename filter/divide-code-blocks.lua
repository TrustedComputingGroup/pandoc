-- draw horizontal rules above and below code blocks to separate them nicely

fontsize_classes =
{
    ["normal"] = "\\small",
    ["small"] = "\\scriptsize",
    ["tiny"] = "\\tiny",
}

function CodeBlock(block)
    local fontsize = fontsize_classes["normal"]
    for _, class in ipairs(block.classes) do
        local maybe_fontsize = fontsize_classes[string.lower(class)]
        if maybe_fontsize then
            fontsize = maybe_fontsize
            break
        end
    end

    -- Without any classes, code blocks are rendered with \verbatim instead of
    -- the Shaded environment. Forcing the addition of a class ensures that
    -- all code blocks are rendered consistently.
    table.insert(block.classes, "_placeholder")

    block.text = block.text:gsub("\r", "") -- Remove carriage-returns.

    return {
        pandoc.RawInline('latex', string.format([[
            \BeginCodeBlock{%s}
        ]], fontsize)),
        block,
        pandoc.RawInline('latex', [[
            \EndCodeBlock
        ]]),
    }
end