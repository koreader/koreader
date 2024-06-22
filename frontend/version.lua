--[[--
This module helps with retrieving version information.
]]

local VERSION_LOG_FILE = "version.log"

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
-- @treturn int version in the form of a 12 digit number such as `201511000982`
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
-- @treturn int version in the form of a 12 digit number such as `201511000982`
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

--- Get last line in `VERSION_LOG_FILE`.
-- @treturn last line in `VERSION_LOG_FILE` or an empty string
function Version:getLastLogLine()
    local log_file = io.open(VERSION_LOG_FILE, "r")
    local last_log_line
    if log_file then
        for line in log_file:lines() do
            last_log_line = line
        end
        log_file:close()
    end

    return last_log_line or ""
end

--- Append text to a `VERSION_LOG_FILE`.
-- @string text text to be appended
function Version:appendToLogFile(text)
    local log_file = io.open(VERSION_LOG_FILE, "a")
    if not log_file then
        return
    end
    log_file:write(text, "\n")
    log_file:close()
    return true
end

--- Updates `VERSION_LOG_FILE` and keep the file small
-- @string model device model (may contain spaces)
function Version:updateVersionLog(current_model)
    local last_line = Version:getLastLogLine()

    local dummy, dummy, last_version, last_model = last_line:match("(.-), (.-), (.-), (.-)$")
    self.last_version = last_version or "last version not found"
    self.last_model = last_model or "last model not found"

    if self.rev ~= last_version or current_model ~= last_model then
        -- Appends KOReader git-rev, model and current date to the `VERSION_LOG_FILE`
        -- in the format 'YYYY-mm-dd, HH:MM:SS, git-rev, model'
        self:appendToLogFile(os.date("%Y-%m-%d, %X, ") .. self.rev .. ", " .. current_model)
    end
end

return Version
