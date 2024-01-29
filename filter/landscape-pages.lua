-- If a table has the "landscape" class on it, wrap it in the landscape environment.

function Table(el)
    if el.classes:find('landscape') then
        return {
            pandoc.RawBlock('latex', '\\begin{landscape}%'),
            el,
            pandoc.RawBlock('latex', '\\end{landscape}')
        }
    end
    return el
  end

-- Support figures as well. Figures contain one or more Images, so we wrap the entire
-- Figure with landscape if any of the enclosed Images have the landscape class.

function Figure(el)
    local foundLandscape = false
    -- Iterate the contents of the figure to see if *any* of the images inside have
    -- the 'landscape' class.
    el:walk {
        Image = function (p)
            if p.classes:find('landscape') then
                foundLandscape = true
            end
        end,
    }
    -- Also, support the figure itself having the landscape class for some reason.
    if foundLandscape or el.classes:find('landscape') then
        return {
            pandoc.RawBlock('latex', '\\begin{landscape}%'),
            el,
            pandoc.RawBlock('latex', '\\end{landscape}')
        }
    end
    return el
  end
