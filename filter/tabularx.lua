-- Use tabularx's tabularx environment instead of longtable to write LaTeX tables.
-- Run this filter after pandoc-crossref.

function Length(element)
    local n = 0
    for key, value in pairs(element) do
        n = n + 1
    end
    return n
end

function ColumnWidth(colspec, numcols)
    local width = 1.0/numcols
    if colspec[2] then
        width = colspec[2]
    end
    return string.format('%f\\linewidth-2\\tabcolsep-\\arrayrulewidth', width)
end

-- This function converts a Pandoc ColSpec object into a colspec for the tabularx environment.
-- https://pandoc.org/lua-filters.html#type-colspec
function TabularColspec(colspec, plain, numcols)
    local result = string.format('p{%s}', ColumnWidth(colspec, numcols))
    if not plain then
        result = '|' .. result
    end
    return result
end

-- This function wraps content in a parbox if needed.
function GetCellCode(cell, colspec)
    local blocks = false
    -- for i, block in ipairs(cell.contents) do
    --     print(string.format('Block type: %s', pandoc.utils.type(block)))
    --     if pandoc.utils.type(block) ~= 'Plain' then
    --         blocks = true
    --     end
    -- end

    local cell_code = pandoc.write(pandoc.Pandoc(cell.contents),'latex')
    if blocks then
        local width = 0.5
        if colspec[2] then
            width = colspec[2]
        end
        cell_code = string.format('\\parbox{%f\\linewidth-2\\tabcolsep-\\arrayrulewidth}{%s}', width, cell_code)
    end
    return cell_code
end

-- This function iterates a List of Rows and creates the tabularx code each row.
-- The 'width' parameter is a necessary hint due to potential column-spanning.
-- If 'header' is true, we style every element in bold white on dark gray.
-- If 'plain' is true, we don't change the colors (but keep it bold).
-- https://pandoc.org/lua-filters.html#type-list
-- https://pandoc.org/lua-filters.html#type-row
function TabularRows(rows, header, plain, colspecs)
    local width = Length(colspecs)

    local latex_code = ''
    -- Keep a 2d array of bools for which cells we know we need to skip.
    local skips = {}

    -- For each row in the list of rows,
    for i, row in ipairs(rows) do
        local n = 1
        -- Prepare a list of latex snippets to be concatenated together below.
        local row_code = {}

        local skip_code = ''
        if not plain then
            for j = 1,width do
                if not skips[i*width + j] then
                    skip_code = skip_code .. string.format("\\cline{%d-%d}", j, j)
                end
            end
            skip_code = skip_code .. '\n'
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
                local cell_code = '{' .. GetCellCode(cell, colspecs[j]) .. '}'
                if header then
                    cell_code = '{\\bfseries ' .. cell_code .. '}'
                end

                -- If this sell spans columns, we have to use multicolumn.
                -- If this cell spans rows, we have to use multirow.
                -- We also need to tell ourselves about it, because we have to write blanks for all
                -- the cells that get covered up empty.
                if cell.row_span > 1 or cell.col_span > 1 then
                    if cell.row_span > 1 then
                        cell_code = string.format('\\multirow{%d}{=}{%s}', cell.row_span, cell_code)
                    end
                    local line = ''
                    if not plain then
                        line = '|'
                    end
                    if cell.col_span > 1 then
                        -- Get the total width of all the columns we're spanning...
                        -- This allows us to place block elements inside multicolumn cells.
                        local total_column_width = ColumnWidth(colspecs[j], Length(colspecs))
                        for z = j+1,j+cell.col_span-1 do
                            total_column_width = total_column_width .. '+' .. ColumnWidth(colspecs[z], Length(colspecs))
                        end
                        cell_code = string.format('\\multicolumn{%d}{%sp{%s}%s}{%s}', cell.col_span, line, total_column_width, line, cell_code)
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
        latex_code = latex_code .. skip_code .. table.concat(row_code, ' & ') .. ' \\\\\n'
    end
    return latex_code
end

-- When writing latex (i.e., output format is latex or pdf), don't rely on the
-- default Pandoc latex writer (which uses longtable). Instead, use tabularx,
-- which gives us the option to draw the full grid of the table.
function Table(tbl)
    if FORMAT =='latex' then
        local numbered = true
        -- We use the caption as both the actual table's caption, and the entry
        -- in the list of tables.
        -- If there is no caption, it doesn't go into the list of tables.
        local caption = pandoc.utils.stringify(tbl.caption.long)

        -- .unnumbered .unlisted is the traditional pair of classes Pandoc uses
        -- to omit something from the TOC. Let's keep that tradition alive.
        -- Also, omit tables with no caption or identifier as well.
        if (tbl.classes:find('unnumbered') and tbl.classes:find('unlisted'))
            or (caption == '' and tbl.identifier == '') then
            numbered = false
        end

        local latex_code = ''
        -- latex_code = latex_code .. '\\begin{table}[H]\n'
        latex_code = latex_code .. '\\centering%\n'

        -- WORKAROUND: ltablex has a side effect of incrementing the table counter on all tabularx,
        -- even ones with no caption (or with caption*).
        -- Undo this by decrementing the counter before starting the uncounted table.
        -- Decrementing the counter after the table can cause links in the list of tables to
        -- mistakenly point to the wrong table.
        if not numbered then
            latex_code = latex_code .. '\\addtocounter{table}{-1}'
        end
        latex_code = latex_code .. '\\begin{xltabular}{\\linewidth}{'

        local plain = false
        if tbl.classes:find('plain') then
            plain = true
        end

        -- We have to translate Pandoc's internal ColSpec into the tabularx one.
        local colspec = ''
        for i, spec in ipairs(tbl.colspecs) do
            -- Just concatenate all the colspecs together.
            latex_code = latex_code .. TabularColspec(spec, plain, Length(tbl.colspecs))
        end
        if not plain then
            latex_code = latex_code .. colspec .. '|'
        end
        latex_code = latex_code .. '}\n'
        -- Done with the colspec

        -- Write out all the header rows (in header).
        if Length(tbl.head.rows) > 0 then
            latex_code = latex_code .. TabularRows(tbl.head.rows, true, plain, tbl.colspecs)
            latex_code = latex_code .. '\\endhead\n'
        end

        -- Write out all the footer rows (in header).
        if Length(tbl.foot.rows) > 0 then
            latex_code = latex_code .. TabularRows(tbl.foot.rows, true, plain, tbl.colspecs)
            latex_code = latex_code .. '\\endfoot\n'
        end

        -- Write out all the body rows.
        -- Typical tables have just one body.
        for i, body in ipairs(tbl.bodies) do
            latex_code = latex_code .. TabularRows(body.body, false, plain, tbl.colspecs)
        end

        -- One last line for the bottom.
        if not plain then
            latex_code = latex_code .. "\\hline\n"
        end

        local caption_cmd = 'caption'
        if not numbered then
            caption_cmd = 'caption*'
        end
        local escaped_caption = ''
        if caption ~= '' then
            escaped_caption = '\\protect\\detokenize{' .. caption .. '}'
        end
        -- We have to LaTeX escape the caption in case it contains reserved
        -- characters.
        latex_code = latex_code .. string.format('\\%s{%s}\n', caption_cmd, escaped_caption)

        -- Typically, #tbl:some-table for crossreferencing/list-of-tables.
        if tbl.identifier ~= '' then
            latex_code = latex_code .. string.format('\\label{%s}\n', tbl.identifier)
        end

        -- Close up the environment.
        latex_code = latex_code .. '\\end{xltabular}\n'
        -- latex_code = latex_code .. '\\end{table}\n'
        latex_code = latex_code .. ''

        -- Return a raw LaTeX blob with our encoded table.
        print(latex_code)
        return pandoc.RawBlock('tex', latex_code)
    end

    return tbl
end