 --[[
MIT License

Copyright (c) 2017-2021 pandoc Lua filters contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

tables-vrules - adds vertical rules to tables for latex output

Copyright:  © 2021 Christophe Agathon <christophe.agathon@gmail.com>

License:    MIT – see license for details

Credits:    marijnschraagen for the original Latex hack

Output:     latex, pdf.

Usage:      See README.md for details

--]]
local List = require 'pandoc.List'

local vars = {}

function get_vars (meta)
  vars.vrules = meta['tables-vrules']
  vars.hrules = meta['tables-hrules']
end

function repl_midrules(m1, m2)
  if m2:match('^\\[%w]+rule') then
    -- don't double the rule
    return m1 .. m2
  else
    return m1 .. '\n\\midrule\n' .. m2
  end
end

function Table(table)
  local returned_list
  local latex_code = ''
  local coldef =''
  local envdef =''
  local new_coldef =''
  local end_line = ''

  if not vars.vrules and not vars.hrules then return nil end

  if FORMAT:match 'latex' then

    -- Get latex code for the whole table
    latex_code = pandoc.write ( pandoc.Pandoc({table}),'latex' )

    -- Rewrite column definition to add vertical rules if needed
    if vars.vrules then
      envdef, begdef, coldef, enddef =
          latex_code:match("((\\begin{longtable}%[[^%]]*%]{@{})(.*)(@{}}))")

      if coldef then
        if coldef:match('^[lrc]+$') then
          -- old style
          new_coldef = coldef:gsub('(.)', '|%1') .. '|'
        else
          -- asuming new style
	  new_coldef = coldef:gsub('(>)', '|%1') .. '|'
	end
	latex_code = latex_code:sub(envdef:len() + 1)
      end
    end

    -- Add \midrules after each row if needed
    if vars.hrules then
      latex_code = latex_code:gsub('(\\\\\n)([\\%w]+)', repl_midrules)
    end

    -- Return modified latex code as a raw block
    if vars.vrules then
      returned_list = List:new{pandoc.RawBlock('tex',
                               begdef .. new_coldef .. enddef ..
                               latex_code)}
    else
      returned_list = List:new{pandoc.RawBlock('tex', latex_code)}
    end
  end
  return returned_list
end

function Meta(meta)
  -- We have to add this since Pandoc doesn't because there are no
  -- table anymore in the AST. We converted them in RawBlocks

  if not vars.vrules and not vars.hrules then return nil end
  includes = [[
%begin tables-vrules.lua
\usepackage{longtable,booktabs,array}
\usepackage{calc} % for calculating minipage widths
% Correct order of tables after \paragraph or \subparagraph
\usepackage{etoolbox}
\makeatletter
\patchcmd\longtable{\par}{\if@noskipsec\mbox{}\fi\par}{}{}
\makeatother
% Allow footnotes in longtable head/foot
\IfFileExists{footnotehyper.sty}{\usepackage{footnotehyper}}{\usepackage{footnote}}
\makesavenoteenv{longtable}
\setlength{\aboverulesep}{0pt}
\setlength{\belowrulesep}{0pt}
\renewcommand{\arraystretch}{1.3}
%end tables-vrules.lua
]]

  if meta['header-includes'] then
    table.insert(meta['header-includes'], pandoc.RawBlock('tex', includes))
  else
    meta['header-includes'] = List:new{pandoc.RawBlock('tex', includes)}
  end

  return meta
end

return {{Meta = get_vars}, {Table = Table}, {Meta = Meta}}