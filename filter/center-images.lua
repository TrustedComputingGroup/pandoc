function Image (img)
    -- Center images even if they aren't captioned.
    if FORMAT:match 'latex' then
        return {
            pandoc.RawInline('latex', '\\begin{center}'),
            img,
            pandoc.RawInline('latex', '\\end{center}'),
        }
    end
    return img
end
