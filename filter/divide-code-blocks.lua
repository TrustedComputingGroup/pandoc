-- draw horizontal rules above and below code blocks to separate them nicely

function CodeBlock(block)
    return {
        pandoc.RawInline('latex', [[
            \begin{customcodeblock}
            \textbf{\textit{\textcolor{codeblock-header}{\small \BeginDemarcated{Code}}}}
        ]]),
        block,
        pandoc.RawInline('latex', [[
            \textbf{\textit{\textcolor{codeblock-header}{\small \EndDemarcated{Code}}}}
            \end{customcodeblock}
        ]]),
    }
end