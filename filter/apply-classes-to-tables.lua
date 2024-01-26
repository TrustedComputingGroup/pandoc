-- Pandoc Markdown has trouble with classes on tables.

function Table(el)
    if el.caption.long then
        for key, inline in pairs(pandoc.utils.blocks_to_inlines(el.caption.long)) do
            if inline then
                print(string.format("%s: %s", key, inline))
                -- local split = string.gmatch(inline.content, "%S+")
                -- print("table long caption:")
                -- for word in split do
                --     print(string.format("table caption part: %s", word))
                -- end
            end
        end
    end

    if el.identifier then
        print(string.format("table identifier: %s", el.identifier))
    end

    if el.classes then
        print(string.format("table classes: %s", el.classes))
    end

    if el.attributes then
        print(string.format("table attributes: %s", el.attributes))
    end

    return el
  end
