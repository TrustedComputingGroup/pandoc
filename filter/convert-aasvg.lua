-- Turn aasvg-classed code blocks into figures, retaining other classes on the
-- code block as classes on the figure.

-- Patch the path to include the current script's directory.
package.path = package.path .. ";" .. debug.getinfo(1).source:match("@?(.*/)") .. "?.lua"
utils = require "utils"

function aasvgFigure(code, caption, attrs)
    local filename_base = '.cache/' .. attrs.identifier .. '.' .. utils.getContentsHash('code=' .. code .. 'caption=' .. pandoc.utils.stringify(caption) .. 'attrs=' .. pandoc.utils.stringify(attrs)) .. '.aasvg'
    local filename_svg = filename_base .. '.svg'
    local filename_pdf = filename_base .. '.pdf'

    if utils.fileExists(filename_pdf) then
        print(string.format("    not converting %s (already up-to-date as %s)", attrs.identifier, filename_pdf))
    else
        print(string.format('rendering %s using aasvg ...', filename_svg))
        if not utils.runCommandWithInput(string.format(
            "aasvg --fill > %s 2>&1", filename_svg), code) then
            print(string.format('failed to convert ASCII art SVG (aasvg) diagram to %s using aasvg, falling back to letting LaTeX try to pick it up', filename_svg))
            return false
        else
            print(string.format("    rendered %s to %s", attrs.identifier, filename_svg))
        end

        print(string.format('converting %s to %s using rsvg-convert ...', filename_svg, filename_pdf))
        if not utils.runCommandSuppressOutput(string.format("rsvg-convert --format=pdf --keep-aspect-ratio --output %s %s 2>&1", filename_pdf, filename_svg)) then
            print(string.format('failed to convert %s to %s using rsvg-convert, falling back to letting LaTeX try to pick it up', filename_svg, filename_pdf))
            return false
        else
            print(string.format('    converted %s to %s', filename_svg, filename_pdf))
        end

        -- Delete stale copies of the files. This makes it easier to cache only the latest converted pdfs.
        -- Don't do this if the "keepstaleimages" variable is set.
        if not PANDOC_WRITER_OPTIONS.variables["keepstaleimages"] then
            utils.deleteFilesExcept('.cache/' .. attrs.identifier .. '*.aasvg.svg*', filename_svg)
            utils.deleteFilesExcept('.cache/' .. attrs.identifier .. '*.aasvg.pdf*', filename_pdf)
        end
    end

    local img = pandoc.Image(caption, filename_pdf)
    return pandoc.Figure(img, caption, attrs)
end

function CodeBlock(el)
    local isAasvg = false
    local figure_classes = pandoc.List({})
    for i, class in ipairs(el.classes) do
        if class == 'aasvg' then
            isAasvg = true
        else
            figure_classes:insert(class)
        end
    end
    if isAasvg then
        local caption = {long = pandoc.Plain(pandoc.Str(el.attributes.caption))}
        local attrs = pandoc.Attr(el.identifier, figure_classes)
        el.identifier = nil
        el.classes = {'aasvg'}
        return aasvgFigure(el.text, caption, attrs)
    end
    return el
end
