local Device = require("device")
local logger = require("logger")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

if Device:isSDL() then
    Device.enableHwSuspend = function()
        logger.dbg("called enableHwSuspend()")
    end
    Device.disableHwSuspend = function()
        logger.dbg("called disableHwSuspend()")
    end
elseif not Device:isPocketBook() then
    return { disabled = true, }
end

local PocketBookSuspend = WidgetContainer:new{
    name = 'PocketBookSuspend',
    enabled = true,
}

function PocketBookSuspend:init()
    self.reader_menu_active = false
    self.config_menu_active = false
end

function PocketBookSuspend:setSuspendState(on, postpone_ms)
    if Device:isSDL() then
        logger.dbg("called setSuspendState("
            .. on  .. "," .. postpone_ms .. ")")
    else
        require("ffi/input").setSuspendState(on, postpone_ms)
    end
end

-- wait 2000ms before enabeling suspend so the ReaderUI-Widget is
-- drawn first
function PocketBookSuspend:onReaderReady()
    logger.dbg("called onReaderReady()")
    PocketBookSuspend:setSuspendState(1,2000)
end

function PocketBookSuspend:onShowReaderMenu()
    logger.dbg("called onShowReaderMenu()")
    if not self.config_menu_active then
        PocketBookSuspend:setSuspendState(0,0)
    end
    self.reader_menu_active = true
end

function PocketBookSuspend:onCloseReaderMenu()
    logger.dbg("called onCloseReaderMenu()")
    self.reader_menu_active = false
    if not self.config_menu_active then
        PocketBookSuspend:setSuspendState(1,2000)
    end
end

function PocketBookSuspend:onShowConfigMenu()
    logger.dbg("called onShowConfigMenu()")
    if not self.reader_menu_active then
        PocketBookSuspend:setSuspendState(0,0)
    end
    self.config_menu_active = true
end

function PocketBookSuspend:onCloseConfigMenu()
    logger.dbg("called onCloseConfigMenu()")
    self.config_menu_active = false
    if not self.reader_menu_active then
        PocketBookSuspend:setSuspendState(1,2000)
    end
end

return PocketBookSuspend
