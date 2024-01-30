-- Convert all informative blocks to TCG Informative text style.
-- Only needed for Word.

function Div(el)
    local class = el.classes[1]
    if(class) then
        el.attributes['custom-style'] = 'TCG Informative'
        el.content:insert(1, pandoc.Para(pandoc.Emph(pandoc.Str(class .. ':'))))
    end
    return el
end
