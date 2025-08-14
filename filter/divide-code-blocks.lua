-- draw horizontal rules above and below code blocks to separate them nicely

code_classes =
{
    ["normal"] = {
        ["font"] = "\\small",
    },
    ["small"] = {
        ["font"] = "\\scriptsize",
    },
    ["tiny"] = {
        ["font"] = "\\tiny",
    },
}

function CodeBlock(block)
    local class_spec = code_classes["normal"]
    for _, class in ipairs(block.classes) do
        local maybe_spec = code_classes[string.lower(class)]
        if maybe_spec then
            class_spec = maybe_spec
            break
        end
    end

    -- Without any classes, code blocks are rendered with \verbatim instead of
    -- the Shaded environment. Forcing the addition of a class ensures that
    -- all code blocks are rendered consistently.
    table.insert(block.classes, "_placeholder")

    block.text = block.text:gsub("\r", "") -- Remove carriage-returns.

    font = class_spec["font"]
    return {
        pandoc.RawInline('latex', string.format([[
            \BeginCodeBlock{%s}
        ]], font)),
        block,
        pandoc.RawInline('latex', [[
            \EndCodeBlock
        ]]),
    }
end