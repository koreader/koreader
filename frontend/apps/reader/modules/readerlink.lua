--[[--
ReaderLink is an abstraction for document-specific link interfaces.
]]

local BD = require("ui/bidi")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LinkBox = require("ui/widget/linkbox")
local Notification = require("ui/widget/notification")
local QRMessage = require("ui/widget/qrmessage")
local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen
local T = ffiutil.template

local ReaderLink = InputContainer:new{
    location_stack = {}
}

function ReaderLink:init()
    if Device:hasKeys() then
        self.key_events.SelectNextPageLink = {
            {"Tab" },
            doc = "select next page link",
            event = "SelectNextPageLink",
        }
        self.key_events.SelectPrevPageLink = {
            {"Shift", "Tab" },
            {"Sym", "Tab" }, -- Right Shift + Tab
            doc = "select previous page link",
            event = "SelectPrevPageLink",
        }
        self.key_events.GotoSelectedPageLink = {
            { "Press" },
            doc = "go to selected page link",
            event = "GotoSelectedPageLink",
        }
        -- "Back" is handled by ReaderBack, which will call our onGoBackLink()
        -- when G_reader_settings:readSetting("back_in_reader") == "previous_location"
    end
    if Device:isTouchDevice() then
        self.ui:registerTouchZones({
            {
                id = "tap_link",
                ges = "tap",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0,
                    ratio_w = 1, ratio_h = 1,
                },
                overrides = {
                    -- Tap on links have priority over everything (it can
                    -- be disabled with "Tap to follow links" menu item)
                    "readerhighlight_tap",
                    "tap_top_left_corner",
                    "tap_top_right_corner",
                    "tap_left_bottom_corner",
                    "tap_right_bottom_corner",
                    "readerfooter_tap",
                    "readerconfigmenu_ext_tap",
                    "readerconfigmenu_tap",
                    "readermenu_ext_tap",
                    "readermenu_tap",
                    "tap_forward",
                    "tap_backward",
                },
                handler = function(ges) return self:onTap(_, ges) end,
            },
            {
                id = "swipe_link",
                ges = "swipe",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0,
                    ratio_w = 1, ratio_h = 1,
                },
                overrides = {
                    "paging_swipe",
                    "rolling_swipe"
                },
                handler = function(ges) return self:onSwipe(_, ges) end,
            },
        })
    end
    self.ui:registerPostInitCallback(function()
        self.ui.menu:registerToMainMenu(self)
    end)
    if G_reader_settings:isTrue("opening_page_location_stack") then
        -- Add location at book opening to stack
        self.ui:registerPostReadyCallback(function()
            self:addCurrentLocationToStack()
        end)
    end
    -- For relative local file links
    local directory, filename = util.splitFilePathName(self.ui.document.file) -- luacheck: no unused
    self.document_dir = directory
    -- Migrate these old settings to the new common one
    if G_reader_settings:isTrue("tap_link_footnote_popup")
            or G_reader_settings:isTrue("swipe_link_footnote_popup") then
        G_reader_settings:saveSetting("tap_link_footnote_popup", nil)
        G_reader_settings:saveSetting("swipe_link_footnote_popup", nil)
        G_reader_settings:saveSetting("footnote_link_in_popup", true)
    end
end

function ReaderLink:onReadSettings(config)
    -- called when loading new document
    self.location_stack = {}
end

local function isTapToFollowLinksOn()
    return G_reader_settings:nilOrTrue("tap_to_follow_links")
end

local function isLargerTapAreaToFollowLinksEnabled()
    return G_reader_settings:isTrue("larger_tap_area_to_follow_links")
end

local function isTapIgnoreExternalLinksEnabled()
    return G_reader_settings:isTrue("tap_ignore_external_links")
end

local function isFootnoteLinkInPopupEnabled()
    return G_reader_settings:isTrue("footnote_link_in_popup")
end

local function isPreferFootnoteEnabled()
    return G_reader_settings:isTrue("link_prefer_footnote")
end

local function isSwipeToGoBackEnabled()
    return G_reader_settings:isTrue("swipe_to_go_back")
end

local function isSwipeToFollowNearestLinkEnabled()
    return G_reader_settings:isTrue("swipe_to_follow_nearest_link")
end

local function isSwipeIgnoreExternalLinksEnabled()
    return G_reader_settings:nilOrTrue("swipe_ignore_external_links")
end

local function isSwipeToJumpToLatestBookmarkEnabled()
    return G_reader_settings:isTrue("swipe_to_jump_to_latest_bookmark")
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
                help_text = _([[Tap on links to follow them.]]),
            },
            {
                text = _("Ignore external links on tap"),
                enabled_func = isTapToFollowLinksOn,
                checked_func = isTapIgnoreExternalLinksEnabled,
                callback = function()
                    G_reader_settings:saveSetting("tap_ignore_external_links",
                        not isTapIgnoreExternalLinksEnabled())
                end,
                help_text = _([[
Ignore taps on external links. Useful with Wikipedia EPUBs to make page turning easier.
You can still follow them from the dictionary window or the selection menu after holding on them.]]),
                separator = true,
            },
            {
                text = _("Swipe to go back"),
                checked_func = isSwipeToGoBackEnabled,
                callback = function()
                    G_reader_settings:saveSetting("swipe_to_go_back",
                        not isSwipeToGoBackEnabled())
                end,
                help_text = _([[Swipe to the right to go back to the previous location after you have followed a link. When the location stack is empty, swiping to the right takes you to the previous page.]]),
            },
            {
                text = _("Swipe to follow nearest link"),
                checked_func = isSwipeToFollowNearestLinkEnabled,
                callback = function()
                    G_reader_settings:saveSetting("swipe_to_follow_nearest_link",
                        not isSwipeToFollowNearestLinkEnabled())
                end,
                help_text = _([[Swipe to the left to follow the link nearest to where you started the swipe. This is useful when a small font is used and tapping on small links is tedious.]]),
            },
            {
                text = _("Ignore external links on swipe"),
                enabled_func = isSwipeToFollowNearestLinkEnabled,
                checked_func = isSwipeIgnoreExternalLinksEnabled,
                callback = function()
                    G_reader_settings:saveSetting("swipe_ignore_external_links",
                        not isSwipeIgnoreExternalLinksEnabled())
                end,
                help_text = _([[
Ignore external links near swipe. Useful with Wikipedia EPUBs to follow only footnotes with swipe.
You can still follow external links from the dictionary window or the selection menu after holding on them.]]),
                separator = true,
            },
            {
                text = _("Swipe to jump to latest bookmark"),
                checked_func = isSwipeToJumpToLatestBookmarkEnabled,
                callback = function()
                    G_reader_settings:saveSetting("swipe_to_jump_to_latest_bookmark",
                        not isSwipeToJumpToLatestBookmarkEnabled())
                end,
                help_text = _([[
Swipe to the left to go the most recently bookmarked page.
This can be useful to quickly swipe back and forth between what you are reading and some reference page (for example notes, a map or a characters list).
If any of the other Swipe to follow link options is enabled, this will work only when the current page contains no link.]]),
            },
        }
    }
    -- Insert other items that are (for now) only supported with CreDocuments
    -- (They could be supported nearly as-is, but given that there is a lot
    -- less visual feedback on PDF document of what is a link, or that we just
    -- followed a link, than on EPUB, it's safer to not use them on PDF documents
    -- even if the user enabled these features for EPUB documents).
    if not self.ui.document.info.has_pages then
        -- Tap section
        table.insert(menu_items.follow_links.sub_item_table, 2, {
            text = _("Allow larger tap area around links"),
            enabled_func = isTapToFollowLinksOn,
            checked_func = isLargerTapAreaToFollowLinksEnabled,
            callback = function()
                G_reader_settings:saveSetting("larger_tap_area_to_follow_links",
                    not isLargerTapAreaToFollowLinksEnabled())
            end,
            help_text = _([[Extends the tap area around internal links. Useful with a small font where tapping on small footnote links may be tedious.]]),
        })
        table.insert(menu_items.follow_links.sub_item_table, 4, {
            text = _("Show footnotes in popup"),
            enabled_func = function()
                return isTapToFollowLinksOn() or isSwipeToFollowNearestLinkEnabled()
            end,
            checked_func = isFootnoteLinkInPopupEnabled,
            callback = function()
                G_reader_settings:saveSetting("footnote_link_in_popup",
                    not isFootnoteLinkInPopupEnabled())
            end,
            help_text = _([[
Show internal link target content in a footnote popup when it looks like it might be a footnote, instead of following the link.

Note that depending on the book quality, footnote detection may not always work correctly.
The footnote content may be empty, truncated, or include other footnotes.

From the footnote popup, you can jump to the footnote location in the book by swiping to the left.]]),
        })
        table.insert(menu_items.follow_links.sub_item_table, 5, {
            text = _("Show more links as footnotes"),
            enabled_func = function()
                return isFootnoteLinkInPopupEnabled() and
                    (isTapToFollowLinksOn() or isSwipeToFollowNearestLinkEnabled())
            end,
            checked_func = isPreferFootnoteEnabled,
            callback = function()
                G_reader_settings:saveSetting("link_prefer_footnote",
                    not isPreferFootnoteEnabled())
            end,
            help_text = _([[Loosen footnote detection rules to show more links as footnotes.]]),
        })
        table.insert(menu_items.follow_links.sub_item_table, 6, {
            text = _("Set footnote popup font size"),
            enabled_func = function()
                return isFootnoteLinkInPopupEnabled() and
                    (isTapToFollowLinksOn() or isSwipeToFollowNearestLinkEnabled())
            end,
            keep_menu_open = true,
            callback = function()
                local spin_widget
                local get_font_size_widget
                get_font_size_widget = function(show_absolute_font_size_widget)
                    local SpinWidget = require("ui/widget/spinwidget")
                    if show_absolute_font_size_widget then
                        spin_widget = SpinWidget:new{
                            width = math.floor(Screen:getWidth() * 0.75),
                            value = G_reader_settings:readSetting("footnote_popup_absolute_font_size")
                                            or Screen:scaleBySize(self.ui.font.font_size),
                            value_min = 12,
                            value_max = 255,
                            precision = "%d",
                            ok_text = _("Set font size"),
                            title_text =  _("Set footnote popup font size"),
                            info_text = _([[
The footnote popup font can adjust to the font size you've set for the document, but you can specify here a fixed absolute font size to be used instead.]]),
                            callback = function(spin)
                                G_reader_settings:delSetting("footnote_popup_relative_font_size")
                                G_reader_settings:saveSetting("footnote_popup_absolute_font_size", spin.value)
                            end,
                            extra_text = _("Set a relative font size instead"),
                            extra_callback = function()
                                UIManager:close(spin_widget)
                                spin_widget = get_font_size_widget(false)
                                UIManager:show(spin_widget)
                            end,
                        }
                    else
                        spin_widget = SpinWidget:new{
                            width = math.floor(Screen:getWidth() * 0.75),
                            value = G_reader_settings:readSetting("footnote_popup_relative_font_size") or -2,
                            value_min = -10,
                            value_max = 5,
                            precision = "%+d",
                            ok_text = _("Set font size"),
                            title_text =  _("Set footnote popup font size"),
                            info_text = _([[
The footnote popup font adjusts to the font size you've set for the document.
You can specify here how much smaller or larger it should be relative to the document font size.
A negative value will make it smaller, while a positive one will make it larger.
The recommended value is -2.]]),
                            callback = function(spin)
                                G_reader_settings:delSetting("footnote_popup_absolute_font_size")
                                G_reader_settings:saveSetting("footnote_popup_relative_font_size", spin.value)
                            end,
                            extra_text = _("Set an absolute font size instead"),
                            extra_callback = function()
                                UIManager:close(spin_widget)
                                spin_widget = get_font_size_widget(true)
                                UIManager:show(spin_widget)
                            end,
                        }
                    end
                    return spin_widget
                end
                local show_absolute_font_size_widget = G_reader_settings:has("footnote_popup_absolute_font_size")
                spin_widget = get_font_size_widget(show_absolute_font_size_widget)
                UIManager:show(spin_widget)
            end,
            help_text = _([[
The footnote popup font adjusts to the font size you've set for the document.
This allows you to specify how much smaller or larger it should be relative to the document font size.]]),
            separator = true,
        })
    end
    menu_items.go_to_previous_location = {
        text = _("Go back to previous location"),
        enabled_func = function() return #self.location_stack > 0 end,
        callback = function() self:onGoBackLink() end,
        hold_callback = function(touchmenu_instance)
            UIManager:show(ConfirmBox:new{
                text = _("Clear location history?"),
                ok_text = _("Clear"),
                ok_callback = function()
                    self:onClearLocationStack()
                    touchmenu_instance:closeMenu()
                end,
            })
        end,
    }
end

--- Check if a xpointer to <a> node really points to itself
function ReaderLink:isXpointerCoherent(a_xpointer)
    -- Get screen coordinates of xpointer
    local screen_y, screen_x = self.ui.document:getScreenPositionFromXPointer(a_xpointer)
    -- Get again link and a_xpointer from this position
    local re_link_xpointer, re_a_xpointer = self.ui.document:getLinkFromPosition({x = screen_x, y = screen_y}) -- luacheck: no unused
    -- We should get the same a_xpointer. If not, crengine has messed up
    -- and we should not trust this xpointer to get back to this link.
    if re_a_xpointer ~= a_xpointer then
        -- Try it again with screen_x+1 (in the rare cases where screen_x
        -- fails, screen_x+1 usually works - probably something in crengine,
        -- but easier to workaround here that way)
        re_link_xpointer, re_a_xpointer = self.ui.document:getLinkFromPosition({x = screen_x+1, y = screen_y}) -- luacheck: no unused
        if re_a_xpointer ~= a_xpointer then
            logger.info("not coherent a_xpointer:", a_xpointer)
            return false
        end
    end
    return true
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
                return {
                    link = link,
                    lbox = lbox,
                    pos = pos,
                }
            end
        end
    else
        local link_xpointer, a_xpointer = self.ui.document:getLinkFromPosition(ges.pos)
        logger.dbg("getLinkFromPosition link_xpointer:", link_xpointer)
        logger.dbg("getLinkFromPosition a_xpointer:",  a_xpointer)

        -- On some documents, crengine may sometimes give a wrong a_xpointer
        -- (in some Wikipedia saved as EPUB, it would point to some other <A>
        -- element in the same paragraph). If followed then back, we could get
        -- to a different page. So, we check here how valid it is, and if not,
        -- we just discard it so that addCurrentLocationToStack() is used.
        local from_xpointer = nil
        if a_xpointer and self:isXpointerCoherent(a_xpointer) then
            from_xpointer = a_xpointer
        end

        if link_xpointer ~= "" then
            -- This link's source xpointer is more precise than a classic
            -- xpointer to top of a page: we can show a marker at its
            -- y-position in target page
            -- (keep a_xpointer even if incoherent, might be needed for
            -- footnote detection (better than nothing if incoherent)
            return {
                xpointer = link_xpointer,
                marker_xpointer = link_xpointer,
                from_xpointer = from_xpointer,
                a_xpointer = a_xpointer,
                -- tap y-position should be a good approximation of link y
                -- (needed to keep its highlight a bit more time if it was
                -- hidden by the footnote popup)
                link_y = ges.pos.y
            }
        end
    end
end

--- Highlights a linkbox if available and goes to it.
function ReaderLink:showLinkBox(link, allow_footnote_popup)
    if link and link.lbox then -- pdfdocument
        -- screen box that holds the link
        local sbox = self.view:pageToScreenTransform(link.pos.page,
            self.ui.document:nativeToPageRectTransform(link.pos.page, link.lbox))
        if sbox then
            UIManager:show(LinkBox:new{
                box = sbox,
                timeout = FOLLOW_LINK_TIMEOUT,
                callback = function()
                    self:onGotoLink(link.link, false, allow_footnote_popup)
                end
            })
            return true
        end
    elseif link and link.xpointer ~= "" then -- credocument
        return self:onGotoLink(link, false, allow_footnote_popup)
    end
end

function ReaderLink:onTap(_, ges)
    if not isTapToFollowLinksOn() then return end
    if self.ui.document.info.has_pages then
        -- (footnote popup and larger tap area are for not
        -- not supported with non-CreDocuments)
        local link = self:getLinkFromGes(ges)
        if link then
            if link.link and link.link.uri and isTapIgnoreExternalLinksEnabled() then
                return
            end
            return self:showLinkBox(link)
        end
        return
    end
    -- For CreDocuments only from now on
    local allow_footnote_popup = isFootnoteLinkInPopupEnabled()
    -- If tap_ignore_external_links, skip precise tap detection to really
    -- ignore a tap on an external link, and allow using onGoToPageLink()
    -- to find the nearest internal link
    if not isTapIgnoreExternalLinksEnabled() then
        local link = self:getLinkFromGes(ges)
        if link then
            return self:showLinkBox(link, allow_footnote_popup)
        end
    end
    if isLargerTapAreaToFollowLinksEnabled() or isTapIgnoreExternalLinksEnabled() then
        local max_distance = 0 -- used when only isTapIgnoreExternalLinksEnabled()
        if isLargerTapAreaToFollowLinksEnabled() then
            -- If no link found exactly at the tap position,
            -- try to find any link in page around that tap position.
            -- With "Ignore external links", onGoToPageLink() will grab
            -- only internal links, which is nice as url links are usually
            -- longer - so this give more chance to catch a small link to
            -- footnote stuck to a longer Wikipedia article name link.
            --
            -- 30px on a reference 167 dpi screen makes 0.45cm, which
            -- seems fine (on a 300dpi device, this will be scaled
            -- to 54px (which makes 1/20th of screen witdh on a GloHD)
            -- Trust Screen.dpi (which may not be the real device
            -- screen DPI if the user has set another one).
            max_distance = Screen:scaleByDPI(30)
        end
        return self:onGoToPageLink(ges, isTapIgnoreExternalLinksEnabled(), max_distance)
    end
end

--- Remember current location so we can go back to it
function ReaderLink:addCurrentLocationToStack()
    if self.ui.document.info.has_pages then
        table.insert(self.location_stack, self.ui.paging:getBookLocation())
    else
        table.insert(self.location_stack, {
            xpointer = self.ui.rolling:getBookLocation(),
        })
    end
end

function ReaderLink:onClearLocationStack(show_notification)
    self.location_stack = {}
    if show_notification then
        UIManager:show(Notification:new{
            text = _("Location history cleared."),
        })
    end
    return true
end

--- Goes to link.
-- (This is called by other modules (highlight, search) to jump to a xpointer,
-- they should not provide allow_footnote_popup=true)
function ReaderLink:onGotoLink(link, neglect_current_location, allow_footnote_popup)
    logger.dbg("onGotoLink:", link)
    local link_url
    if self.ui.document.info.has_pages then
        -- internal pdf links have a "page" attribute, while external ones have an "uri" attribute
        if link.page then -- Internal link
            logger.dbg("Internal link:", link)
            if not neglect_current_location then
                self:addCurrentLocationToStack()
            end
            self.ui:handleEvent(Event:new("GotoPage", link.page + 1))
            return true
        end
        link_url = link.uri -- external link
    else
        -- For crengine, internal links may look like :
        --   #_doc_fragment_0_Organisation (link from anchor)
        --   /body/DocFragment/body/ul[2]/li[5]/text()[3].16 (xpointer from full-text search)
        -- If the XPointer does not exist (or is a full url), we will jump to page 1
        -- Best to check that this link exists in document with the following,
        -- which accepts both of the above legitimate xpointer as input.
        if self.ui.document:isXPointerInDocument(link.xpointer) then
            logger.dbg("Internal link:", link)
            if allow_footnote_popup then
                if self:showAsFootnotePopup(link, neglect_current_location) then
                    return true
                end
                -- if it fails for any reason, fallback to following link
            end
            if not neglect_current_location then
                if link.from_xpointer then
                    -- We have a more precise xpointer than the xpointer to top of
                    -- current page that addCurrentLocationToStack() would give, and
                    -- we may be able to show a marker when back
                    local saved_location
                    if self.view.view_mode == "scroll" then
                        -- In scroll mode, we still use the top of page as the
                        -- xpointer to go back to, so we get back to the same view.
                        -- We can still show the marker at the link position
                        saved_location = {
                            xpointer = self.ui.rolling:getBookLocation(),
                            marker_xpointer = link.from_xpointer,
                        }
                    else
                        -- In page mode, we use the same for go to and for marker,
                        -- as 'page mode' ensures we get back to the same view.
                        saved_location = {
                            xpointer = link.from_xpointer,
                            marker_xpointer = link.from_xpointer,
                        }
                    end
                    table.insert(self.location_stack, saved_location)
                else
                    self:addCurrentLocationToStack()
                end
            end
            self.ui:handleEvent(Event:new("GotoXPointer", link.xpointer, link.marker_xpointer))
            return true
        end
        link_url = link.xpointer -- external link
    end
    logger.dbg("External link:", link_url)

    local is_http_link = link_url:find("^https?://") ~= nil
    if is_http_link and self:onGoToExternalLink(link_url) then
        return true
    end

    -- Check if it is a link to a local file
    local linked_filename = link_url:gsub("^file:(//)?", "") -- remove local file protocol if any
    local anchor
    if linked_filename:find("?") then -- remove any query string (including any following anchor)
        linked_filename, anchor = linked_filename:match("^(.-)(%?.*)$")
    elseif linked_filename:find("#") then -- remove any anchor
        linked_filename, anchor = linked_filename:match("^(.-)(#.*)$")
    end
    linked_filename  = ffiutil.joinPath(self.document_dir, linked_filename) -- get full path
    linked_filename = ffiutil.realpath(linked_filename) -- clean full path from ./ or ../
    if linked_filename and lfs.attributes(linked_filename, "mode") == "file" then
        local DocumentRegistry = require("document/documentregistry")
        local provider = DocumentRegistry:getProvider(linked_filename)
        if provider then
            -- Display filename with anchor or query string, so the user gets
            -- this information and can manually go to the appropriate place
            local display_filename = linked_filename
            if anchor then
                display_filename = display_filename .. anchor
            end
            UIManager:show(ConfirmBox:new{
                text = T(_("Would you like to read this local document?\n\n%1\n"), BD.filepath(display_filename)),
                ok_callback = function()
                    UIManager:scheduleIn(0.1, function()
                        self.ui:switchDocument(linked_filename)
                    end)
                end
            })
        else
            UIManager:show(InfoMessage:new{
                text = T(_("Link to unsupported local file:\n%1"), BD.url(link_url)),
            })
        end
        return true
    end

    -- Not supported
    UIManager:show(InfoMessage:new{
        text = T(_("Invalid or external link:\n%1"), BD.url(link_url)),
        -- no timeout to allow user to type that link in his web browser
    })
    -- don't propagate, user will notice and tap elsewhere if he wants to change page
    return true
end

function ReaderLink:onGoToExternalLink(link_url)
    local text
    local dialog
    local buttons = {
        {
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                end,
            },
        },
    }
    local add_button = function(button)
        if #buttons[#buttons] >= 2 then
            -- add new row if last contains already 2
            table.insert(buttons, {})
        end
        -- append button to last row
        table.insert(buttons[#buttons], button)
    end
    -- Set up buttons for alternative external link handling methods
    local alt_handlers_buttons = {}
    table.insert(alt_handlers_buttons, {
        text = _("Copy"),
        callback = function()
            UIManager:close(dialog)
            Device.input.setClipboardText(link_url)
        end,
    })
    table.insert(alt_handlers_buttons, {
        text = _("Show QR code"),
        callback = function()
            UIManager:close(dialog)
            UIManager:show(QRMessage:new{
                text = link_url,
                width = Device.screen:getWidth(),
                height = Device.screen:getHeight()
            })
        end,
    })
    if self.ui.wallabag then
        table.insert(alt_handlers_buttons, {
            text = _("Add to Wallabag"),
            callback = function()
                UIManager:close(dialog)
                self.ui:handleEvent(Event:new("AddWallabagArticle", link_url))
            end,
        })
    end
    if Device:canOpenLink() then
        table.insert(alt_handlers_buttons, {
            text = _("Open in browser"),
            callback = function()
                UIManager:close(dialog)
                Device:openLink(link_url)
            end,
        })
    end

    -- Check if it is a wikipedia link
    local wiki_lang, wiki_page = link_url:match([[https?://([^%.]+).wikipedia.org/wiki/([^/]+)]])
    if wiki_lang and wiki_page then
        logger.dbg("Wikipedia link:", wiki_lang, wiki_page)
        -- Ask for user confirmation before launching lookup (on a
        -- wikipedia page saved as epub, full of wikipedia links, it's
        -- too easy to click on links when wanting to change page...)
        -- But first check if this wikipedia article has been saved as EPUB
        local epub_filename = wiki_page .. "."..string.upper(wiki_lang)..".epub"
        local epub_fullpath
        -- either in current book directory
        local last_file = G_reader_settings:readSetting("lastfile")
        if last_file then
            local current_book_dir = last_file:match("(.*)/")
            local safe_filename = util.getSafeFilename(epub_filename, current_book_dir):gsub("_", " ")
            local epub_path = current_book_dir .. "/" .. safe_filename
            if util.pathExists(epub_path) then
                epub_fullpath = epub_path
            end
        end
        -- or in wikipedia save directory
        if not epub_fullpath then
            local dir = G_reader_settings:readSetting("wikipedia_save_dir")
            if not dir then dir = G_reader_settings:readSetting("home_dir") end
            if not dir then dir = require("apps/filemanager/filemanagerutil").getDefaultDir() end
            if dir then
                local safe_filename = util.getSafeFilename(epub_filename, dir):gsub("_", " ")
                local epub_path = dir .. "/" .. safe_filename
                if util.pathExists(epub_path) then
                    epub_fullpath = epub_path
                end
            end
        end
        text = T(_("Would you like to read this Wikipedia %1 article?\n\n%2\n"), wiki_lang:upper(), wiki_page:gsub("_", " "))
        add_button({
            text = _("Read online"),
            callback = function()
                UIManager:nextTick(function()
                    UIManager:close(dialog)
                    self.ui:handleEvent(Event:new("LookupWikipedia", wiki_page, true, false, true, wiki_lang))
                end)
            end,
        })
        if epub_fullpath then
            text = T("%1\n%2", text, _("This article has previously been saved as EPUB. You may wish to read the saved EPUB instead."))
            add_button({
                text = _("Read EPUB"),
                callback = function()
                    UIManager:scheduleIn(0.1, function()
                        UIManager:close(dialog)
                        self.ui:switchDocument(epub_fullpath)
                    end)
                end,
            })
        end
    else
        if #alt_handlers_buttons == 0 then
            -- No external link handler
            return false
        end
        text = T(_("External link:\n\n%1"), BD.url(link_url))
    end

    -- Add all alternative handlers buttons
    for __, button in ipairs(alt_handlers_buttons) do
        add_button(button)
    end
    dialog = ButtonDialogTitle:new{
        title = text,
        use_info_style = true,
        buttons = buttons,
    }
    UIManager:show(dialog)
    return true
end

--- Goes back to previous location.
function ReaderLink:onGoBackLink(show_notification_if_empty)
    local saved_location = table.remove(self.location_stack)
    if saved_location then
        logger.dbg("GoBack: restoring:", saved_location)
        self.ui:handleEvent(Event:new('RestoreBookLocation', saved_location))
        return true
    elseif show_notification_if_empty then
        UIManager:show(Notification:new{
            text = _("Location history is empty."),
        })
    end
end

function ReaderLink:onSwipe(arg, ges)
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
    if direction == "east" then
        if isSwipeToGoBackEnabled() then
            if #self.location_stack > 0 then
                -- Remember if location stack is going to be empty, so we
                -- can stop the propagation of next swipe back: so the user
                -- knows it is empty and that next swipe back will get him
                -- to previous page (and not to previous location)
                self.swipe_back_resist = #self.location_stack == 1
                return self:onGoBackLink()
            elseif self.swipe_back_resist then
                self.swipe_back_resist = false
                -- Make that gesture don't do anything, and show a Notification
                -- so the user knows why
                UIManager:show(Notification:new{
                    text = _("Location history is empty."),
                })
                return true
            end
        end
    elseif direction == "west" then
        local ret = false
        if isSwipeToFollowNearestLinkEnabled() then
            ret = self:onGoToPageLink(ges, isSwipeIgnoreExternalLinksEnabled())
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
function ReaderLink:onGoToPageLink(ges, internal_links_only, max_distance)
    local selected_link = nil
    local selected_distance2 = nil
    -- We use squares of distances all along the calculations, no need
    -- to math.sqrt() them when comparing
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
        local pos_x, pos_y = pos.x, pos.y
        local shortest_dist = nil
        for _, link in ipairs(links) do
            if not internal_links_only or link.page then
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
        if shortest_dist then
            selected_distance2 = shortest_dist
        end
    else
        -- Getting segments on a page with many internal links is
        -- a bit expensive. With larger_tap_area_to_follow_links=true,
        -- this is done for each tap on screen (changing pages, showing
        -- menu...). We might want to cache these links per page (and
        -- clear that cache when page layout change).
        -- If we care only about internal links, request them only
        -- (and avoid that expensive segments work on external links)
        local links = self.ui.document:getPageLinks(internal_links_only)
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
        --         ["a_xpointer"] = "/body/DocFragment/body/div/p[12]/sup[3]/a[3].0",
        --     },
        -- and when segments requested (example for a multi-lines link):
        --     [3] = {
        --         ["section"] = "#_doc_fragment_0_ Man_of_letters",
        --         ["a_xpointer"] = "/body/DocFragment/body/div/div[4]/ul/li[3]/ul/li[2]/ul/li[1]/ul/li[3]/a.0",
        --         ["start_x"] = 101,
        --         ["start_y"] = 457,
        --         ["end_x"] = 176,
        --         ["end_y"] = 482,,
        --         ["segments"] = {
        --             [1] = {
        --                  ["x0"] = 101,
        --                  ["y0"] = 457,
        --                  ["x1"] = 590,
        --                  ["y1"] = 482,
        --             },
        --             [2] = {
        --                  ["x0"] = 101,
        --                  ["y0"] = 482,
        --                  ["x1"] = 177,
        --                  ["y1"] = 507,
        --             }
        --         },
        --     },
        -- Note: with some documents and some links, crengine may give wrong
        -- coordinates, and our code below may miss or give the wrong first
        -- or nearest link...
        local pos_x, pos_y = ges.pos.x, ges.pos.y
        local shortest_dist = nil
        for _, link in ipairs(links) do
            -- link.uri may be an empty string with some invalid links: ignore them
            if link.section or (link.uri and link.uri ~= "") then
                if link.segments then
                    -- With segments, each is a horizontal segment, with start_x < end_x,
                    -- and we should compute the distance from gesture position to
                    -- each segment.
                    local segments_max_y = -1
                    local link_is_shortest = false
                    local segments = link.segments
                    for i=1, #segments do
                        local segment = segments[i]
                        local segment_dist
                        -- Distance here is kept squared (d^2 = diff_x^2 + diff_y^2),
                        -- and we compute each part individually
                        -- First, vertical distance (squared)
                        if pos_y < segment.y0 then -- above the segment height
                            segment_dist = math.pow(segment.y0 - pos_y, 2)
                        elseif pos_y > segment.y1 then -- below the segment height
                            segment_dist = math.pow(pos_y - segment.y1, 2)
                        else -- gesture pos is on the segment height, no vertical distance
                            segment_dist = 0
                        end
                        -- Next, horizontal distance (squared)
                        if pos_x < segment.x0 then -- on the left of segment: calc dist to x0
                            segment_dist = segment_dist + math.pow(segment.x0 - pos_x, 2)
                        elseif pos_x > segment.x1 then -- on the right of segment : calc dist to x1
                            segment_dist = segment_dist + math.pow(pos_x - segment.x1, 2)
                        -- else -- gesture pos is in the segment width, no horizontal distance
                        end
                        if shortest_dist == nil or segment_dist < shortest_dist then
                            selected_link = link
                            shortest_dist = segment_dist
                            link_is_shortest = true
                        end
                        if segment.y1 > segments_max_y then
                            segments_max_y = segment.y1
                        end
                    end
                    if link_is_shortest then
                        -- update the selected_link we just set with its lower segment y
                        selected_link.link_y = segments_max_y
                    end
                else
                    -- Before "segments" were available, we did this:
                    -- We'd only get a horizontal segment if the link is on a single line.
                    -- When it is multi-lines, we can't do much calculation...
                    -- We used to just check distance from start_x and end_x, and
                    -- we could miss a tap in the middle of a long link.
                    -- (also start_y = end_y = the top of the rect for a link on a single line)
                    local start_dist = math.pow(link.start_x - pos_x, 2) + math.pow(link.start_y - pos_y, 2)
                    local end_dist = math.pow(link.end_x - pos_x, 2) + math.pow(link.end_y - pos_y, 2)
                    local min_dist = math.min(start_dist, end_dist)
                    if shortest_dist == nil or min_dist < shortest_dist then
                        selected_link = link
                        selected_link.link_y = link.end_y
                        shortest_dist = min_dist
                    end
                end
            end
        end
        if shortest_dist then
            selected_distance2 = shortest_dist
        end

        if selected_link then
            logger.dbg("nearest selected_link", selected_link)
            -- Check a_xpointer is coherent, use it as from_xpointer only if it is
            local from_xpointer = nil
            if selected_link.a_xpointer and self:isXpointerCoherent(selected_link.a_xpointer) then
                from_xpointer = selected_link.a_xpointer
            end
            -- Make it a link as expected by onGotoLink
            selected_link = {
                xpointer = selected_link.section or selected_link.uri,
                marker_xpointer = selected_link.section,
                from_xpointer = from_xpointer,
                -- (keep a_xpointer even if incoherent, might be needed for
                -- footnote detection (better than nothing if incoherent)
                a_xpointer = selected_link.a_xpointer,
                -- keep the link y position, so we can keep its highlight shown
                -- a bit more time if it was hidden by the footnote popup
                link_y = selected_link.link_y,
            }
        end
    end
    if selected_link then
        if max_distance and selected_distance2 and selected_distance2 > math.pow(max_distance, 2) then
            logger.dbg("nearest link is further than max distance, ignoring it")
        else
            return self:onGotoLink(selected_link, false, isFootnoteLinkInPopupEnabled())
        end
    end
end

function ReaderLink:onGoToInternalPageLink(ges)
    self:onGoToPageLink(ges, true)
end

function ReaderLink:onSelectNextPageLink()
    return self:selectRelPageLink(1)
end

function ReaderLink:onSelectPrevPageLink()
    return self:selectRelPageLink(-1)
end

function ReaderLink:selectRelPageLink(rel)
    if self.ui.document.info.has_pages then
        -- not implemented for now (see at doing like in showLinkBox()
        -- to highlight the link before jumping to it)
        return
    end
    -- Follow swipe_ignore_external_links setting to allow
    -- skipping external links when using keys
    local links = self.ui.document:getPageLinks(isSwipeIgnoreExternalLinksEnabled())
    if not links or #links == 0 then
        return
    end
    if self.cur_selected_page_link_num then
        self.cur_selected_page_link_num = self.cur_selected_page_link_num + rel
        -- When reaching end of list, don't immediately jump to
        -- the other side: allow one step with no link selected
        if self.cur_selected_page_link_num > #links then
            self.cur_selected_page_link_num = nil
        elseif self.cur_selected_page_link_num <= 0 then
            self.cur_selected_page_link_num = nil
        end
    else
        if rel > 0 then
            self.cur_selected_page_link_num = 1
        elseif rel < 0 then
            self.cur_selected_page_link_num = #links
        end
    end
    if not self.cur_selected_page_link_num then
        self.cur_selected_link = nil
        self.ui.document:highlightXPointer()
        UIManager:setDirty(self.dialog, "ui")
        return
    end
    local selected_link = links[self.cur_selected_page_link_num]
    logger.dbg("selected_link", selected_link)
    -- Check a_xpointer is coherent, use it as from_xpointer only if it is
    local from_xpointer = nil
    if selected_link.a_xpointer and self:isXpointerCoherent(selected_link.a_xpointer) then
        from_xpointer = selected_link.a_xpointer
    end
    local link_y
    if selected_link.segments and #selected_link.segments > 0 then
        link_y = selected_link.segments[#selected_link.segments].y1
    else
        link_y = selected_link.end_y
    end
    -- Make it a link as expected by onGotoLink
    self.cur_selected_link = {
        xpointer = selected_link.section or selected_link.uri,
        marker_xpointer = selected_link.section,
        from_xpointer = from_xpointer,
        -- (keep a_xpointer even if incoherent, might be needed for
        -- footnote detection (better than nothing if incoherent)
        a_xpointer = selected_link.a_xpointer,
        -- keep the link y position, so we can keep its highlight shown
        -- a bit more time if it was hidden by the footnote popup
        link_y = link_y,
    }
    self.ui.document:highlightXPointer() -- clear any previous one
    self.ui.document:highlightXPointer(self.cur_selected_link.from_xpointer)
    UIManager:setDirty(self.dialog, "ui")
    return true
end

function ReaderLink:onGotoSelectedPageLink()
    if self.cur_selected_link then
        return self:onGotoLink(self.cur_selected_link, false, isFootnoteLinkInPopupEnabled())
    end
end

function ReaderLink:onPageUpdate()
    if self.cur_selected_link then
        self.ui.document:highlightXPointer()
        self.cur_selected_page_link_num = nil
        self.cur_selected_link = nil
    end
end

function ReaderLink:onPosUpdate()
    if self.cur_selected_link then
        self.ui.document:highlightXPointer()
        self.cur_selected_page_link_num = nil
        self.cur_selected_link = nil
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
            -- Make it a link as expected by onGotoLink
            local link
            if latest_bookmark.pos0 then -- text highlighted, precise xpointer
                link = {
                    xpointer = latest_bookmark.pos0,
                    marker_xpointer = latest_bookmark.pos0,
                }
            else -- page bookmarked, 'page' is a xpointer to top of page
                link = {
                    xpointer = latest_bookmark.page,
                }
            end
            return self:onGotoLink(link)
        end
    end
end

function ReaderLink:showAsFootnotePopup(link, neglect_current_location)
    if self.ui.document.info.has_pages then
        return false -- not supported
    end

    local source_xpointer = link.from_xpointer or link.a_xpointer
    local target_xpointer = link.xpointer
    if not source_xpointer or not target_xpointer then
        return false
    end
    local trust_source_xpointer = link.from_xpointer ~= nil

    -- For reference, Kobo information and conditions for showing a link as popup:
    --   https://github.com/kobolabs/epub-spec#footnotesendnotes-are-fully-supported-across-kobo-platforms
    -- Calibre has its own heuristics to decide if a link is to a footnote or not,
    -- and what to gather around the footnote target as the footnote content to display:
    -- Nearly same logic, implemented in python and in coffeescript:
    --   https://github.com/kovidgoyal/calibre/blob/master/src/pyj/read_book/footnotes.pyj
    --   https://github.com/kovidgoyal/calibre/blob/master/src/calibre/ebooks/oeb/display/extract.coffee

    -- We do many tests, including most of those done by Kobo and Calibre, to
    -- detect if a link is to a footnote.
    -- The detection is done in cre.cpp, because it makes use of DOM navigation and
    -- inspection that can't be done from Lua (unless we add many proxy functions)

    -- Detection flags, to allow tweaking a bit cre.cpp code if needed
    local flags = 0

    -- If no detection decided, fallback to false (not a footnote, so, follow link)
    if isPreferFootnoteEnabled() then
        flags = flags + 0x0001 -- if set, fallback to true
    end

    if trust_source_xpointer then
        -- trust source_xpointer: allow checking attribute and styles
        -- if not trusted, checks marked (*) don't apply
        flags = flags + 0x0002
    end
    -- Checks for private CSS properties "-cr-hint: footnote/noteref/..." are
    -- always done (they can be applied to specific elements or classe names
    -- with Styles tweaks.)

    -- Trust role= and epub:type= attribute values if defined, for source(*) and target
    flags = flags + 0x0004

    -- Accept classic FB2 footnotes: body[name="notes" or "comments"] > section
    flags = flags + 0x0008

    -- TARGET STATUS AND SOURCE RELATION
    -- Target must have an anchor #id (ie: must not be a simple link to a html file)
    flags = flags + 0x0010
    -- Target must come after source in the book
    -- (Glossary definitions may point to others before, so avoid this check
    -- if user wants more footnotes)
    if not isPreferFootnoteEnabled() then
        flags = flags + 0x0020
    end
    -- Target must not be a target of a TOC entry
    flags = flags + 0x0040
    -- flags = flags + 0x0080 -- Unused yet

    -- SOURCE NODE CONTEXT
    -- (*) Source link must not be empty content, and must not be the only content of
    -- its parent block tag (this could mean it's a chapter title in an inline ToC)
    flags = flags + 0x0100
    -- (*) Source node vertical alignment:
    -- check that all non-empty-nor-space-only children have their computed
    -- vertical-align: any of: sub super top bottom (which will be the case
    -- whether a parent or the childre themselves are in a <sub> or <sup>)
    -- (Also checks if parent or children are <sub> or <sup>, which may
    -- have been tweaked with CSS to not have one of these vertical-align.)
    flags = flags + 0x0200
    -- (*) Source node text (punctuation and parens stripped) is a number
    -- (3 digits max, to avoid catching years ... but only years>1000)
    flags = flags + 0x0400
    -- (*) Source node text (punctuation and parens stripped) is 1 or 2 letters,
    -- with 0 to 2 numbers (a, z, ab, 1a, B2)
    flags = flags + 0x0800

    -- TARGET NODE CONTEXT
    -- Target must not contain, or be contained, in H1..H6
    flags = flags + 0x1000
    -- flags = flags + 0x2000 -- Unused yet
    -- Try to extend footnote, to gather more text after target
    flags = flags + 0x4000
    -- Extended target readable text (not accounting HTML tags) must not be
    -- larger than max_text_size
    flags = flags + 0x8000
    local max_text_size = 10000 -- nb of chars

    logger.dbg("Checking if link is to a footnote:", flags, source_xpointer, target_xpointer)
    local is_footnote, reason, extStopReason, extStartXP, extEndXP =
            self.ui.document:isLinkToFootnote(source_xpointer, target_xpointer, flags, max_text_size)
    if not is_footnote then
        logger.info("not a footnote:", reason)
        return false
    end
    logger.info("is a footnote:", reason)
    if extStartXP then
        logger.info("  extended until:", extStopReason)
        logger.info(extStartXP)
        logger.info(extEndXP)
    else
        logger.info("  not extended because:", extStopReason)
    end
    -- OK, done with the dirty footnote detection work, we can now
    -- get back to the fancy UI stuff

    -- We don't request CSS files, to have a more consistent footnote style.
    -- (we still get and give to MuPDF styles set with style="" )
    -- (We also don't because MuPDF is quite sensitive to bad css, and may
    -- then just ignore the whole stylesheet, including our own declarations
    -- we add at start)
    --
    -- flags = 0x1001 to get the simplest/purest HTML without CSS, with added
    -- soft-hyphens where hyphenation is allowed (done by crengine according
    -- to user's hyphenation settings), and dir= and lang= attributes grabbed
    -- from parent nodes
    local html
    if extStartXP and extEndXP then
        html = self.ui.document:getHTMLFromXPointers(extStartXP, extEndXP, 0x1001)
    else
        html = self.ui.document:getHTMLFromXPointer(target_xpointer, 0x1001, true)
        -- from_final_parent = true to get a possibly more complete footnote
    end
    if not html then
        logger.info("failed getting HTML for xpointer:", target_xpointer)
        return false
    end

    -- if false then -- for debug, to display html
    --     UIManager:show( require("ui/widget/textviewer"):new{text = html})
    --     return true
    -- end

    -- As we stay on the current page, we can highlight the selected link
    -- (which might not be seen when covered by FootnoteWidget)
    local close_callback = nil
    if link.from_xpointer then -- coherent xpointer
        self.ui.document:highlightXPointer() -- clear any previous one
        self.ui.document:highlightXPointer(link.from_xpointer)
        -- Don't let a previous footnote popup clear our highlight
        self._footnote_popup_discard_previous_close_callback = true
        UIManager:setDirty(self.dialog, "ui")
        close_callback = function(footnote_height)
            -- remove this highlight (actually all) on close
            local highlight_page = self.ui.document:getCurrentPage()
            local clear_highlight = function()
                self.ui.document:highlightXPointer()
                -- Only refresh if we stayed on the same page, otherwise
                -- this could remove too early a marker on the target page
                -- after this footnote is followed
                if self.ui.document:getCurrentPage() == highlight_page then
                    UIManager:setDirty(self.dialog, "ui")
                end
            end
            if footnote_height then
                -- If the link was hidden by the footnote popup,
                -- delay a bit its clearing, so the user can see
                -- it and know where to start reading again
                local footnote_top_y = Screen:getHeight() - footnote_height
                if link.link_y > footnote_top_y then
                    UIManager:scheduleIn(0.5, clear_highlight)
                else
                    clear_highlight()
                end
            else
                clear_highlight()
            end
        end
    end

    -- We give FootnoteWidget the document margins and font size, so
    -- it can base its own values on them (note that this can look
    -- misaligned when floating punctuation is enabled, as margins then
    -- don't have a fixed size)
    local FootnoteWidget = require("ui/widget/footnotewidget")
    local popup
    popup = FootnoteWidget:new{
        html = html,
        doc_font_size = Screen:scaleBySize(self.ui.font.font_size),
        doc_margins = self.ui.document:getPageMargins(),
        close_callback = close_callback,
        follow_callback = function() -- follow the link on swipe west
            UIManager:close(popup)
            self:onGotoLink(link, neglect_current_location)
        end,
        on_tap_close_callback = function(arg, ges, footnote_height)
            self._footnote_popup_discard_previous_close_callback = nil
            -- On tap outside, see if we are tapping on another footnote,
            -- and display it if we do (avoid the need for 2 taps)
            self:onTap(arg, ges)
            -- If onTap() did show another FootnoteWidget, and it
            -- has already cleared our highlight, avoid calling our
            -- close_callback so we do not clear the new highlight
            if not self._footnote_popup_discard_previous_close_callback then
                if close_callback then -- not set if xpointer not coherent
                    close_callback(footnote_height)
                end
            end
            self._footnote_popup_discard_previous_close_callback = nil
        end,
        dialog = self.dialog,
    }
    UIManager:show(popup)
    return true
end

return ReaderLink
