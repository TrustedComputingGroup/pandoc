-- Use tabularray instead of longtable to write tables.

function TabularrayColspec(colspec)
    local mapping = {
        ['AlignLeft'] = 'Q[l]',
        ['AlignCenter'] = 'Q[c]',
        ['AlignDefault'] = 'Q[c]',
        ['AlignRight'] = 'Q[r]',
    }
    return mapping[colspec[1]]
end

function TabularrayRows(rows, width)
    local latex_code = ''
    local skips = {}
    for i, row in ipairs(rows) do
        local n = 1
        local row_code = {}
        for j = 1,width do
            if skips[i*width + j] then
                row_code[j] = ' '
            elseif row.cells[n] then
                local cell = row.cells[n]
                n = n + 1
                local cell_code = pandoc.write(pandoc.Pandoc(cell.contents),'latex')
                if cell.row_span > 1 or cell.col_span > 1 then
                    cell_code = string.format('\\SetCell[r=%d,c=%d]{c} ', cell.row_span, cell.col_span) .. cell_code
                    
                    for skipi=i,i+cell.row_span-1 do
                        for skipj=j,j+cell.col_span-1 do
                            skips[skipi*width + skipj] = true
                        end
                    end
                end
                row_code[j] = cell_code
            end
        end
        latex_code = latex_code .. table.concat(row_code, ' & ') .. ' \\\\\n'
    end
    return latex_code
end

function Table(tbl)
    if FORMAT =='latex' then
        local latex_code = '\\begin{tblr}{hlines,vlines,'
        if tbl.identifier ~= '' then
            latex_code = latex_code .. string.format('label=%s', tbl.identifier)
        end
        local caption = pandoc.utils.stringify(tbl.caption.long)
        if caption ~= '' then
            latex_code = latex_code .. string.format('caption=%s,entry=%s,', caption, caption)
        else
            latex_code = latex_code .. 'entry=,'
        end
        
        latex_code = latex_code .. 'colspec={'

        width = 1
        for i, spec in ipairs(tbl.colspecs) do
            latex_code = latex_code .. TabularrayColspec(spec)
            width = i
        end

        latex_code = latex_code .. '}}\n'

        latex_code = latex_code .. TabularrayRows(tbl.head.rows, width)
        for i, body in ipairs(tbl.bodies) do
            latex_code = latex_code .. TabularrayRows(body.body, width)
        end
        latex_code = latex_code .. TabularrayRows(tbl.foot.rows, width)

        latex_code = latex_code .. '\\end{tblr}\n'

        print(string.format("Latex: %s", latex_code))

        return pandoc.RawBlock('tex', latex_code)
    end

    return tbl
end