-- Use xltabular's xltabular environment instead of longtable to write LaTeX tables.
-- Run this filter after pandoc-crossref.

function Length(element)
    local n = 0
    for key, value in pairs(element) do
        n = n + 1
    end
    return n
end

function NormalizeColumns(colspecs)
    local total_width = 0
    for i, colspec in ipairs(colspecs) do
        total_width = total_width + (colspec[2] or 1.0)
    end
    for i, colspec in ipairs(colspecs) do
        colspecs[i][2] = (colspec[2] or 1.0) / total_width
    end
    return colspecs
end

-- The adjustment value for any column width to account for column separators.
local ColumnAdjustmentValue = '-2\\tabcolsep-\\arrayrulewidth'

function ColumnWidth(colspec)
    return string.format('%f\\linewidth', colspec[2])
end

-- This function converts a Pandoc ColSpec object into a colspec for the xltabular environment.
-- https://pandoc.org/lua-filters.html#type-colspec
-- xltabular resets parskip, so override it here (https://tex.stackexchange.com/questions/279207/why-is-parskip-zero-inside-a-tabular)
function TabularColspec(colspec, plain, numcols)
    local column_pre = {
        ['AlignLeft'] = '>{\\RaggedRight\\parskip=\\tabularparskip}',
        ['AlignCenter'] = '>{\\Centering\\parskip=\\tabularparskip}',
        ['AlignDefault'] = '>{\\RaggedRight\\parskip=\\tabularparskip}',
        ['AlignRight'] = '>{\\RaggedLeft\\parskip=\\tabularparskip}',
    }

    local result = string.format('%sp{%s%s}', column_pre[colspec[1]], ColumnWidth(colspec), ColumnAdjustmentValue)
    if not plain then
        result = '|' .. result
    end
    return result
end

function GetCellCode(cell)
    local cell_code = pandoc.write(pandoc.Pandoc(cell.contents),'latex')
    -- \\ is not supported inside a cell. Replace it with a double-newline and a parskip.
    cell_code = cell_code:gsub('\\\\', '\n\n\\tabularparskip')
    return cell_code
end

-- For === Special Header === rows in rowspans.
function SpecialSeparatorRow(width, contents, i, plain)
    local code = ''
    local colspec = 'c'
    if not plain then
        code = code .. '\\hline'
        colspec = '|c|'
    end

    local inner_contents = string.format('\\textbf{\\textit{%s}}', contents)
    code = code .. string.format('\\multicolumn{%d}{%s}{\\cellcolor{table-section-background}\\textcolor{table-section-foreground}{%s}} \\\\*\n', width, colspec, inner_contents)

    return code
end

-- TODO: This code's a real spaghetti factory. Refactor it in the future.
function TabularRow(height, colspecs, skips, rows_with_rowspans, row, i, plain, no_first_hline, header)
    local width = Length(colspecs)

    -- Special case: this row's first cell spans the entire table and begins and ends with ===.
    if row.cells[1] and row.cells[1].col_span == width then
        local contents = pandoc.utils.stringify(row.cells[1].contents):match('===+ ?(.*) ===+')
        if contents then
            return SpecialSeparatorRow(width, contents, i, plain)
        end
    end

    local n = 1
    -- Prepare a list of latex snippets to be concatenated together below.
    local row_code = {}

    -- Draw horizontal rules using cline, for each non-skipped cell (so we don't draw a line through a rowspan cell).
    local clines_code = ''
    local any_skips = false
    if not plain and (i > 1 or not no_first_hline) then
        local j = 1
        while j <= width do
            if skips[(i-1)*width + j] then
                any_skips = true
                j = j + skips[(i-1)*width + j]
            else
                clines_code = clines_code .. string.format("\\cline{%d-%d}", j, j)
                j = j + 1
            end
        end
        -- Simplify a whole row of clines as just an hline.
        -- In addition to making the LaTeX code prettier, this serves an
        -- important purpose. clines can be separated from their row
        -- (in the case of a page break) while hlines are kept with with
        -- their row.
        -- Since xltabular avoids breaking rowspans across pages,
        -- we completely avoid problems like 
        -- https://github.com/TrustedComputingGroup/pandoc/issues/115
        -- by doing this.
        if not any_skips then
            clines_code = "\\hline"
        end
    end

    -- For each cell in the row,
    local j = 1
    while j <= width do
        -- We may need to leave this cell empty due to a previous row/colspan.
        if skips[(i-1)*width + j] then
            -- Even more complicated: We may need to put a multicolumn here (in the event that there are multiple
            -- skipped cells in a row).
            local skipstart = j
            local skipend = j + skips[(i-1)*width + j] - 1
            if skipstart == skipend then
                table.insert(row_code, ' ')
            else
                local left_line = ''
                local right_line = ''
                if not plain then
                    if skipstart == 1 then
                        -- We only have to put a | on the left side of the colspec if we're the leftmost column.
                        left_line = '|'
                    end
                    right_line = '|'
                end
                table.insert(row_code, string.format('\\multicolumn{%d}{%sl%s}{ }', (skipend-skipstart) + 1, left_line, right_line))
            end
            j = j + (skipend-skipstart) + 1
        -- Otherwise, let's write some content into the cell.
        elseif row.cells[n] then
            local cell = row.cells[n]
            local cell_code = '{' .. GetCellCode(cell) .. '}'
            if header then
                cell_code = '{\\bfseries ' .. cell_code .. '}'
            end

            -- If this sell spans columns, we have to use multicolumn.
            -- If this cell spans rows, we have to use multirow.
            -- We also need to tell ourselves about it, because we have to write blanks for all
            -- the cells that get covered up empty.
            if cell.row_span > 1 or cell.col_span > 1 then
                if cell.row_span > 1 then
                    for skipi=i,i+cell.row_span-1 do
                        rows_with_rowspans[skipi] = true
                    end
                    cell_code = string.format('\\multirow{%d}{=}{%s}', cell.row_span, cell_code)
                end
                local left_line = ''
                local right_line = ''
                if not plain then
                    if j == 1 then
                        -- We only have to put a | on the left side of the colspec if we're the leftmost column.
                        left_line = '|'
                    end
                    right_line = '|'
                end
                if cell.col_span > 1 then
                    -- Get the total width of all the columns we're spanning.
                    -- This allows us to place block elements inside multicolumn cells.
                    local total_column_width = ColumnWidth(colspecs[j])
                    for z = j+1,j+cell.col_span-1 do
                        total_column_width = total_column_width .. '+' .. ColumnWidth(colspecs[z])
                    end
                    total_column_width = total_column_width .. ColumnAdjustmentValue
                    cell_code = string.format('\\multicolumn{%d}{%sp{%s}%s}{%s}', cell.col_span, left_line, total_column_width, right_line, cell_code)
                end
                
                -- Mark skips for the next rows but not the current one.
                -- tabularx/multirow/multicolumn want us to NOT provide empty "& &" cells after a multicolumn.
                -- Multirow cells DO need empty "& &" cells populated.
                for skipi=i+1,i+cell.row_span-1 do
                    skips[(skipi-1)*width + j] = cell.col_span
                end
            end

            -- Store this cell's code for concatenation below.
            table.insert(row_code, cell_code)
            -- Increment j by the colspan of the current cell.
            j = j + cell.col_span
            n = n + 1
        else
            -- Not skipping this cell, but we have no more data. That means we're done with this row.
            break
        end
    end

    local linebreak = '\\\\'
    if header or i == height or rows_with_rowspans[i] then
        -- Use the \\* break which keeps rows together even when there's a page break.
        -- Use this on header/footer lines, the last row in the body, and on
        -- any rows where there was a rowspan.
        linebreak = linebreak .. '*'
    end

    return clines_code .. ' ' .. table.concat(row_code, ' & ') .. string.format(' %s\n', linebreak)
end

-- This function iterates a List of Rows and creates the code for each row.
-- If 'header' is true, we style every element in bold.
-- If 'no_first_hline' is true, we omit the first hline (if applicable).
-- If 'plain' is true, we don't change the colors (but keep it bold).
-- https://pandoc.org/lua-filters.html#type-list
-- https://pandoc.org/lua-filters.html#type-row
function TabularRows(rows, header, no_first_hline, plain, colspecs)
    local height = Length(rows)
    local latex_code = ''
    -- Keep a 2d array of bools for which cells we know we need to skip.
    local skips = {}
    local rows_with_rowspans = {}

    -- For each row in the list of rows,
    for i, row in ipairs(rows) do
        local row_code = TabularRow(height, colspecs, skips, rows_with_rowspans, row, i, plain, no_first_hline, header)

        -- The entire row is all the cells joined by '&' with a '\\' at the end.
        latex_code = latex_code .. row_code .. '\n'
    end

    latex_code = latex_code .. '\n'
    return latex_code
end

-- When writing latex (i.e., output format is latex or pdf), don't rely on the
-- default Pandoc latex writer (which uses longtable). Instead, use xltabular,
-- which gives us the option to draw the full grid of the table.
function Table(tbl)
    if FORMAT =='latex' then
        tbl.colspecs = NormalizeColumns(tbl.colspecs)
        local latex_code = ''

        local plain = false
        if tbl.classes:find('plain') then
            plain = true
        end

        -- We use the caption as both the actual table's caption, and the entry
        -- in the list of tables.
        -- Escape the caption if needed.
        local caption = pandoc.utils.stringify(tbl.caption.long)
        local escaped_caption = ''
        if caption ~= '' then
            escaped_caption = '\\protect\\detokenize{' .. caption .. '}'
        end

        local numbered = true

        -- .unnumbered .unlisted is the traditional pair of classes Pandoc uses
        -- to omit something from the TOC. Let's keep that tradition alive.
        -- Also, omit tables with no caption as well.
        if (tbl.classes:find('unnumbered') and tbl.classes:find('unlisted'))
            or (caption == '') then
            numbered = false
        end

        -- Choose the right command for the caption (caption if numbered; caption* if not)
        local caption_cmd = 'caption'
        if not numbered then
            caption_cmd = 'caption*'
        end

        -- WORKAROUND: All caption commands are currently incrementing the table counter.
        -- Undo this by decrementing the counter before starting the uncounted table.
        -- Decrementing the counter after the table can cause links in the list of tables to
        -- mistakenly point to the wrong table.
        if not numbered then
            latex_code = latex_code .. '\\addtocounter{table}{-1}\n'
        end

        --
        -- Begin the xltabular environment
        --

        -- N.B., we use linewidth here instead of textwidth, because (experimentally) textwidth
        -- doesn't get updated in the landscape environment.
        -- This will cause problems with tables inside of tables, but we don't support that.
        latex_code = latex_code .. '\\begin{xltabular}{\\linewidth}{'
        --
        -- Specify the columns
        --

        local colspec = ''
        for i, spec in ipairs(tbl.colspecs) do
            -- Just concatenate all the colspecs together.
            latex_code = latex_code .. TabularColspec(spec, plain, Length(tbl.colspecs))
        end
        if not plain then
            latex_code = latex_code .. colspec .. '|'
        end
        latex_code = latex_code .. '}\n'
        
        --
        -- Create the first header. This consists of the caption, a top line, and any header lines.
        --

        if escaped_caption ~= '' or tbl.identifier ~= '' then
            if tbl.identifier ~= '' then
                -- The label, if we have one, goes inside of the caption command.
                latex_code = latex_code .. string.format('\\%s{%s \\label{%s}}\n', caption_cmd, escaped_caption, tbl.identifier)
            else
                latex_code = latex_code .. string.format('\\%s{%s}\n', caption_cmd, escaped_caption)
            end
            latex_code = latex_code .. '\\\\\n'
        end

        if Length(tbl.head.rows) > 0 then
            latex_code = latex_code .. TabularRows(tbl.head.rows, true, false, plain, tbl.colspecs)
        end
        latex_code = latex_code .. '\\endfirsthead\n'

        --
        -- Create the not-first header. This is the same as the first header, except there's no caption
        -- and there's a continuation note instead.
        --

        -- Write out all the header rows.
        latex_code = latex_code .. string.format('\\multicolumn{%s}{c}\n{\\Centering\\textit{\\Centering (continued from previous page)}}\\\\\n', Length(tbl.colspecs))
        if Length(tbl.head.rows) > 0 then
            latex_code = latex_code .. TabularRows(tbl.head.rows, true, false, plain, tbl.colspecs)
        end
        -- There's always a header, even if there are no header rows. This avoids
        -- edge cases where a continued table loses its leading hline.
        latex_code = latex_code .. '\\endhead\n'

        --
        -- Create the footer.
        --

        -- Write out all the footer rows.
        if Length(tbl.foot.rows) > 0 then
            latex_code = latex_code .. TabularRows(tbl.foot.rows, true, true, plain, tbl.colspecs)
            if not plain then
                latex_code = latex_code .. '\\hline\n'
            end
        end
        latex_code = latex_code .. string.format('\\multicolumn{%s}{c}\n{\\Centering\\textit{\\Centering(continued on next page)}}\\\\\n', Length(tbl.colspecs))
        latex_code = latex_code .. '\\endfoot\n'

        -- Write out all the footer rows again for the last footer.
        latex_code = latex_code .. TabularRows(tbl.foot.rows, true, false, plain, tbl.colspecs)
        if not plain then
            latex_code = latex_code .. '\\hline\n'
        end
        latex_code = latex_code .. '\\endlastfoot\n'

        --
        -- Body
        --

        -- Write out all the body rows.
        -- Typical tables have just one body.
        for i, body in ipairs(tbl.bodies) do
            latex_code = latex_code .. TabularRows(body.body, false, false, plain, tbl.colspecs)
        end

        if not plain then
            latex_code = latex_code .. '\\hlineifmdframed\n'
        end

        --
        -- End the tabular environment
        --

        latex_code = latex_code .. '\\end{xltabular}\n'

        -- Return a raw LaTeX blob with our encoded table.
        return pandoc.RawBlock('tex', latex_code)
    end

    return tbl
end