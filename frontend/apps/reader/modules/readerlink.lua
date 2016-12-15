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

local function isFollowLinksOn()
    return G_reader_settings:readSetting("follow_links") ~= false
end

local function isSwipeToGoBackEnabled()
    return G_reader_settings:readSetting("swipe_to_go_back") == true
end

local function isSwipeToFollowFirstLinkEnabled()
    return G_reader_settings:readSetting("swipe_to_follow_first_link") == true
end

function ReaderLink:addToMainMenu(tab_item_table)
    -- insert table to main reader menu
    table.insert(tab_item_table.navi, {
        text = _("Follow links"),
        sub_item_table = {
            {
                text_func = function()
                    return isFollowLinksOn() and _("Disable") or _("Enable")
                end,
                callback = function()
                    G_reader_settings:saveSetting("follow_links",
                        not isFollowLinksOn())
                end
            },
            {
                text = _("Go back"),
                enabled_func = function() return #self.location_stack > 0 end,
                callback = function() self:onGoBackLink() end,
            },
            {
                text = _("Swipe to go back"),
                checked_func = isSwipeToGoBackEnabled,
                callback = function()
                    G_reader_settings:saveSetting("swipe_to_go_back",
                        not isSwipeToGoBackEnabled())
                end,
            },
            {
                text = _("Swipe to follow first link"),
                checked_func = isSwipeToFollowFirstLinkEnabled,
                callback = function()
                    G_reader_settings:saveSetting("swipe_to_follow_first_link",
                        not isSwipeToFollowFirstLinkEnabled())
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
    if not isFollowLinksOn() then return end
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
        return true
    end
end

function ReaderLink:onSwipe(_, ges)
    if ges.direction == "east" then
        if isSwipeToGoBackEnabled() then
            return self:onGoBackLink()
        end
    elseif ges.direction == "west" then
        if isSwipeToFollowFirstLinkEnabled() then
            return self:onGoToFirstLink(ges)
        end
    end
end

function ReaderLink:onGoToFirstLink(ges)
    if not isFollowLinksOn() then return end
    local firstlink = nil
    if self.ui.document.info.has_pages then
        local pos = self.view:screenToPageTransform(ges.pos)
        if not pos then
            return
        end
        local links = self.ui.document:getPageLinks(pos.page)
        if #links == 0 then
            return
        end
        -- DEBUG("PDF Page links : ", links)
        -- We may get multiple links: internal ones (with "page" key)
        -- that we're interested in, but also external links (no "page", but
        -- a "uri" key) that we don't care about.
        --     [2] = {
        --         ["y1"] = 107.88977050781,
        --         ["x1"] = 176.60360717773,
        --         ["y0"] = 97.944396972656,
        --         ["x0"] = 97,
        --         ["page"] = 347
        --     },
        -- Links may not be in the order they are in the page, so let's
        -- find the one with the smallest y0.
        local first_y0 = nil
        for _, link in ipairs(links) do
            if link["page"] then
                if first_y0 == nil or link["y0"] < first_y0 then
                    -- onGotoLink()'s GotoPage event needs the link
                    -- itself, and will use its "page" value
                    firstlink = link
                    first_y0 = link["y0"]
                end
            end
        end
    else
        local links = self.ui.document:getPageLinks()
        if #links == 0 then
            return
        end
        -- DEBUG("CRE Page links : ", links)
        -- We may get multiple links: internal ones (they have a "section" key)
        -- that we're interested in, but also external links (no "section", but
        -- a "uri" key) that we don't care about.
        --     [1] = {
        --         ["end_x"] = 825,
        --         ["uri"] = "",
        --         ["end_y"] = 333511,
        --         ["start_x"] = 90,
        --         ["start_y"] = 333511
        --     },
        --     [2] = {
        --         ["end_x"] = 366,
        --         ["section"] = "#_doc_fragment_19_ftn_fn6",
        --         ["end_y"] = 1201,
        --         ["start_x"] = 352,
        --         ["start_y"] = 1201
        --     },
        -- links may not be in the order they are in the page, so let's
        -- find the one with the smallest start_y.
        local first_start_y = nil
        for _, link in ipairs(links) do
            if link["section"] then
                if first_start_y == nil or link["start_y"] < first_start_y then
                    -- onGotoLink()'s GotoXPointer event needs
                    -- the "section" value
                    firstlink = link["section"]
                    first_start_y = link["start_y"]
                end
            end
        end
        -- cre.cpp getPageLinks() does highlight found links :
        --   sel.add( new ldomXRange(*links[i]) ); // highlight
        -- and we'll find them highlighted when back from link.
        -- So let's clear them now.
        self.ui.document:clearSelection()
    end
    if firstlink then
        return self:onGotoLink(firstlink)
    end
end

return ReaderLink
