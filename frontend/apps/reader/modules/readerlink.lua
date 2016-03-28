local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local LinkBox = require("ui/widget/linkbox")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Screen = require("device").screen
local Device = require("device")
local Event = require("ui/event")
local _ = require("gettext")

local ReaderLink = InputContainer:new{
    location_stack = {}
}

function ReaderLink:init()
    if Device:isTouchDevice() then
        self:initGesListener()
    end
    self.ui:registerPostInitCallback(function()
        self.ui.menu:registerToMainMenu(self)
    end)
end

function ReaderLink:onReadSettings(config)
    -- called when loading new document
    self.location_stack = {}
end

function ReaderLink:initGesListener()
    if Device:isTouchDevice() then
        self.ges_events = {
            Tap = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight()
                    }
                }
            },
            Swipe = {
                GestureRange:new{
                    ges = "swipe",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    }
                }
            },
        }
    end
end

local function is_follow_links_on()
    return G_reader_settings:readSetting("follow_links") ~= false
end

local function swipe_to_go_back()
    return G_reader_settings:readSetting("swipe_to_go_back") == true
end

function ReaderLink:addToMainMenu(tab_item_table)
    -- insert table to main reader menu
    table.insert(tab_item_table.navi, {
        text = _("Follow links"),
        sub_item_table = {
            {
                text_func = function()
                    return is_follow_links_on() and _("Disable") or _("Enable")
                end,
                callback = function()
                    G_reader_settings:saveSetting("follow_links",
                        not is_follow_links_on())
                end
            },
            {
                text = _("Go back"),
                enabled_func = function() return #self.location_stack > 0 end,
                callback = function() self:onGoBackLink() end,
            },
            {
                text = _("Swipe to go back"),
                checked_func = function() return swipe_to_go_back() end,
                callback = function()
                    G_reader_settings:saveSetting("swipe_to_go_back",
                        not swipe_to_go_back())
                end,
            },
        }
    })
end

function ReaderLink:onSetDimensions(dimen)
    -- update listening according to new screen dimen
    if Device:isTouchDevice() then
        self:initGesListener()
    end
end

function ReaderLink:onTap(_, ges)
    if not is_follow_links_on() then return end
    if self.ui.document.info.has_pages then
        local pos = self.view:screenToPageTransform(ges.pos)
        if pos then
            -- link box in native page
            local link, lbox = self.ui.document:getLinkFromPosition(pos.page, pos)
            if link and lbox then
                -- screen box that holds the link
                local sbox = self.view:pageToScreenTransform(pos.page,
                    self.ui.document:nativeToPageRectTransform(pos.page, lbox))
                if sbox then
                    UIManager:show(LinkBox:new{
                        box = sbox,
                        timeout = FOLLOW_LINK_TIMEOUT,
                        callback = function() self:onGotoLink(link) end
                    })
                    return true
                end
            end
        end
    else
        local link = self.ui.document:getLinkFromPosition(ges.pos)
        if link ~= "" then
            return self:onGotoLink(link)
        end
    end
end

function ReaderLink:onGotoLink(link)
    if self.ui.document.info.has_pages then
        table.insert(self.location_stack, self.ui.paging:getBookLocation())
        self.ui:handleEvent(Event:new("GotoPage", link.page + 1))
    else
        table.insert(self.location_stack, self.ui.rolling:getBookLocation())
        self.ui:handleEvent(Event:new("GotoXPointer", link))
    end
    return true
end

function ReaderLink:onGoBackLink()
    local saved_location = table.remove(self.location_stack)
    if saved_location then
        self.ui:handleEvent(Event:new('RestoreBookLocation', saved_location))
    end
    return true
end

function ReaderLink:onSwipe(_, ges)
    if ges.direction == "east" and swipe_to_go_back() then
        return self:onGoBackLink()
    end
end

return ReaderLink
