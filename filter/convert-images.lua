-- Convert a variety of image formats to PDF


-- Wrap calls to drawio in xvfb-run. Note that --no-sandbox has to be the last argument.
-- https://github.com/jgraph/drawio-desktop/issues/249
function drawio(source, dest)
    if not os.execute(string.format("xvfb-run -a drawio -x -f pdf -o %s %s --no-sandbox", dest, source)) then
        print(string.format('failed to convert %s to %s using drawio, falling back to letting latex try to pick it up', img.src, new_filename))
        return false
    end
    return true
end

function imagemagick(source, dest)
    if not os.execute(string.format("convert -density 300 %s %s", source, dest)) then
        print(string.format('failed to convert %s to %s using imagemagick, falling back to letting latex try to pick it up', img.src, new_filename))
        return false
    end
    return true
end

local converters = {
    ['.jpg'] = imagemagick,
    ['.png'] = imagemagick,
    ['.svg'] = imagemagick,
    ['.drawio'] = drawio
}

function string:hassuffix(suffix)
    return self:sub(-#suffix) == suffix
end

if FORMAT:match 'latex' then
    function Image (img)
        -- Try to convert anything that is not a pdf, jpg, or png.
        -- This allows us to support file types that latex doesn't (e.g., SVG),
        -- as well as speed up the latex render iterations.
        local file_ext = img.src:match("^.+(%..+)$")
        if file_ext and converters[file_ext] then
            local new_filename = pandoc.sha1(img.src) .. '.temp.pdf'
            if converters[file_ext](img.src, new_filename) then
                img.src = new_filename
            end
        elseif file_ext ~= ".pdf" then
            print(string.format("not converting %s (extension %s)", img.src, file_ext))
        end
        return img
    end
end