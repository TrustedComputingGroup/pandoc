-- use regular markdown quotes as "informative text" blocks

function BlockQuote(el)
    local result = pandoc.List({
        pandoc.RawBlock('latex', '\\vskip 0.5em'),
        pandoc.RawBlock('latex', '\\begin{mdframed}[linewidth=0pt,backgroundcolor=informative-background,skipabove=\\parskip,nobreak=true]'),
        pandoc.RawBlock('latex', '\\textbf{\\textit{\\textcolor{informative-header}{\\small \\BeginDemarcated{Informative comment}}}}'),
        pandoc.RawBlock('latex', '\\color{informative-foreground}')
    })
    result:extend(el.content)
    result:extend(pandoc.List({
        pandoc.RawBlock('latex', '\\textbf{\\textit{\\textcolor{informative-header}{\\small \\EndDemarcated{Informative comment}}}}'),
        pandoc.RawBlock('latex', '\\end{mdframed}')
    }))
    return result
  end