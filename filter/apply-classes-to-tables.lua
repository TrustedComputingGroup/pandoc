-- Pandoc Markdown has trouble parsing classes on tables: https://github.com/jgm/pandoc/issues/6317
-- Implement our own extension that does the expected thing based on pandoc-crossref's solution
-- (i.e., parse it out of the "caption")
-- This filter takes a table whose caption is "My Table {#tbl:my-table .my-attribute}"
-- and makes it a table whose caption is "My Table", whose ID is "tbl:my-table", and whose class is "my-attribute".
-- TODO: Get rid of this filter if Pandoc's normal markdown parser supports this obvious syntax

function Table(el)
    if el.caption.long then
        -- This thing has the entire line after "Table:"
        local caption = pandoc.utils.stringify(el.caption.long)
        local name = caption:match('(.*) ?{')
        if name then
            -- Trim trailing spaces on name, to support any number of spaces between the title and opening {
            name = name:gsub('%s*$', '')
            el.caption.long = {pandoc.Plain(pandoc.Str(name))}
        elseif caption then
            name = caption
            el.caption.long = {pandoc.Plain(pandoc.Str(name))}
        end

        local braced = caption:match('{(.*)}')
        if braced then
            for attribute in braced:gmatch("%S+") do
                local id = attribute:match("^#(.*)")
                if id then
                    el.identifier = id
                end
                local class = attribute:match("^%.(.*)")
                if class then
                    el.classes:insert(class)
                end
            end
        end
    end

    return el
  end
