-- Use longtable* instead of longtable when there is no caption.
function Table(table)
  if FORMAT =='latex' and pandoc.utils.stringify(table.caption) == '' then
    latex_code = pandoc.write(pandoc.Pandoc({table}),'latex')
    latex_code = latex_code:gsub("{longtable}", "{longtable*}")
    return pandoc.RawBlock('tex', latex_code)
  end
  return table
end
