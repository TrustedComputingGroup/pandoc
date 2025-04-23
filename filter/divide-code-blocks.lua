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
    local class = block.classes[1]
    local class_spec = code_classes[string.lower(class or "")]
    if not class_spec then
        class_spec = code_classes["normal"]
    end
    font = class_spec["font"]
    return {
        pandoc.RawInline('latex', string.format([[
            \vskip 3pt
            \begin{customcodeblock}
            \textbf{\textit{\textcolor{codeblock-header}{\small \BeginDemarcated{Code}}}}
            %s
        ]], font)),
        block,
        pandoc.RawInline('latex', [[
            \textbf{\textit{\textcolor{codeblock-header}{\small \EndDemarcated{Code}}}}
            \end{customcodeblock}
        ]]),
    }
end