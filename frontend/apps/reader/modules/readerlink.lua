--[[--
ReaderLink is an abstraction for document-specific link interfaces.
]]

local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local LinkBox = require("ui/widget/linkbox")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

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

local function isTapToFollowLinksOn()
    return not G_reader_settings:isFalse("tap_to_follow_links")
end

local function isSwipeToGoBackEnabled()
    return G_reader_settings:readSetting("swipe_to_go_back") == true
end

local function isSwipeToFollowFirstLinkEnabled()
    return G_reader_settings:readSetting("swipe_to_follow_first_link") == true
end

local function isSwipeToFollowNearestLinkEnabled()
    return G_reader_settings:readSetting("swipe_to_follow_nearest_link") == true
end

local function isSwipeToJumpToLatestBookmarkEnabled()
    return G_reader_settings:readSetting("swipe_to_jump_to_latest_bookmark") == true
end

function ReaderLink:addToMainMenu(menu_items)
    -- insert table to main reader menu
    menu_items.follow_links = {
        text = _("Links"),
        sub_item_table = {
            {
                text = _("Tap to follow links"),
                checked_func = isTapToFollowLinksOn,
                callback = function()
                    G_reader_settings:saveSetting("tap_to_follow_links",
                        not isTapToFollowLinksOn())
                end,
                separator = true,
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
                text = _("Swipe to follow first link on page"),
                checked_func = isSwipeToFollowFirstLinkEnabled,
                callback = function()
                    G_reader_settings:saveSetting("swipe_to_follow_first_link",
                        not isSwipeToFollowFirstLinkEnabled())
                    if isSwipeToFollowFirstLinkEnabled() then
                        G_reader_settings:delSetting("swipe_to_follow_nearest_link") -- can't have both
                    end
                end,
            },
            {
                text = _("Swipe to follow nearest link"),
                checked_func = isSwipeToFollowNearestLinkEnabled,
                callback = function()
                    G_reader_settings:saveSetting("swipe_to_follow_nearest_link",
                        not isSwipeToFollowNearestLinkEnabled())
                    if isSwipeToFollowNearestLinkEnabled() then
                        G_reader_settings:delSetting("swipe_to_follow_first_link") -- can't have both
                    end
                end,
                separator = true,
            },
            {
                text = _("Swipe to jump to latest bookmark"),
                checked_func = isSwipeToJumpToLatestBookmarkEnabled,
                callback = function()
                    G_reader_settings:saveSetting("swipe_to_jump_to_latest_bookmark",
                        not isSwipeToJumpToLatestBookmarkEnabled())
                end,
            },
        }
    }
    menu_items.go_to_previous_location = {
        text = _("Go back to previous location"),
        enabled_func = function() return #self.location_stack > 0 end,
        callback = function() self:onGoBackLink() end,
    }
end

--- Gets link from gesture.
-- `Document:getLinkFromPosition()` behaves differently depending on
-- document type, so this function provides a wrapper.
function ReaderLink:getLinkFromGes(ges)
    if self.ui.document.info.has_pages then
        local pos = self.view:screenToPageTransform(ges.pos)
        if pos then
            -- link box in native page
            local link, lbox = self.ui.document:getLinkFromPosition(pos.page, pos)
            if link and lbox then
                return link, lbox, pos
            end
        end
    else
        local link = self.ui.document:getLinkFromPosition(ges.pos)
        if link ~= "" then
            return link
        end
    end
end

--- Highlights a linkbox if available and goes to it.
function ReaderLink:showLinkBox(link, lbox, pos)
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
    else
        if link ~= "" then
            return self:onGotoLink(link)
        end
    end
end

function ReaderLink:onSetDimensions(dimen)
    -- update listening according to new screen dimen
    if Device:isTouchDevice() then
        self:initGesListener()
    end
end

function ReaderLink:onTap(_, ges)
    if not isTapToFollowLinksOn() then return end
    local link, lbox, pos = self:getLinkFromGes(ges)
    if link then
        return self:showLinkBox(link, lbox, pos)
    end
end

--- Goes to link.
function ReaderLink:onGotoLink(link)
    logger.dbg("onGotoLink:", link)
    if self.ui.document.info.has_pages then
        -- internal pdf links have a "page" attribute, while external ones have an "uri" attribute
        if link.page then -- Internal link
            logger.dbg("Internal link:", link)
            table.insert(self.location_stack, self.ui.paging:getBookLocation())
            self.ui:handleEvent(Event:new("GotoPage", link.page + 1))
            return true
        end
        link = link.uri -- external link
    else
        -- For crengine, internal links may look like :
        --   #_doc_fragment_0_Organisation (link from anchor)
        --   /body/DocFragment/body/ul[2]/li[5]/text()[3].16 (xpointer from full-text search)
        -- If the XPointer does not exist (or is a full url), we will jump to page 1
        -- Best to check that this link exists in document with the following,
        -- which accepts both of the above legitimate xpointer as input.
        if self.ui.document:isXPointerInDocument(link) then
            logger.dbg("Internal link:", link)
            table.insert(self.location_stack, self.ui.rolling:getBookLocation())
            self.ui:handleEvent(Event:new("GotoXPointer", link))
            return true
        end
    end
    logger.dbg("External link:", link)
    -- Check if it is a wikipedia link
    local wiki_lang, wiki_page = link:match([[https?://([^%.]+).wikipedia.org/wiki/([^/]+)]])
    if wiki_lang and wiki_page then
        logger.dbg("Wikipedia link:", wiki_lang, wiki_page)
        -- Ask for user confirmation before launching lookup (on a
        -- wikipedia page saved as epub, full of wikipedia links, it's
        -- too easy to click on links when wanting to change page...)
        local ConfirmBox = require("ui/widget/confirmbox")
        UIManager:show(ConfirmBox:new{
            text = T(_("Would you like to read this Wikipedia %1 article?\n\n%2\n"), wiki_lang:upper(), wiki_page:gsub("_", " ")),
            ok_callback = function()
                UIManager:nextTick(function()
                    self.ui:handleEvent(Event:new("LookupWikipedia", wiki_page, false, true, wiki_lang))
                end)
            end
        })
    else
        -- local Notification = require("ui/widget/notification")
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = T(_("Invalid or external link:\n%1"), link),
            timeout = 1.0,
        })
    end
    -- don't propagate, user will notice and tap elsewhere if he wants to change page
    return true
end

--- Goes back to previous location.
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
        local ret = false
        if isSwipeToFollowFirstLinkEnabled() then
            ret = self:onGoToPageLink(ges, true)
        elseif isSwipeToFollowNearestLinkEnabled() then
            ret = self:onGoToPageLink(ges)
        end
        -- If no link found, or no follow link option enabled,
        -- jump to latest bookmark (if enabled)
        if not ret and isSwipeToJumpToLatestBookmarkEnabled() then
            ret = self:onGoToLatestBookmark(ges)
        end
        return ret
    end
end

--- Goes to link nearest to the gesture (or first link in page)
function ReaderLink:onGoToPageLink(ges, use_page_first_link)
    local selected_link = nil
    if self.ui.document.info.has_pages then
        local pos = self.view:screenToPageTransform(ges.pos)
        if not pos then
            return
        end
        local links = self.ui.document:getPageLinks(pos.page)
        if not links or #links == 0 then
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
        local pos_x, pos_y = ges.pos.x, ges.pos.y
        local shortest_dist = nil
        local first_y0 = nil
        for _, link in ipairs(links) do
            if link["page"] then
                if use_page_first_link then
                    -- Links may not be in the order they are in the page, so let's
                    -- find the one with the smallest y0.
                    if first_y0 == nil or link["y0"] < first_y0 then
                        selected_link = link
                        first_y0 = link["y0"]
                    end
                else
                    local start_dist = math.pow(link.x0 - pos_x, 2) + math.pow(link.y0 - pos_y, 2)
                    local end_dist = math.pow(link.x1 - pos_x, 2) + math.pow(link.y1 - pos_y, 2)
                    local min_dist = math.min(start_dist, end_dist)
                    if shortest_dist == nil or min_dist < shortest_dist then
                        -- onGotoLink()'s GotoPage event needs the link
                        -- itself, and will use its "page" value
                        selected_link = link
                        shortest_dist = min_dist
                    end
                end
            end
        end
    else
        local links = self.ui.document:getPageLinks()
        if not links or #links == 0 then
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
        local pos_x, pos_y = ges.pos.x, ges.pos.y
        local shortest_dist = nil
        local first_start_y = nil
        for _, link in ipairs(links) do
            if link["section"] then
                if use_page_first_link then
                    -- links may not be in the order they are in the page, so let's
                    -- find the one with the smallest start_y.
                    if first_start_y == nil or link["start_y"] < first_start_y then
                        selected_link = link["section"]
                        first_start_y = link["start_y"]
                    end
                else
                    local start_dist = math.pow(link.start_x - pos_x, 2) + math.pow(link.start_y - pos_y, 2)
                    local end_dist = math.pow(link.end_x - pos_x, 2) + math.pow(link.end_y - pos_y, 2)
                    local min_dist = math.min(start_dist, end_dist)
                    if shortest_dist == nil or min_dist < shortest_dist then
                        -- onGotoLink()'s GotoXPointer event needs
                        -- the "section" value
                        selected_link = link["section"]
                        shortest_dist = min_dist
                    end
                end
            end
        end
        -- cre.cpp getPageLinks() does highlight found links :
        --   sel.add( new ldomXRange(*links[i]) ); // highlight
        -- and we'll find them highlighted when back from link.
        -- So let's clear them now.
        self.ui.document:clearSelection()
    end
    if selected_link then
        return self:onGotoLink(selected_link)
    end
end

function ReaderLink:onGoToLatestBookmark(ges)
    local latest_bookmark = self.ui.bookmark:getLatestBookmark()
    if latest_bookmark then
        if self.ui.document.info.has_pages then
            -- self:onGotoLink() needs something with a page attribute.
            -- we need to substract 1 to bookmark page, as links start from 0
            -- and onGotoLink will add 1 - we need a fake_link (with a single
            -- page attribute) so we don't touch the bookmark itself
            local fake_link = {}
            fake_link.page = latest_bookmark.page - 1
            return self:onGotoLink(fake_link)
        else
            -- self:onGotoLink() needs a xpointer, that we find
            -- as the bookmark page attribute
            return self:onGotoLink(latest_bookmark.page)
        end
    end
end

return ReaderLink
