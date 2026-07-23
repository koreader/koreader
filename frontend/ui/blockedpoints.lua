local BlockedPoints = {}

local blocked_points_table = {}

-- Requires G_reader_settings and json.lua
-- G_reader_settings is a global, no need to require it.
local JSON = require("json")

function BlockedPoints.loadBlockedPoints()
    if not G_reader_settings then
        print("Warning: G_reader_settings not available to BlockedPoints module.")
        blocked_points_table = {}
        return
    end
    local blocked_points_json = G_reader_settings:readSetting("blocked_points_list")
    if blocked_points_json then
        local success, decoded_table = pcall(JSON.decode, blocked_points_json)
        if success and type(decoded_table) == "table" then
            blocked_points_table = decoded_table
        else
            blocked_points_table = {}
        end
    else
        blocked_points_table = {}
    end
end

function BlockedPoints.saveBlockedPoints()
    if not G_reader_settings then
        print("Warning: G_reader_settings not available to BlockedPoints module. Cannot save.")
        return
    end
    local success, encoded_json = pcall(JSON.encode, blocked_points_table)
    if success then
        G_reader_settings:saveSetting("blocked_points_list", encoded_json)
    else
        -- Handle encoding error, perhaps log it
        print("Error encoding blocked points to JSON")
    end
end

function BlockedPoints.addBlockedPoint(x, y)
    for _, point in ipairs(blocked_points_table) do
        if point.x == x and point.y == y then
            return -- Point already exists
        end
    end
    table.insert(blocked_points_table, {x = x, y = y})
    BlockedPoints.saveBlockedPoints()
end

function BlockedPoints.removeBlockedPoint(x, y)
    for i, point in ipairs(blocked_points_table) do
        if point.x == x and point.y == y then
            table.remove(blocked_points_table, i)
            BlockedPoints.saveBlockedPoints()
            return
        end
    end
end

function BlockedPoints.isBlocked(x, y)
    for _, point in ipairs(blocked_points_table) do
        if point.x == x and point.y == y then
            return true
        end
    end
    return false
end

-- Initialize by loading blocked points
BlockedPoints.loadBlockedPoints()

return BlockedPoints
