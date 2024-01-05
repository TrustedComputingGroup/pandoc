-- draw horizontal rules above and below code blocks to separate them nicely

function CodeBlock(block)
    return {
        pandoc.RawInline('latex', [[
            \vskip 0.5em
            \begin{customcodeblock}
        ]]),
        block,
        pandoc.RawInline('latex', [[
            \end{customcodeblock}
        ]]),
    }
end