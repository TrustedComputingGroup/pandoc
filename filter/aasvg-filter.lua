-- Turn aasvg-classed code blocks into figures, retaining other classes on the
-- code block as classes on the figure.

function runCommandWithInput(command, input)
    local pipe = io.popen(command, "w")
    if not pipe then
        return false
    end
    pipe:write(input)
    pipe:flush()
    pipe:close()
    return true
end

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

function getContentsHash(contents)
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

function aasvgFigure(code, caption, attrs)
    local filename_base = getContentsHash('code=' .. code .. 'caption=' .. pandoc.utils.stringify(caption) .. 'attrs=' .. pandoc.utils.stringify(attrs)) .. '.aasvg'
    local filename_svg = filename_base .. '.svg'
    local filename_pdf = filename_base .. '.pdf'

    if fileExists(filename_pdf) then
        print(string.format('%s already exists; not re-rendering it', filename_pdf))
    else
        print(string.format('rendering %s using aasvg ...', filename_svg))
        if not runCommandWithInput(string.format(
            "aasvg --fill > %s 2>&1", filename_svg), code) then
            print(string.format('failed to convert ASCII art SVG (aasvg) diagram to %s using aasvg, falling back to letting LaTeX try to pick it up', filename_svg))
            return false
        end

        print(string.format('converting %s to %s using rsvg-convert ...', filename_svg, filename_pdf))
        if not runCommandSuppressOutput(string.format("rsvg-convert --format=pdf --keep-aspect-ratio --output %s %s 2>&1", filename_pdf, filename_svg)) then
            print(string.format('failed to convert %s to %s using rsvg-convert, falling back to letting LaTeX try to pick it up', filename_svg, filename_pdf))
            return false
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
