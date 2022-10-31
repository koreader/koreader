local bit = require("bit")
local ffi = require("ffi")
local lfs = require("libs/libkoreader-lfs")

-- Constants from the linux kernel input-event-codes.h
local KEY_UP = 103
local BTN_DPAD_UP = 0x220

local FindKeyboard = {}

local function count_set_bits(n)
    -- Brian Kernighan's algorithm
    local count = 0
    while n ~= 0 do
        count = count + 1
        n = bit.band(n, n - 1)
    end
    return count
end

local function capabilities_str_to_long_bitmap_array(str)
    -- The format for capabilities is at include/linux/mod_devicetable.h.
    -- They are long's split by spaces. See linux/drivers/input/input.c::input_print_bitmap.
    local long_bitmap_arr = {}
    for c in str:gmatch "([0-9a-fA-F]+)" do
        local long_bitmap = tonumber(c, 16)
        table.insert(long_bitmap_arr, 1, long_bitmap)
    end
    return long_bitmap_arr
end

local function count_set_bits_in_array(arr)
    local count = 0
    for __, number in ipairs(arr) do
        local count_in_number = count_set_bits(number)
        count = count + count_in_number
    end

    return count
end

local function is_capabilities_bit_set(long_bitmap_arr, bit_offset)
    local long_bitsize = ffi.sizeof("long") * 8
    local arr_index = math.floor(bit_offset / long_bitsize)
    local long_mask = bit.lshift(1, bit_offset % long_bitsize)
    local long_bitmap = long_bitmap_arr[arr_index + 1] -- Array index starts from 1 in Lua

    if long_bitmap then
        return bit.band(long_bitmap, long_mask) ~= 0
    else
        return false
    end
end

local function read_key_capabilities(sys_event_path)
    local key_path = sys_event_path .. "/device/capabilities/key"
    local file = io.open(key_path, "r")
    if not file then
        -- This should not happen - the kernel creates key capabilities file for all devices.
        return nil
    end
    local keys_bitmap_str = file:read("l")
    file:close()

    return capabilities_str_to_long_bitmap_array(keys_bitmap_str)
end

local function analyze_key_capabilities(long_bitmap_arr)
    -- The heuristic is that a keyboard has at least as many keys as there are alphabet letters and some more.
    local keyboard_min_number_keys = 64
    local keys_count = count_set_bits_in_array(long_bitmap_arr)

    local is_keyboard = keys_count >= keyboard_min_number_keys
    local has_dpad = is_capabilities_bit_set(long_bitmap_arr, KEY_UP) or
        is_capabilities_bit_set(long_bitmap_arr, BTN_DPAD_UP)

    return {
        is_keyboard = is_keyboard,
        has_dpad = has_dpad,
    }
end

function FindKeyboard:check(event_file_name)
    local capabilities_long_bitmap_arr = read_key_capabilities("/sys/class/input/" .. event_file_name)
    if capabilities_long_bitmap_arr then
        local keyboard_info = analyze_key_capabilities(capabilities_long_bitmap_arr)
        if keyboard_info.is_keyboard then
            return {
                event_path = "/dev/input/" .. event_file_name,
                has_dpad = keyboard_info.has_dpad
            }
        end
    end
    return nil
end

function FindKeyboard:find()
    local keyboards = {}
    for event_file_name in lfs.dir("/sys/class/input/") do
        if event_file_name:match("event.*") then
            local kb = self:check(event_file_name)
            if kb then
                table.insert(keyboards, kb)
            end
        end
    end
    return keyboards
end

return FindKeyboard
