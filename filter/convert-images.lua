-- Convert a variety of image formats to PDF

function string:hassuffix(suffix)
    return self:sub(-#suffix) == suffix
end

if FORMAT:match 'latex' then
    function Image (img)
        -- Try to convert anything that is not a pdf, jpg, or png.
        -- This allows us to support file types that latex doesn't (e.g., SVG),
        -- as well as speed up the latex render iterations.
        if not img.src or img.src:hassuffix('pdf') or img.src:hassuffix('jpg') or img.src:hassuffix('png') then
            return img
        end
        local new_filename = pandoc.sha1(img.src) .. '.temp.pdf'
        if not os.execute(string.format("convert -density 300 %s %s", img.src, new_filename)) then
            print(string.format('failed to convert %s to %s, falling back to letting latex try to pick it up', img.src, new_filename))
            return img
        end
        img.src = new_filename
        return img
    end
end