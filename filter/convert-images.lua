-- Convert a variety of image formats to PDF

-- Patch the path to include the current script's directory.
package.path = package.path .. ";" .. debug.getinfo(1).source:match("@?(.*/)") .. "?.lua"
utils = require "utils"

-- Only prepend '.cache/' if the path is not already in that directory.
function ensurePathInCache(path)
    if path:find('^[.]cache/') == nil then
        return '.cache/' .. path
    else
        return path
    end
end

-- Wrap calls to drawio in xvfb-run. Note that --no-sandbox has to be the last argument.
-- https://github.com/jgraph/drawio-desktop/issues/249
function drawio(source, dest)
    print(string.format('converting %s using drawio ...', source))
    if not utils.runCommandSuppressOutput(string.format("xvfb-run -a drawio -x -f pdf --crop -o %s %s --no-sandbox 2>&1", dest, source)) then
        print(string.format('failed to convert %s to %s using drawio, falling back to letting LaTeX try to pick it up', source, dest))
        return false
    end
    return true
end

function imagemagick(source, dest)
    print(string.format('converting %s using ImageMagick ...', source))
    if not utils.runCommandSuppressOutput(string.format("convert -density 300 %s %s 2>&1", source, dest)) then
        print(string.format('failed to convert %s to %s using ImageMagick, falling back to letting LaTeX try to pick it up', source, dest))
        return false
    end
    return true
end

function svg(source, dest)
    print(string.format('converting %s using rsvg-convert...', source))
    if not utils.runCommandSuppressOutput(string.format("rsvg-convert --format=pdf --keep-aspect-ratio --output %s %s 2>&1", dest, source)) then
        print(string.format('failed to convert %s to %s using rsvg-convert, falling back to letting LaTeX try to pick it up', source, dest))
        return false
    end
    return true
end

function string:hassuffix(suffix)
    return self:sub(-#suffix):lower() == suffix:lower()
end

function converterFor(filename)
    if filename:hassuffix('.drawio') or filename:hassuffix('.drawio.svg') then
        return drawio
    elseif filename:hassuffix('.jpg') or filename:hassuffix('.png') or filename:hassuffix('.webp') then
        return imagemagick
    elseif filename:hassuffix('.svg') then
        return svg
    end
    return nil
end

function Image (img)
    -- Try to convert anything that is not a pdf, jpg, or png.
    -- This allows us to support file types that LaTeX doesn't (e.g., SVG),
    -- as well as speed up the LaTeX render iterations.
    local converter = converterFor(img.src)
    if converter then
        local new_filename = ensurePathInCache(img.src) .. '.' .. utils.getFileHash(img.src) .. '.convert.pdf'
        utils.ensureDirExists(new_filename)

        if utils.fileExists(new_filename) then
            print(string.format("    not converting %s (already up-to-date as %s)", img.src, new_filename))
            img.src = new_filename
        elseif converter(img.src, new_filename) then
            print(string.format("    converted %s to %s", img.src, new_filename))
            -- Delete stale copies of this file. This makes it easier to cache only the latest converted pdfs.
            -- Don't do this if the "keepstaleimages" variable is set.
            if not PANDOC_WRITER_OPTIONS.variables["keepstaleimages"] then
                utils.deleteFilesExcept(ensurePathInCache(img.src) .. "*.convert.pdf", new_filename)
            end
            img.src = new_filename
        end
    else
        print(string.format("    not converting %s", img.src))
    end
    return img
end
