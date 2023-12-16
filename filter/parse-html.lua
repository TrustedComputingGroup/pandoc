-- https://tex.stackexchange.com/questions/631243/how-to-render-html-tables-in-markdown-using-pandoc

function RawBlock (raw)
    return raw.format:match 'html'
      and pandoc.read(raw.text, 'html').blocks
      or raw
  end
  
function RawInline (raw)
    return raw.format:match 'html'
      and pandoc.RawInline(raw.text, 'html')
      or raw
  end
  