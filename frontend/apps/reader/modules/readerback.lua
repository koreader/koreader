local Device = require("device")
local Event = require("ui/event")
local EventListener = require("ui/widget/eventlistener")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

local ReaderBack = EventListener:new{
    location_stack = {},
    -- a limit not intended to be a practical limit but just a failsafe
    max_stack = 5000,
    -- allow for disabling back history, and having Back key
    -- quit immediately (useful for some developers)
    disabled = G_reader_settings:isFalse("enable_back_history"),
}

function ReaderBack:init()
    if Device:hasKeys() then
        self.ui.key_events.Back = { {"Back"}, doc = "Reader back" }
    end
end

function ReaderBack:_getCurrentLocation()
    local current_location

    if self.ui.document.info.has_pages then
        current_location = self.ui.paging:getBookLocation()
    else
        current_location = {
            xpointer = self.ui.rolling:getBookLocation(),
        }
    end

    return current_location
end

local ignore_location

function ReaderBack:addCurrentLocationToStack()
    local location_stack = self.location_stack
    local new_location = self:_getCurrentLocation()

    if util.tableEquals(ignore_location, new_location) then return end

    table.insert(location_stack, new_location)

    if #location_stack > self.max_stack then
        table.remove(location_stack, 1)
    end
end

-- Scroll mode crengine
function ReaderBack:onPosUpdate()
    if self.disabled then return end
    self:addCurrentLocationToStack()
end

-- Paged media
function ReaderBack:onPageUpdate()
    if self.disabled then return end
    self:addCurrentLocationToStack()
end

-- Called when loading new document
function ReaderBack:onReadSettings(config)
    self.location_stack = {}
end

function ReaderBack:onBack()
    local location_stack = self.location_stack

    if self.disabled then
        self.ui:handleEvent(Event:new("Close"))
    elseif #location_stack > 1 then
        local saved_location = table.remove(location_stack)

        if saved_location then
            ignore_location = self:_getCurrentLocation()
            logger.dbg("[ReaderBack] restoring:", saved_location)
            self.ui:handleEvent(Event:new('RestoreBookLocation', saved_location))
            return true
        end
    else
        logger.dbg("[ReaderBack] no location history, closing")
        self.ui:handleEvent(Event:new("Home"))
    end
end

return ReaderBack
