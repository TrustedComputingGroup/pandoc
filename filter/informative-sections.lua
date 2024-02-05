-- Allow entire sections to be marked as "Informative"

function Header(hdr)
    if FORMAT:match 'latex' then
        if hdr.level == 1 then
            if hdr.classes:find('informative') then
                return {
                    hdr,
                    pandoc.RawBlock('latex', '\\pagecolor{informative-background}\\pagestyle{informative-header-footer}%'),
                }
            else
                return {
                    hdr,
                    pandoc.RawBlock('latex', '\\pagecolor{white}\\pagestyle{normal-header-footer}%'),
                }
            end
        end
    end
    return hdr
end
