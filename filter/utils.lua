-- A collection of helper functions.

local utils = {}

function utils.runCommandWithInput(command, input)
    local pipe = io.popen(command, "w")
    if not pipe then
        return false
    end
    pipe:write(input)
    pipe:flush()
    pipe:close()
    return true
end

function utils.runCommandSuppressOutput(command)
    -- N.B.: we are using io.popen so we can suppress the output of the command.
    local pipe = io.popen(command)
    if not pipe then
        return false
    end
    pipe:flush()
    local output = pipe:read("*all")
    pipe:close()
    return true
end

function utils.readFile(path)
    local f = assert(io.open(path, "rb"))
    local content = f:read("*all")
    f:close()
    return content
end

function utils.getContentsHash(contents)
    return pandoc.sha1(contents):sub(1,10)
end

function utils.getFileHash(file)
    local f = assert(io.open(file, "r"))
    local contents = f:read("*all")
    f:close()
    return pandoc.sha1(contents):sub(1,10)
end

function utils.fileExists(file)
    local f = io.open(file)
    if f then
        f:close()
        return true
    end
    return false
end

function utils.ensureDirExists(path)
    local dirname = path:match("(.*/)")
    pandoc.system.make_directory(dirname, true)
end

function utils.deleteFilesExcept(pattern, keep)
    local f = io.popen(string.format("ls %s", pattern))
    for filename in f:lines() do
        if filename ~= keep then
            os.remove(filename)
            print(string.format("        deleted stale file %s", filename))
        end
    end
    f:close()
end

return utils
