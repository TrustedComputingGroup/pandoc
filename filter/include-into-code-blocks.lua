-- Allow code blocks to include code from other files.

-- Patch the path to include the current script's directory.
package.path = package.path .. ";" .. debug.getinfo(1).source:match("@?(.*/)") .. "?.lua"
utils = require "utils"

function resolveIncludes(text)
    -- A hack to make the regex below work, since gsub can't match `^ | \n`
    if text:match("^!include ") then
        text = "\n" .. text
    end

    return text:gsub("\n(!include )(%C+)", function(_, include_path)
        return utils.readFile(include_path)
    end)
end

function CodeBlock(el)
    for i, class in ipairs(el.classes) do
        if class == 'include' then
            return pandoc.CodeBlock(resolveIncludes(el.text), el.attr)
        end
    end

    return el
end
