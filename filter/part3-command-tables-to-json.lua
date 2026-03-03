local FieldType = {
    COMMAND = 1,
    HANDLE = 2,
    PARAMETER = 3,
}

-- Extracts the field type from a cell of the form `========== [TYPE] ==========`
function getFieldTypeFromSpan(text)
    -- ^    : Start of string
    -- %=+  : One or more "=" (the % escapes the = character)
    -- %s*  : Zero or more spaces
    -- (.-) : Capture the shortest possible sequence of any characters (the target text)
    -- %s*  : Zero or more spaces
    -- %=+  : One or more "="
    -- $    : End of string
    local extracted = text:match("^%=+%s*(.-)%s*%=+$")

    if extracted == "Handles" then
        return FieldType.HANDLE
    elseif extracted == "Parameters" then
        return FieldType.PARAMETER
    else
        return nil
    end
end

-- Extracts a JSON representation of a command table from Part 3.
--
-- Must have three columns: Type, Name, and Description
-- Colspan separators can either be 'Handles' or 'Parameters'
-- Any fields that appear before the first colspan separator are assumed to be command-code fields.
function extractCommandFields(tbl)
    local caption = pandoc.utils.stringify(tbl.caption.long)
    if #tbl.head.rows ~= 1 then
        print(string.format("Table '%s' has %d header rows, expected 1", caption, #tbl.head.rows))
        return nil
    end

    local header = tbl.head.rows[1]

    if #header.cells ~= 3 then
        print(string.format("Table '%s' has %d header cells, expected 3", caption, #header.cells))
        return nil
    end

    local header_1 = pandoc.utils.stringify(header.cells[1].contents)
    local header_2 = pandoc.utils.stringify(header.cells[2].contents)
    local header_3 = pandoc.utils.stringify(header.cells[3].contents)

    if header_1 ~= "Type" or header_2 ~= "Name" or header_3 ~= "Description" then
        print(string.format("Table '%s' has malformed header cells: '%s', '%s', '%s'; expected 'Type', 'Name' and 'Description'",
            caption, header_1, header_2, header_3))
        return nil
    end

    if #tbl.bodies ~= 1 then
        print(string.format("Table '%s' has %d bodies, expected 1", caption, #tbl.bodies))
        return nil
    end

    local fields = {command_fields = {}, handle_fields = {}, parameter_fields = {}}
    local current_field_type = FieldType.COMMAND

    for i, row in ipairs(tbl.bodies[1].body) do
        if #row.cells == 1 then
            -- We're in a colspan which indicates the type of fields that follow.

            local span_contents = pandoc.utils.stringify(row.cells[1].contents)
            current_field_type = getFieldTypeFromSpan(span_contents)

            if current_field_type == nil then
                print(string.format("Table '%s' has malformed span: '%s', expected 'Handles' or 'Parameters'",
                    caption, span_contents))
                return nil
            end
        elseif #row.cells == 3 then
            type_cell = pandoc.utils.stringify(row.cells[1].contents)
            name_cell = pandoc.utils.stringify(row.cells[2].contents)
            desc_cell = pandoc.utils.stringify(row.cells[3].contents)

            local field = {type = type_cell, name = name_cell, description = desc_cell}

            if current_field_type == FieldType.COMMAND then
                table.insert(fields.command_fields, field)
            elseif current_field_type == FieldType.HANDLE then
                table.insert(fields.handle_fields, field)
            elseif current_field_type == FieldType.PARAMETER then
                table.insert(fields.parameter_fields, field)
            end
        else
            print(string.format("Table '%s' row %d has %d columns, expected 1 or 3", caption, i, #row.cells))
            return nil
        end
    end

    return fields
end

-- Takes a table of entries whose captions are of the form "[Command name] [Command/Response]"
-- and collates the command and response fields.
function collateCommandsAndResponses(data_entries)
    local collated = {}

    for _, table_data in ipairs(data_entries) do
        local command_name, type = string.match(table_data["caption"], "(%w+) (%w+)")
        if collated[command_name] == nil then
            collated[command_name] = {}
        end

        if type == "Command" then
            collated[command_name]["command"] = table_data["fields"]
        elseif type == "Response" then
            collated[command_name]["response"] = table_data["fields"]
        else
            print(string.format("Table '%s' has malformed type, expected 'Command' or 'Response'", table_data["caption"]))
        end
    end

    return collated
end

function Pandoc(doc)
    local table_fields = {}

    for _, block in ipairs(doc.blocks) do
        if block.t == "Table" then
            local fields = extractCommandFields(block)
            if fields ~= nil then
                table.insert(table_fields, {caption = pandoc.utils.stringify(block.caption.long), fields = fields})
            end
        end
    end

    print(string.format("Extracted data from %d tables", #table_fields))
    print("Collating tables")

    local collated = collateCommandsAndResponses(table_fields)

    -- Overwrite the entire document with a single code block containing the JSON
    local json_string = pandoc.json.encode(collated)
    return pandoc.Pandoc({pandoc.CodeBlock(json_string)})
end
