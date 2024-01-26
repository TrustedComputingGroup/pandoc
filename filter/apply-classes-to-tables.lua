-- Pandoc Markdown has trouble parsing classes on tables: https://github.com/jgm/pandoc/issues/6317
-- Implement our own extension that does the expected thing based on pandoc-crossref's solution
-- (i.e., parse it out of the "caption")

function Table(el)
    if el.caption.long then
        -- This thing has the entire line after "Table:"
        local caption = pandoc.utils.stringify(el.caption.long)
        local name = caption:match('(.*) {')
        local braced = caption:match('{(.*)}')
        print(string.format("name: '%s'", name))
        print(string.format("braced: '%s'", braced))

        if name then
            el.caption.long = {pandoc.Plain(pandoc.Str(name))}
        end
    end

    -- Test

    if el.caption.long then
        print(string.format("table caption: %s", pandoc.utils.stringify(el.caption.long)))
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
