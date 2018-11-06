local Device = require("device")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local UsbGadget = {}

-- get, set and check current mode.
local function getMode()
    local mode = G_reader_settings:readSetting("usb_mode")
    return mode or "charge"
end

local function setMode(mode)
    G_reader_settings:saveSetting("usb_mode", mode)
    G_reader_settings:flush()
end

local function isEqual(mode)
    if getMode() == mode then
        return true
    else
        return false
    end
end

-- get, set and check current lock state
local function getLockState()
    local state = G_reader_settings:readSetting("usb_mode_locked")
    if not state then return 0 end
    return state
end

local function setLockState(lock)
    if not lock == 0 and not lock == 1 then return end
    G_reader_settings:saveSetting("usb_mode_locked", lock)
    G_reader_settings:flush()
end

local function isLocked()
    if getLockState() == 1 then
        return true
    else
        return false
    end
end

-- from https://stackoverflow.com/questions/1410862/concatenation-of-tables-in-lua
local function tableConcat(t1,t2)
    for i=1,#t2 do
        t1[#t1+1] = t2[i]
    end
    return t1
end

--[[ Plug In ]]--
function UsbGadget:plugIn()
    local mode = getMode()
    local lock = getLockState()
    if mode == "network" and lock == 0 then
        setLockState(1)
        Device:usbNetworkIn()
    elseif mode == "storage" and lock == 0 then
        local ConfirmBox = require("ui/widget/confirmbox")
        UIManager:show(ConfirmBox:new{
            text = _("Share storage via USB?\n"),
            ok_text = _("Share"),
            ok_callback = function()
                setLockState(1)
                Device:usbStorageIn()
            end,
        })
    end
end

--[[ Plug Out ]]--
function UsbGadget:plugOut()
    local mode = getMode()
    local lock = getLockState()
    if mode == "network" and lock == 1 then
        setLockState(0)
        Device:usbNetworkOut()
    elseif mode == "storage" and lock == 1 then
        setLockState(0)
        Device:usbStorageOut()
    end
end

--[[ Menu ]]--
function UsbGadget:getMenuTable()
    local menu = {
        {
            text = _("Disabled"),
            enabled_func = function() return not isLocked() end,
            checked_func = function() return isEqual("charge") end,
            callback = function() setMode("charge") end,
        },
        {
            text = _("Storage"),
            enabled_func = function() return not isLocked() end,
            checked_func = function() return isEqual("storage") end,
            callback = function() setMode("storage") end,
        },
        {
            text = _("Network"),
            enabled_func = function() return not isLocked() end,
            checked_func = function() return isEqual("network") end,
            callback = function() setMode("network") end,
            separator = true,
        },
    }

    local test = nil
    if Device:isSDL() then
        -- add a submenu to test plug/unplug events on SDL devices.
        test = {
            {
                text = _("test USB events"),
                sub_item_table = {
                    {
                        text = _("UsbHostPlugIn"),
                        callback = function() UsbGadget:plugIn() end,
                    },
                    {
                        text = _("UsbHostPlugOut"),
                        callback = function() UsbGadget:plugOut() end,
                    },
                },
            },
        }
    end
    if not test then return menu end
    return tableConcat(menu, test)
end

return UsbGadget
