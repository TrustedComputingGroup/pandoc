-- Use tabularx's tabularx environment instead of longtable to write LaTeX tables.
-- Run this filter after pandoc-crossref.

function Length(element)
    local n = 0
    for key, value in pairs(element) do
        n = n + 1
    end
    return n
end

-- This function converts a Pandoc ColSpec object into a colspec for the tabularx environment.
-- https://pandoc.org/lua-filters.html#type-colspec
function TabularColspec(colspec, plain)
    local line = ''
    if not plain then
        line = '|'
    end
    -- OK. 'X' type columns are pretty neat, because tabularx will expand the
    -- columns based on the actual widths required by the contents, resulting
    -- in what can only be described as the platonic ideal proportion for all
    -- table widths.
    -- In reality, a 500 page document with 100 tables in it will literally
    -- take 40 minutes to render. So, we use 'Q' columns, and provide the width
    -- proportions that pandoc already calculated internally when it parsed
    -- the table (which seem to be pretty good).
    local mapping = {
        ['AlignLeft'] = '%sl',
        ['AlignCenter'] = '%sc',
        ['AlignDefault'] = '%sl',
        ['AlignRight'] = '%sr',
    }
    -- If Pandoc has no preferred width for the column, spec it as just [alignment]
    local width = ''
    -- Pandoc may optionally tell us how wide the column should be. If so,
    -- spec the column as a proportion of the line width (which is pretty much
    -- what Pandoc means here).
    -- N.B. we use linewidth instead of textwidth here, because of
    -- landscape tables.
    -- https://tex.stackexchange.com/questions/7680/how-to-make-a-landscape-table-fill-the-whole-width
    if colspec[2] then
        return string.format("%sp{%f\\linewidth-2\\tabcolsep-\\arrayrulewidth}", line, colspec[2])
    else
        return string.format(mapping[colspec[1]], line)
    end
end

-- This function iterates a List of Rows and creates the tabularx code each row.
-- The 'width' parameter is a necessary hint due to potential column-spanning.
-- If 'header' is true, we style every element in bold white on dark gray.
-- If 'plain' is true, we don't change the colors (but keep it bold).
-- https://pandoc.org/lua-filters.html#type-list
-- https://pandoc.org/lua-filters.html#type-row
function TabularRows(rows, width, header, plain)
    local latex_code = ''
    -- Keep a 2d array of bools for which cells we know we need to skip.
    local skips = {}

    -- For each row in the list of rows,
    for i, row in ipairs(rows) do
        local n = 1
        -- Prepare a list of latex snippets to be concatenated together below.
        local row_code = {}

        if not plain then
            latex_code = latex_code .. "\\hline\n"
        end
        -- For each cell in the row,
        for j = 1,width do
            -- We may need to leave this cell empty due to a previous row/colspan.
            if skips[i*width + j] then
                row_code[j] = ' '
            -- Otherwise, let's write some content into the cell.
            elseif row.cells[n] then
                local cell = row.cells[n]
                n = n + 1
                local cell_code = '{' .. pandoc.write(pandoc.Pandoc(cell.contents),'latex') .. '}'
                if header then
                    cell_code = '{\\bfseries ' .. cell_code .. '}'
                end

                -- If this cell spans rows or column, we use \SetCell to tell tabularx about it.
                -- We also need to tell ourselves about it, because we have to write blanks for all
                -- the cells that get covered up empty.
                if cell.row_span > 1 or cell.col_span > 1 then
                    if cell.row_span > 1 then
                        cell_code = string.format('\\multirow{%d}{*}{%s}', cell.row_span, cell_code)

                    end
                    if cell.col_span > 1 then
                        cell_code = string.format('\\multicolumn{%d}{c}{%s}', cell.col_span, cell_code)
                    end
                    
                    for skipi=i,i+cell.row_span-1 do
                        skips[skipi*width + j] = true
                    end
                end

                -- Store this cell's code for concatenation below.
                row_code[j] = cell_code
            end
        end
        if header and not plain then
            -- latex_code = latex_code .. '\\SetRow{table-header-background,fg=white,ht=24pt} '
        end
        -- The entire row is all the cells joined by '&' with a '\\' at the end.
        latex_code = latex_code .. table.concat(row_code, ' & ') .. ' \\\\\n'
    end
    return latex_code
end

-- When writing latex (i.e., output format is latex or pdf), don't rely on the
-- default Pandoc latex writer (which uses longtable). Instead, use tabularx,
-- which gives us the option to draw the full grid of the table.
function Table(tbl)
    if FORMAT =='latex' then
        local latex_code = ''

        -- We use the caption as both the actual table's caption, and the entry
        -- in the list of tables.
        -- If there is no caption, it doesn't go into the list of tables.
        local caption = pandoc.utils.stringify(tbl.caption.long)
        local escaped_caption = ''
        if caption ~= '' then
            -- We have to LaTeX escape the caption in case it contains reserved
            -- characters.
            escaped_caption = '\\protect\\detokenize{' .. caption .. '}'
            -- latex_code = latex_code .. string.format('\\caption{%s}\n', escaped_caption)
        end

        -- -- .unnumbered .unlisted is the traditional pair of classes Pandoc uses
        -- -- to omit something from the TOC. Let's keep that tradition alive.
        -- -- Also, omit tables with no caption or identifier as well.
        -- if (tbl.classes:find('unnumbered') and tbl.classes:find('unlisted'))
        --     or (caption == '' and tbl.identifier == '') then
        --     latex_code = latex_code .. 'entry=none,label=none,'
        -- else
        --     -- N.B.: caption might be the empty string, in the case of a table
        --     -- that goes into the list of tables that has no caption.
        --     latex_code = latex_code .. string.format('entry={%s},', escaped_caption)
        -- end

        -- Typically, #tbl:some-table for crossreferencing/list-of-tables.
        if tbl.identifier ~= '' then
            latex_code = latex_code .. string.format('\\label{%s}\n', tbl.identifier)
        end

        -- latex_code = latex_code .. '\\centering\n'
        latex_code = latex_code .. '\\begin{tabularx}{\\linewidth}{'

        local plain = false
        if tbl.classes:find('plain') then
            plain = true
        end

        -- We have to translate Pandoc's internal ColSpec into the tabularx one.
        local colspec = ''
        for i, spec in ipairs(tbl.colspecs) do
            -- Just concatenate all the colspecs together.
            latex_code = latex_code .. TabularColspec(spec, plain)
        end
        if not plain then
            latex_code = latex_code .. colspec .. '|'
        end
        latex_code = latex_code .. '}\n'
        -- Done with the colspec


        -- if not plain then
        --     -- Here, we get to enable borders for every cell in the table.
        --     -- I.e., the main purpose of this filter.
        --     latex_code = latex_code .. 'hlines={1pt,white},vlines={1pt,white},'
        --     -- Color the headers and cells correctly according to the TCG style.
        --     -- latex_code = latex_code .. 'rowhead={table-header-background},rowfoot={table-header-background},'
        --     latex_code = latex_code .. 'row{odd}={table-odd-background},row{even}={table-even-background},'
        -- end

        -- tabularx uses hbox under the hood to measure the boxes.
        -- This is broken if there are e.g., lists in the box.
        -- This is fixed by telling tabularx to use vbox to measure the box.
        -- see tabularx documentation, section "Library varwidth"
        -- latex_code = latex_code .. 'measure=vbox,'
        
        -- Setting rowhead and rowfoot tells tabularx to replicate these rows
        -- on every page containing the table (i.e., repeat them if the table
        -- crosses the page boundary).
        -- latex_code = latex_code .. string.format('rowhead=%d,rowfoot=%d,', Length(tbl.head.rows), Length(tbl.foot.rows))

        width = Length(tbl.colspecs)

        -- Write out all the header rows (in header).
        latex_code = latex_code .. TabularRows(tbl.head.rows, width, true, plain)

        -- Write out all the body rows.
        -- Typical tables have just one body.
        for i, body in ipairs(tbl.bodies) do
            latex_code = latex_code .. TabularRows(body.body, width, false, plain)
        end

        -- Write out all the footer rows (in header).
        latex_code = latex_code .. TabularRows(tbl.foot.rows, width, true, plain)

        -- One last line for the bottom.
        if not plain then
            latex_code = latex_code .. "\\hline\n"
        end

        -- Close up the environment.
        latex_code = latex_code .. '\\end{tabularx}\n'
        latex_code = latex_code .. ''

        -- Return a raw LaTeX blob with our encoded table.
        print(latex_code)
        return pandoc.RawBlock('tex', latex_code)
    end

    return tbl
end