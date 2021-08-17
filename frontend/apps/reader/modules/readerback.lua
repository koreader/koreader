local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local EventListener = require("ui/widget/eventlistener")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

-- This module handles the "Back" key (and the "Back" gesture action).
-- When global setting "back_in_reader" == "previous_read_page", it
-- additionally handles a location stack for each visited page or
-- page view change (when scrolling in a same page)

local ReaderBack = EventListener:new{
    location_stack = {},
    -- a limit not intended to be a practical limit but just a failsafe
    max_stack = 5000,
}

function ReaderBack:init()
    if Device:hasKeys() then
        self.ui.key_events.Back = { {"Back"}, doc = "Reader back" }
    end
    -- Regular function wrapping our method, to avoid re-creating
    -- an anonymous function at each page turn
    self._addPreviousLocationToStackCallback = function()
        self:_addPreviousLocationToStack()
    end
end

function ReaderBack:_getCurrentLocation()
    if self.ui.document.info.has_pages then
        return self.ui.paging:getBookLocation()
    else
        return {
            xpointer = self.ui.rolling:getBookLocation(),
        }
    end
end

function ReaderBack:_areLocationsSimilar(location1, location2)
    if self.ui.document.info.has_pages then
        -- locations are arrays of k/v tables
        if #location1 ~= #location2 then
            return false
        end
        for i=1, #location1 do
            if not util.tableEquals(location1[i], location2[i]) then
                return false
            end
        end
        return true
    else
        return location1.xpointer == location2.xpointer
    end
end

function ReaderBack:_addPreviousLocationToStack()
    local new_location = self:_getCurrentLocation()

    if self.cur_location and new_location then
        if self:_areLocationsSimilar(self.cur_location, new_location) then
            -- Unchanged, don't add it yet
            return
        end
        table.insert(self.location_stack, self.cur_location)
        if #self.location_stack > self.max_stack then
            table.remove(self.location_stack, 1)
        end
    end

    if new_location then
        self.cur_location = new_location
    end
end

-- Called when loading new document
function ReaderBack:onReadSettings(config)
    self.location_stack = {}
    self.cur_location = nil
end

function ReaderBack:_onViewPossiblyUpdated()
    if G_reader_settings:readSetting("back_in_reader") == "previous_read_page" then
        -- As multiple modules will have their :onPageUpdate()/... called,
        -- and some of them will set up the new page with it, we need to
        -- delay our handling after all of them are called (otherwise,
        -- depending on the order of the calls, we may be have the location
        -- of either the previous page or the current one).
        UIManager:nextTick(self._addPreviousLocationToStackCallback)
    end
    self.back_resist = nil
end

-- Hook to events that do/may change page/view (more than one of these events
-- may be sent on a single page turn/scroll, _addPreviousLocationToStack()
-- will ignore those for the same book location):
-- Called after initial page is set up
ReaderBack.onReaderReady = ReaderBack._onViewPossiblyUpdated
-- New page on paged media or crengine in page mode
ReaderBack.onPageUpdate = ReaderBack._onViewPossiblyUpdated
-- New page on crengine in scroll mode
ReaderBack.onPosUpdate = ReaderBack._onViewPossiblyUpdated
-- View updated (possibly on the same page) on paged media
ReaderBack.onViewRecalculate = ReaderBack._onViewPossiblyUpdated
-- View updated (possibly on the same page) on paged media (needed in Reflow mode)
ReaderBack.onPagePositionUpdated = ReaderBack._onViewPossiblyUpdated

function ReaderBack:onBack()
    local back_in_reader = G_reader_settings:readSetting("back_in_reader") or "previous_location"
    local back_to_exit = G_reader_settings:readSetting("back_to_exit") or "prompt"

    if back_in_reader == "previous_read_page" then
        if #self.location_stack > 0 then
            local saved_location = table.remove(self.location_stack)
            if saved_location then
                -- Reset self.cur_location, which will be updated with the restored
                -- saved_location, which will then not be added to the stack
                self.cur_location = nil
                logger.dbg("[ReaderBack] restoring:", saved_location)
                self.ui:handleEvent(Event:new('RestoreBookLocation', saved_location))
                -- Ensure we always have self.cur_location updated, as in some
                -- cases (same page), no event that we handle might be sent.
                UIManager:nextTick(self._addPreviousLocationToStackCallback)
                return true
            end
        elseif not self.back_resist or back_to_exit == "disable" then
            -- Show a one time notification when location stack is empty.
            -- On next "Back" only, proceed with the default behaviour (unless
            -- it's disabled, in which case we always show this notification)
            self.back_resist = true
            UIManager:show(Notification:new{
                text = _("Location history is empty."),
            })
            return true
        else
            self.back_resist = nil
        end
    elseif back_in_reader == "previous_location" then
        -- ReaderLink maintains its own location_stack of less frequent jumps
        -- (links or TOC entries followed, skim document...)
        if back_to_exit == "disable" then
            -- Let ReaderLink always show its notification if empty
            self.ui.link:onGoBackLink(true) -- show_notification_if_empty=true
            return true
        end
        if self.back_resist then
            -- Notification "Location history is empty" previously shown by ReaderLink
            self.back_resist = nil
        elseif self.ui.link:onGoBackLink(true) then -- show_notification_if_empty=true
            return true -- some location restored
        else
            -- ReaderLink has shown its notification that location stack is empty.
            -- On next "Back" only, proceed with the default behaviour
            self.back_resist = true
            return true
        end
    elseif back_in_reader == "filebrowser" then
        self.ui:handleEvent(Event:new("Home"))
        -- Filebrowser will handle next "Back" and ensure back_to_exit
        return true
    end

    -- location stack empty, or back_in_reader == "default"
    if back_to_exit == "always" then
        self.ui:handleEvent(Event:new("Close"))
    elseif back_to_exit == "disable" then
        return true
    elseif back_to_exit == "prompt" then
        UIManager:show(ConfirmBox:new{
            text = _("Exit KOReader?"),
            ok_text = _("Exit"),
            ok_callback = function()
                self.ui:handleEvent(Event:new("Close"))
            end
        })
    end
    return true
end

return ReaderBack
