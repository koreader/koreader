local bit = require("bit")
local lfs = require("libs/libkoreader-lfs")

local FindKeyboard = {}

local function count_set_bits(n)
    -- Brian Kernighan's algorithm
    local count = 0
    while n > 0 do
        count = count + 1
        n = bit.band(n, n - 1)
    end
    return count
end

local function count_set_bits_in_string(str)
    local count = 0
    for c in str:gmatch"[0-9a-fA-F]" do
        local digit = tonumber(c, 16)
        count = count + count_set_bits(digit)
    end

    return count
end

local function is_keyboard(sys_event_path)
    local key_path = sys_event_path .. "/device/capabilities/key"
    local file = io.open(key_path, "r")
    if not file then
        -- This should not happen - the kernel creates key capabilities file for all devices.
        return false
    end
    local keys_bitmap_str = file:read("l")
    file:close()

    -- The heuristic is that a keyboard has at least as many keys as there are alphabet letters.
    local keyboard_min_number_keys = 28
    local ones_count = count_set_bits_in_string(keys_bitmap_str)
    return ones_count >= keyboard_min_number_keys
end

function FindKeyboard:find()
    for event_file_name in lfs.dir("/sys/class/input/") do
        if event_file_name:match("event.*") then
            if is_keyboard("/sys/class/input/" .. event_file_name) then
                return "/dev/input/" .. event_file_name
            end
        end
    end
    return nil
end

-- print(FindKeyboard:find())
return FindKeyboard
