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

function Table(tbl)
    if FORMAT =='latex' then
        local latex_code = '\\begin{tblr}{hlines,vlines,colspec={'

        print(string.format("Table: %s", pandoc.utils.stringify(tbl.caption.long)))
        for i, spec in ipairs(tbl.colspecs) do
            latex_code = latex_code .. TabularrayColspec(spec)
        end

        latex_code = latex_code .. '}}\n'

        for i, hdr in ipairs(tbl.head.rows) do
            local row = {}
            for j, cell in ipairs(hdr.cells) do
                local setcell_code = string.format('\\SetCell[r=%d,c=%d]{c}', cell.row_span, cell.col_span)
                row[j] = setcell_code .. pandoc.write(pandoc.Pandoc(cell.contents),'latex')
            end
            latex_code = latex_code .. table.concat(row, " & ") .. " \\\\\n"
        end
        for i, body in ipairs(tbl.bodies) do
            for j, thisrow in ipairs(body.body) do
                local row = {}
                for k, cell in ipairs(thisrow.cells) do
                    local setcell_code = string.format('\\SetCell[r=%d,c=%d]{c}', cell.row_span, cell.col_span)
                    row[k] = setcell_code .. pandoc.write(pandoc.Pandoc(cell.contents),'latex')
                end
                latex_code = latex_code .. table.concat(row, " & ") .. " \\\\\n"
            end
        end
        for i, foot in ipairs(tbl.foot.rows) do
            print(string.format("  Foot: %s", foot))
        end
        latex_code = latex_code .. '\\end{tblr}\n'

        print(string.format("Latex: %s", latex_code))

        return pandoc.RawBlock('tex', latex_code)
    end

    return tbl
end