-- Convert a variety of image formats to PDF

function runCommandSuppressOutput(command)
    -- N.B.: we are using io.popen so we can suppress the output of the command.
    local pipe = io.popen(command)
    if not pipe then
        return false
    end
    pipe:flush()
    local output = pipe:read("*all")
    pipe:close()
    return true
end

-- Wrap calls to drawio in xvfb-run. Note that --no-sandbox has to be the last argument.
-- https://github.com/jgraph/drawio-desktop/issues/249
function drawio(source, dest)
    if not runCommandSuppressOutput(string.format("xvfb-run -a drawio -x -f pdf -o %s %s --no-sandbox 2>&1", dest, source)) then
        print(string.format('failed to convert %s to %s using drawio, falling back to letting latex try to pick it up', img.src, new_filename))
        return false
    end
    print(string.format("  Converted %s to %s with drawio.", source, dest))
    return true
end

function imagemagick(source, dest)
    if not runCommandSuppressOutput(string.format("convert -density 300 %s %s 2>&1", source, dest)) then
        print(string.format('failed to convert %s to %s using imagemagick, falling back to letting latex try to pick it up', img.src, new_filename))
        return false
    end
    print(string.format("  Converted %s to %s with ImageMagick.", source, dest))
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