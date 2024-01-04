-- Center images (i.e., those produced by Mermaid): https://pandoc.org/lua-filters.html#center-images-in-latex-and-html-output

function string:hassuffix(suffix)
    return self:sub(-#suffix) == suffix
end

if FORMAT:match 'latex' then
    function Image (elem)
        return elem.src:hassuffix(".pdf")
            -- Surround all pdf images with image-centering raw LaTeX.
            and {
                pandoc.RawInline('latex', '\\hfill\\break{\\centering'),
                elem,
                pandoc.RawInline('latex', '\\par}')
            }
            or elem
    end
end