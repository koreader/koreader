--[[--
This module helps with writing information to log files
]]

local LogFile = {
    log_files = {},
}

--- Returns the last line in a log file and drop any lines except the last `max_nb_log_lines`.
-- @string path path of the logfile
-- @int max_nb_lines maxiumum number of lines to keep
-- @treturn string last line in log file
function LogFile:getLastLineAndShrinkFile(path, max_nb_log_lines)
    local log_file = io.open(path, "r")
    local log_lines = {}
    if log_file then
        local next_line = log_file:read("*line")
        while next_line do
            table.insert(log_lines, next_line)
            next_line = log_file:read("*line")
        end
        log_file:close()

        self.log_files[path] = #log_lines

        max_nb_log_lines = max_nb_log_lines or math.huge
        if #log_lines <= 0 then -- empty log file
            return ""
        elseif #log_lines > max_nb_log_lines then -- keep only the last N-1 lines
            local new_file = io.open(path .. ".new", "a")
            for i = #log_lines - max_nb_log_lines + 1, #log_lines do
                new_file:write(log_lines[i], "\n")
            end
            new_file:close()
            os.remove(path)
            os.rename(path .. ".new", path)
            self.log_files[path] = max_nb_log_lines
        end
    else -- log_file does not exist or can not be opened
        return ""
    end

    return log_lines[#log_lines]
end

--- Append some text to a file and limit the file size to the last `max_nb_log_lines`.
-- @string path path of the logfile
-- @string text text to be appended
-- @int max_nb_lines maxiumum number of lines to keep
function LogFile:append(path, text, max_nb_log_lines)
    max_nb_log_lines = max_nb_log_lines or math.huge
    if not self.log_files or not self.log_files[path] or self.log_files[path] > max_nb_log_lines then
        LogFile:getLastLineAndShrinkFile(path, max_nb_log_lines - 1)
    end

    local log_file = io.open(path, "a")
    if not log_file then
        return
    end
    log_file:write(text, "\n")
    log_file:close()

    local _, nb_new_lines = text:gsub("\n","")
    if self.log_files and self.log_files[path] then
        self.log_files[path] = self.log_files[path] + nb_new_lines + 1
    else
        self.log_files[path] = nb_new_lines + 1
    end

    return true
end

return LogFile
