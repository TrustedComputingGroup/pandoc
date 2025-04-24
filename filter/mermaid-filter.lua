-- Turn mermaid-classed code blocks into figures, retaining other classes on the
-- code block as classes on the figure.

output_classes =
{
    ["pdf"] = {
        ["extension"] = ".mermaid.pdf",
        ["image_attrs"] = {},
    },
    ["html"] = {
        ["extension"] = ".mermaid.svg",
        ["image_attrs"] = {
            "", -- No identifier
            {}, -- No classes
            {width = "500px"}
        },
    }
}

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

function mermaidFigure(code, caption, attrs)
    output_class = output_classes[FORMAT] or output_classes["pdf"]

    local filename = getContentsHash('code=' .. code .. 'caption=' .. pandoc.utils.stringify(caption) .. 'attrs=' .. pandoc.utils.stringify(attrs)) .. output_class["extension"]
    if fileExists(filename) then
        print(string.format('%s already exists; not re-rendering it', filename))
    else
        print(string.format('rendering %s using Mermaid ...', filename))
        if not runCommandWithInput(string.format(
            "mmdc --configFile /resources/filters/mermaid-config.json --puppeteerConfigFile ./.puppeteer.json --width 2000 --height 2000 --backgroundColor transparent --pdfFit --input - --output %s 2>&1", filename), code) then
            print(string.format('failed to convert Mermaid diagram to %s using mmdc, falling back to letting LaTeX try to pick it up', filename))
            return false
        end
    end

    local img = pandoc.Image(caption, filename, "", output_class["image_attrs"])
    return pandoc.Figure(img, caption, attrs)
end

function CodeBlock(el)
    local isMermaid = false
    local figure_classes = pandoc.List({})
    for i, class in ipairs(el.classes) do
        if class == 'mermaid' then
            isMermaid = true
        else
            figure_classes:insert(class)
        end
    end
    if isMermaid then
        local caption = {long = pandoc.Plain(pandoc.Str(el.attributes.caption))}
        local attrs = pandoc.Attr(el.identifier, figure_classes)
        el.identifier = nil
        el.classes = {'mermaid'}
        return mermaidFigure(el.text, caption, attrs)
    end
    return el
end
