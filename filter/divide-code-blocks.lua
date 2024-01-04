-- draw horizontal rules above and below code blocks to separate them nicely

function CodeBlock(block)
    return {
        pandoc.RawInline('latex', '\\noindent\\textcolor{gray}{\\rule{\\textwidth}{0.25pt}}'),
        block,
        pandoc.RawInline('latex', '\\noindent\\textcolor{gray}{\\rule{\\textwidth}{0.25pt}}'),
    }
end