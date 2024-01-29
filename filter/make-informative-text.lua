-- TODO: Convert this into a Lua filtuer and test it on some docx exports.
-- #!/usr/bin/env python3

-- """
-- Pandoc filter to convert all block quotes to TCG Informative text.
-- """

-- from pandocfilters import toJSONFilter, Str, Div, attributes

-- def informative(key, value, format, meta):
--   if key == 'BlockQuote':
--     return Div(attributes({'custom-style': 'TCG Informative'}), value)

-- if __name__ == "__main__":
--   toJSONFilter(informative)