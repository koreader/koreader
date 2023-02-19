--[[--
This module helps with retrieving version information.
]]

local VERSION_LOG_FILE = "version.log"
local LAST_VERSION_NOT_FOUND = "last version not found"
local MAX_NB_LOG_LINES = 365

local Version = {}

--- Returns current KOReader git-rev.
-- @treturn string full KOReader git-rev such as `v2015.11-982-g704d4238`
function Version:getCurrentRevision()
    if not self.rev then
        local rev_file = io.open("git-rev", "r")
        if rev_file then
            self.rev = rev_file:read("*line")
            rev_file:close()
        end
        -- sanity check in case `git describe` failed
        if self.rev == "fatal: No names found, cannot describe anything." then
            self.rev = nil
        end
    end
    return self.rev
end

--- Returns normalized version of KOReader git-rev input string.
-- @string rev full KOReader git-rev such as `v2015.11-982-g704d4238`
-- @treturn int version in the form of a 10 digit number such as `2015110982`
-- @treturn string short git commit version hash such as `704d4238`
function Version:getNormalizedVersion(rev)
    if not rev then return end
    local year, month, point, revision = rev:match("v(%d%d%d%d)%.(%d%d)%.?(%d?%d?)-?(%d*)")

    year = tonumber(year)
    month = tonumber(month)
    point = tonumber(point)
    revision = tonumber(revision)

    local commit = rev:match("-%d*-g(%x*)[%d_%-]*")
    -- NOTE: * 10000 to handle at most 9999 commits since last tag ;).
    return ((year or 0) * 100 + (month or 0)) * 1000000 + (point or 0) * 10000 + (revision or 0), commit
end

--- Returns current version of KOReader.
-- @treturn int version in the form of a 10 digit number such as `2015110982`
-- @treturn string short git commit version hash such as `704d4238`
-- @see getNormalizedVersion
function Version:getNormalizedCurrentVersion()
    if not self.version or not self.commit then
        self.version, self.commit = self:getNormalizedVersion(self:getCurrentRevision())
    end
    return self.version, self.commit
end

--- Returns current version of KOReader, in short form.
-- @treturn string version, without the git details (i.e., at most YYYY.MM.P-R)
function Version:getShortVersion()
    if not self.short then
        local rev = self:getCurrentRevision()
        if (not rev or rev == "") then return "unknown" end
        local year, month, point, revision = rev:match("v(%d%d%d%d)%.(%d%d)%.?(%d?%d?)-?(%d*)")
        self.short = year .. "." .. month
        if point and point ~= "" then
            self.short = self.short .. "." .. point
        end
        if revision and revision ~= "" then
            self.short = self.short .. "-" .. revision
        end
    end
    return self.short
end

--- Returns the release date of the current version of KOReader, YYYYmmdd, in UTC.
--- Technically closer to the build date, but close enough where official builds are concerned ;).
-- @treturn int date
function Version:getBuildDate()
    if not self.date then
        local lfs = require("libs/libkoreader-lfs")
        local mtime = lfs.attributes("git-rev", "modification")
        if mtime then
            local ts = os.date("!%Y%m%d", mtime)
            self.date = tonumber(ts) or 0
        else
            -- No git-rev file?
            self.date = 0
        end
    end
    return self.date
end

--- Returns the KOReader git-rev and model of the last line in the `VERSION_LOG_FILE`
--- and drop any lines except the last `MAX_NB_LOG_LINE's.
-- @treturn string,string  git-rev, model
function Version:getLastVersion()
    local log_file = io.open(VERSION_LOG_FILE, "r")
    local log_lines = {}
    if log_file then
        local next_line = log_file:read("*line")
        while next_line do
            table.insert(log_lines, next_line)
            next_line = log_file:read("*line")
        end
        log_file:close()

        if #log_lines <= 0 then -- no need for shortening the log file
            return LAST_VERSION_NOT_FOUND, ""
        elseif #log_lines >= MAX_NB_LOG_LINES then -- keep only the last N-1 lines
            local new_file = io.open(VERSION_LOG_FILE.."new", "a")
            for i = math.max(#log_lines - MAX_NB_LOG_LINES + 1, 1), #log_lines do
                new_file:write(log_lines[i], "\n")
            end
            new_file:close()
            os.remove(VERSION_LOG_FILE)
            os.rename(VERSION_LOG_FILE.."new", VERSION_LOG_FILE)
        end
    else -- log_file does not exist or can not be opened
        return LAST_VERSION_NOT_FOUND, ""
    end

    local last_version_line = log_lines[#log_lines]
    local dummy, dummy, last_version, last_model = last_version_line:match("(.-), (.-), (.-), (.-)$")

    self.last_version = last_version or ""
    self.last_model = last_model or ""
    return self.last_version, self.last_model
end

--- Appends KOReader git-rev, model and current date to the `VERSION_LOG_FILE`
--- in the format 'YYYY-mm-dd, HH:MM:SS, git-rev, model'
-- @string model device model (may contain spaces)
function Version:appendVersionLog(model)
    local file = io.open(VERSION_LOG_FILE, "a")
    if not file then
        return
    end
    file:write(os.date("%Y-%m-%d, %X, "), self.rev or LAST_VERSION_NOT_FOUND, ", ", model or "", "\n")
    file:close()
    return
end

--- Updates the `VERSION_LOG_FILE` and keep the file small
-- @string model device model (may contain spaces)
function Version:updateVersionLog(current_model)
    local last_version, last_model = self:getLastVersion()
    if self.rev ~= last_version or current_model ~= last_model then
        self:appendVersionLog(current_model)
    end
end

return Version
