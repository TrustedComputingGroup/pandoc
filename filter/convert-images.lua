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

function getFileHash(file)
    local f = assert(io.open(file, "r"))
    local contents = f:read("*all")
    f:close()
    return pandoc.sha1(contents):sub(1,10)
end

function fileExists(file)
    local f = io.open(file)
    if f then
        f:close()
        return true
    end
    return false
end

function deleteFilesExcept(pattern, keep)
    local f = io.popen(string.format("ls %s", pattern))
    for filename in f:lines() do
        if filename ~= keep then
            os.remove(filename)
            print(string.format("        deleted stale file %s", filename))
        end
    end
    f:close()
end

-- Wrap calls to drawio in xvfb-run. Note that --no-sandbox has to be the last argument.
-- https://github.com/jgraph/drawio-desktop/issues/249
function drawio(source, dest)
    print(string.format('converting %s using drawio...', source))
    if not runCommandSuppressOutput(string.format("xvfb-run -a drawio -x -f pdf -o %s %s --no-sandbox 2>&1", dest, source)) then
        print(string.format('failed to convert %s to %s using drawio, falling back to letting latex try to pick it up', source, dest))
        return false
    end
    return true
end

function imagemagick(source, dest)
    print(string.format('converting %s using imagemagick...', source))
    if not runCommandSuppressOutput(string.format("convert -density 300 %s %s 2>&1", source, dest)) then
        print(string.format('failed to convert %s to %s using imagemagick, falling back to letting latex try to pick it up', source, dest))
        return false
    end
    return true
end

function string:hassuffix(suffix)
    return self:sub(-#suffix) == suffix
end

function converterFor(filename)
    if filename:hassuffix('.drawio') or filename:hassuffix('.drawio.svg') then
        return drawio
    end
    if filename:hassuffix('.jpg') or filename:hassuffix('.png') or filename:hassuffix('.svg') then
        return imagemagick
    end
    return nil
end

function Image (img)
    -- Try to convert anything that is not a pdf, jpg, or png.
    -- This allows us to support file types that latex doesn't (e.g., SVG),
    -- as well as speed up the latex render iterations.
    local converter = converterFor(img.src)
    if converter then
        local new_filename = img.src .. '.' .. getFileHash(img.src) .. '.convert.pdf'
        if fileExists(new_filename) then
            print(string.format("    not converting %s (already up-to-date as %s)", img.src, new_filename))
            img.src = new_filename
        elseif converter(img.src, new_filename) then
            print(string.format("    converted %s to %s", img.src, new_filename))
            -- Delete stale copies of this file. This makes it easier to cache only the latest converted pdfs
            deleteFilesExcept(img.src .. ".*.convert.pdf", new_filename)
            img.src = new_filename
        end
    else
        print(string.format("    not converting %s", img.src))
    end
    return img
end