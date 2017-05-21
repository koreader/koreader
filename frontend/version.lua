--[[--
This module helps with retrieving version information.
]]

local Version = {}

--- Returns current KOReader git-rev.
-- @treturn string full KOReader git-rev such `v2015.11-982-g704d4238`
function Version:getCurrentRevision()
    if not self.rev then
        local rev_file = io.open("git-rev", "r")
        if rev_file then
            self.rev = rev_file:read()
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
-- @string rev full KOReader git-rev such `v2015.11-982-g704d4238`
-- @treturn int version in the form of a number such as `201511982`
-- @treturn string short git commit version hash such as `704d4238`
function Version:getNormalizedVersion(rev)
    if not rev then return end
    local year, month, revision = rev:match("v(%d%d%d%d)%.(%d%d)-?(%d*)")
    local commit = rev:match("-%d*-g(.*)")
    return ((year or 0) * 100 + (month or 0)) * 1000 + (revision or 0), commit
end

--- Returns current version of KOReader.
-- @treturn int version in the form of a number such as `201511982`
-- @treturn string short git commit version hash such as `704d4238`
-- @see normalized_version
function Version:getNormalizedCurrentVersion()
    if not self.version or not self.commit then
        self.version, self.commit = self:getNormalizedVersion(self:getCurrentRevision())
    end
    return self.version, self.commit
end

return Version
