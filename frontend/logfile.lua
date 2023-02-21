--[[--
This module helps with writing information to log files
]]

local logfile = {}

--- Returns last line in a log file and drop any lines except the last lines
-- string path of the logfile
-- int max_nb_log_lines maximum number of lines in the log file
-- @treturn string,string  git-rev, model
function logfile.getLastLineAndShrinkFile(path, max_nb_log_lines)
    local log_file = io.open(path, "r")
    local log_lines = {}
    if log_file then
        local next_line = log_file:read("*line")
        while next_line do
            table.insert(log_lines, next_line)
            next_line = log_file:read("*line")
        end
        log_file:close()

        max_nb_log_lines = max_nb_log_lines or math.huge
        if #log_lines <= 0 then -- no need for shortening the log file
            return ""
        elseif #log_lines > max_nb_log_lines then -- keep only the last N-1 lines
            local new_file = io.open(path .. ".new", "a")
            for i = math.max(#log_lines - max_nb_log_lines, 1), #log_lines do
                new_file:write(log_lines[i], "\n")
            end
            new_file:close()
            os.remove(path)
            os.rename(path .. ".new", path)
        end
    else -- log_file does not exist or can not be opened
        return ""
    end

    return log_lines[#log_lines]
end

--- Document: ToDo
function logfile.append(path, text)
    local log_file = io.open(path, "a")
    if not log_file then
        return
    end
    log_file:write(text, "\n")
    log_file:close()
    return true
end

return logfile