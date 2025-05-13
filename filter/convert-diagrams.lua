-- Turn mermaid and plantuml code blocks into figures, retaining other classes
-- on the code block as classes on the figure.

-- Patch the path to include the current script's directory.
package.path = package.path .. ";" .. debug.getinfo(1).source:match("@?(.*/)") .. "?.lua"
utils = require "utils"

image_attrs =
{
    ["pdf"] = {},
    ["html"] = {
        "", -- No identifier
        {}, -- No classes
        {width = "500px"}
    },
}

mermaid_extension =
{
    ["pdf"] = ".mermaid.pdf",
    ["html"] = ".mermaid.svg",
}

-- Recursively resolve all UML includes ourselves, instead of letting plantuml do it.
-- This ensures that cache files become invalidated if any included file changes.
-- Doesn't try to detect infinite loops.
function resolveUmlIncludes(uml_src_path, uml_content)
    local src_dirname = uml_src_path:match("(.*/)")

    -- A hack to make the regex below work, since gsub can't match `^ | \n`
    if uml_content:match("^!include ") then
        uml_content = "\n" .. uml_content
    end

    return uml_content:gsub("\n(!include )(%C+)", function(term, include_path)
        -- Don't correct absolute paths.
        if include_path:sub(1, 1) ~= "/" then
            include_path = src_dirname .. include_path
        end

        print("    resolving UML include: " .. include_path)

        included_content = utils.readFile(include_path)

        return resolveUmlIncludes(include_path, included_content)
    end)
end

-- `convert_command` must contain a single '%s', which will be replaced with the
-- path to the output file.
function convertFigure(code, caption, attrs, extension, convert_command)
    local filename = '.cache/' .. attrs.identifier .. '.' .. utils.getContentsHash('code=' .. code .. 'caption=' .. pandoc.utils.stringify(caption) .. 'attrs=' .. pandoc.utils.stringify(attrs)) .. extension
    if utils.fileExists(filename) then
        print(string.format("    not converting %s (already up-to-date as %s)", attrs.identifier, filename))
    else
        print(string.format('rendering %s...', filename))
        if not utils.runCommandWithInput(string.format(convert_command, filename), code) then
            print(string.format('failed to convert diagram to %s, falling back to letting LaTeX try to pick it up', filename))
            return false
        else
            print(string.format('    rendered %s to %s', attrs.identifier, filename))
        end
        -- Delete stale copies of this file. This makes it easier to cache only the latest converted diagrams.
        -- Don't do this if the "keepstaleimages" variable is set.
        if not PANDOC_WRITER_OPTIONS.variables["keepstaleimages"] then
            utils.deleteFilesExcept('.cache/' .. attrs.identifier .. '*' .. extension .. '*', filename)
        end
    end

    local img = pandoc.Image(caption, filename, "", image_attrs[FORMAT] or image_attrs["pdf"])
    return pandoc.Figure(img, caption, attrs)
end

function mermaidFigure(code, caption, attrs)
    return convertFigure(code, caption, attrs, mermaid_extension[FORMAT] or mermaid_extension["pdf"],
        "mmdc --configFile /resources/filters/mermaid-config.json --puppeteerConfigFile ./.puppeteer.json --width 2000 --height 2000 --backgroundColor transparent --pdfFit --input - --output %s 2>&1")
end

function plantUmlFigure(code, caption, attrs)
    code = resolveUmlIncludes("./", code)
    return convertFigure(code, caption, attrs, ".plantuml.svg", "java -jar /usr/share/plantuml.jar -tsvg -pipe 2>&1 > %s")
end

function CodeBlock(el)
    local diagramType = nil

    local figure_classes = pandoc.List({})
    for i, class in ipairs(el.classes) do
        if class == 'mermaid' or class == 'plantuml' then
            diagramType = class
        else
            figure_classes:insert(class)
        end
    end

    if diagramType ~= nil then
        local caption = {long = pandoc.Plain(pandoc.Str(el.attributes.caption))}
        local attrs = pandoc.Attr(el.identifier, figure_classes)

        if diagramType == 'mermaid' then
            return mermaidFigure(el.text, caption, attrs)
        end
        if diagramType == 'plantuml' then
            return plantUmlFigure(el.text, caption, attrs)
        end
    end
    return el
end
