local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

local ReaderHighlight = InputContainer:new{}

function ReaderHighlight:init()
    self.ui:registerPostInitCallback(function()
        self.ui.menu:registerToMainMenu(self)
    end)
end

function ReaderHighlight:setupTouchZones()
    -- deligate gesture listener to readerui
    self.ges_events = {}
    self.onGesture = nil

    if not Device:isTouchDevice() then return end

    self.ui:registerTouchZones({
        {
            id = "readerhighlight_tap",
            ges = "tap",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            overrides = { 'tap_forward', 'tap_backward', 'readermenu_tap', 'readerconfigmenu_tap', },
            handler = function(ges) return self:onTap(nil, ges) end
        },
        {
            id = "readerhighlight_hold",
            ges = "hold",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onHold(nil, ges) end
        },
        {
            id = "readerhighlight_hold_release",
            ges = "hold_release",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function() return self:onHoldRelease() end
        },
        {
            id = "readerhighlight_hold_pan",
            ges = "hold_pan",
            rate = 2.0,
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onHoldPan(nil, ges) end
        },
    })
end

function ReaderHighlight:onReaderReady()
    self:setupTouchZones()
end

function ReaderHighlight:addToMainMenu(menu_items)
    -- insert table to main reader menu
    menu_items.highlight_options = {
        text = _("Highlight options"),
        sub_item_table = self:genHighlightDrawerMenu(),
    }
end

local highlight_style = {
    lighten = _("Lighten"),
    underscore = _("Underline"),
    invert = _("Invert"),
}

function ReaderHighlight:genHighlightDrawerMenu()
    local get_highlight_style = function(style)
        return {
            text = highlight_style[style],
            checked_func = function()
                return self.view.highlight.saved_drawer == style
            end,
            enabled_func = function()
                return not self.view.highlight.disabled
            end,
            callback = function()
                self.view.highlight.saved_drawer = style
            end
        }
    end
    return {
        {
            text_func = function()
                return self.view.highlight.disabled and _("Enable") or _("Disable")
            end,
            callback = function()
                self.view.highlight.disabled = not self.view.highlight.disabled
            end,
            hold_callback = function() self:makeDefault(not self.view.highlight.disabled) end,
        },
        get_highlight_style("lighten"),
        get_highlight_style("underscore"),
        get_highlight_style("invert"),
    }
end

function ReaderHighlight:clear()
    if self.ui.document.info.has_pages then
        self.view.highlight.temp = {}
    else
        self.ui.document:clearSelection()
    end
    if self.hold_pos then
        self.hold_pos = nil
        self.selected_text = nil
        UIManager:setDirty(self.dialog, "ui")
        return true
    end
end

function ReaderHighlight:onClearHighlight()
    self:clear()
    return true
end

function ReaderHighlight:onTap(_, ges)
    if not self:clear() then
        if self.ui.document.info.has_pages then
            return self:onTapPageSavedHighlight(ges)
        else
            return self:onTapXPointerSavedHighlight(ges)
        end
    end
end

local function inside_box(pos, box)
    if pos then
        local x, y = pos.x, pos.y
        if box.x <= x and box.y <= y
            and box.x + box.w >= x
            and box.y + box.h >= y then
            return true
        end
    end
end

function ReaderHighlight:onTapPageSavedHighlight(ges)
    local pages = self.view:getCurrentPageList()
    local pos = self.view:screenToPageTransform(ges.pos)
    for key, page in pairs(pages) do
        local items = self.view.highlight.saved[page]
        if items then
            for i = 1, #items do
                local pos0, pos1 = items[i].pos0, items[i].pos1
                local boxes = self.ui.document:getPageBoxesFromPositions(page, pos0, pos1)
                if boxes then
                    for index, box in pairs(boxes) do
                        if inside_box(pos, box) then
                            logger.dbg("Tap on hightlight")
                            return self:onShowHighlightDialog(page, i)
                        end
                    end
                end
            end
        end
    end
end

function ReaderHighlight:onTapXPointerSavedHighlight(ges)
    local pos = self.view:screenToPageTransform(ges.pos)
    for page, _ in pairs(self.view.highlight.saved) do
        local items = self.view.highlight.saved[page]
        if items then
            for i = 1, #items do
                local pos0, pos1 = items[i].pos0, items[i].pos1
                local boxes = self.ui.document:getScreenBoxesFromPositions(pos0, pos1)
                if boxes then
                    for index, box in pairs(boxes) do
                        if inside_box(pos, box) then
                            logger.dbg("Tap on hightlight")
                            return self:onShowHighlightDialog(page, i)
                        end
                    end
                end
            end
        end
    end
end

function ReaderHighlight:onShowHighlightDialog(page, index)
    self.edit_highlight_dialog = ButtonDialog:new{
        buttons = {
            {
                {
                    text = _("Delete"),
                    callback = function()
                        self:deleteHighlight(page, index)
                        -- other part outside of the dialog may be dirty
                        UIManager:close(self.edit_highlight_dialog, "ui")
                    end,
                },
                {
                    text = _("Edit"),
                    enabled = false,
                    callback = function()
                        self:editHighlight()
                        UIManager:close(self.edit_highlight_dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(self.edit_highlight_dialog)
    return true
end

function ReaderHighlight:onHold(arg, ges)
    -- disable hold gesture if highlighting is disabled
    if self.view.highlight.disabled then return true end
    self.hold_pos = self.view:screenToPageTransform(ges.pos)
    logger.dbg("hold position in page", self.hold_pos)
    if not self.hold_pos then
        logger.dbg("not inside page area")
        return true
    end

    -- check if we were holding on an image
    local image = self.ui.document:getImageFromPosition(self.hold_pos)
    if image then
        logger.dbg("hold on image")
        local ImageViewer = require("ui/widget/imageviewer")
        local imgviewer = ImageViewer:new{
            image = image,
            -- title_text = _("Document embedded image"),
            -- No title, more room for image
            with_title_bar = false,
            fullscreen = true,
        }
        UIManager:show(imgviewer)
        return true
    end

    -- otherwise, we must be holding on text
    local ok, word = pcall(self.ui.document.getWordFromPosition, self.ui.document, self.hold_pos)
    if ok and word then
        logger.dbg("selected word:", word)
        self.selected_word = word
        if self.ui.document.info.has_pages then
            local boxes = {}
            table.insert(boxes, self.selected_word.sbox)
            self.view.highlight.temp[self.hold_pos.page] = boxes
        end
        UIManager:setDirty(self.dialog, "ui")
        -- TODO: only mark word?
        -- Unfortunately, CREngine does not return good coordinates
        -- UIManager:setDirty(self.dialog, "partial", self.selected_word.sbox)
    end
    return true
end

function ReaderHighlight:onHoldPan(_, ges)
    if self.hold_pos == nil then
        logger.dbg("no previous hold position")
        return true
    end
    local page_area = self.view:getScreenPageArea(self.hold_pos.page)
    if ges.pos:notIntersectWith(page_area) then
        logger.dbg("not inside page area", ges, page_area)
        return true
    end

    self.holdpan_pos = self.view:screenToPageTransform(ges.pos)
    logger.dbg("holdpan position in page", self.holdpan_pos)
    local old_text = self.selected_text and self.selected_text.text
    self.selected_text = self.ui.document:getTextFromPositions(self.hold_pos, self.holdpan_pos)
    if self.selected_text and old_text and old_text == self.selected_text.text then
        -- no modification
        return
    end
    logger.dbg("selected text:", self.selected_text)
    if self.selected_text then
        self.view.highlight.temp[self.hold_pos.page] = self.selected_text.sboxes
        -- remove selected word if hold moves out of word box
        if not self.selected_text.sboxes or #self.selected_text.sboxes == 0 then
            self.selected_word = nil
        elseif self.selected_word and not self.selected_word.sbox:contains(self.selected_text.sboxes[1]) or
            #self.selected_text.sboxes > 1 then
            self.selected_word = nil
        end
    end
    UIManager:setDirty(self.dialog, "ui")
end

function ReaderHighlight:lookup(selected_word)
    -- if we extracted text directly
    if selected_word.word then
        local word_box = self.view:pageToScreenTransform(self.hold_pos.page, selected_word.sbox)
        self.ui:handleEvent(Event:new("LookupWord", selected_word.word, word_box, self))
    -- or we will do OCR
    elseif selected_word.sbox and self.hold_pos then
        local word = self.ui.document:getOCRWord(self.hold_pos.page, selected_word)
        logger.dbg("OCRed word:", word)
        local word_box = self.view:pageToScreenTransform(self.hold_pos.page, selected_word.sbox)
        self.ui:handleEvent(Event:new("LookupWord", word, word_box, self))
    end
end

function ReaderHighlight:translate(selected_text)
    if selected_text.text ~= "" then
        self.ui:handleEvent(Event:new("TranslateText", self, selected_text.text))
    -- or we will do OCR
    else
        local text = self.ui.document:getOCRText(self.hold_pos.page, selected_text)
        logger.dbg("OCRed text:", text)
        self.ui:handleEvent(Event:new("TranslateText", self, text))
    end
end

function ReaderHighlight:onHoldRelease()
    if self.selected_word then
        self:lookup(self.selected_word)
        self.selected_word = nil
    elseif self.selected_text then
        logger.dbg("show highlight dialog")
        self.highlight_dialog = ButtonDialog:new{
            buttons = {
                {
                    {
                        text = _("Highlight"),
                        callback = function()
                            self:saveHighlight()
                            self:onClose()
                        end,
                    },
                    {
                        text = _("Add Note"),
                        enabled = false,
                        callback = function()
                            self:addNote()
                            self:onClose()
                        end,
                    },
                },
                {
                    {
                        text = _("Wikipedia"),
                        callback = function()
                            UIManager:scheduleIn(0.1, function()
                                self:lookupWikipedia()
                                self:onClose()
                            end)
                        end,
                    },
                    {
                        text = _("Translate"),
                        enabled = false,
                        callback = function()
                            self:translate(self.selected_text)
                            self:onClose()
                        end,
                    },
                },
                {
                    {
                        text = _("Search"),
                        callback = function()
                            self:onHighlightSearch()
                            UIManager:close(self.highlight_dialog)
                        end,
                    },
                    {
                        text = _("Dictionary"),
                        callback = function()
                            self:onHighlightDictLookup()
                            self:onClose()
                        end,
                    },
                },
            },
            tap_close_callback = function() self:handleEvent(Event:new("Tap")) end,
        }
        UIManager:show(self.highlight_dialog)
    end
    return true
end

function ReaderHighlight:highlightFromHoldPos()
    if self.hold_pos then
        if not self.selected_text then
            self.selected_text = self.ui.document:getTextFromPositions(self.hold_pos, self.hold_pos)
            logger.dbg("selected text:", self.selected_text)
        end
    end
end

function ReaderHighlight:onHighlight()
    self:saveHighlight()
end

function ReaderHighlight:onUnhighlight(item)
    local page
    local sel_text
    local sel_pos0
    local idx
    if item then
        local bookmark_text = item.text
        local words = {}
        for word in bookmark_text:gmatch("%S+") do table.insert(words, word) end
        page = tonumber(words[2])
        sel_text = item.notes
        sel_pos0 = item.pos0
    else
        page = self.hold_pos.page
        sel_text = self.selected_text.text
        sel_pos0 = self.selected_text.pos0
    end
    for index = 1, #self.view.highlight.saved[page] do
        if self.view.highlight.saved[page][index].text == sel_text and
            self.view.highlight.saved[page][index].pos0 == sel_pos0 then
            idx = index
            break
        end
    end
    self:deleteHighlight(page, idx)
    return true
end

function ReaderHighlight:getHighlightBookmarkItem()
    if self.hold_pos and not self.selected_text then
        self:highlightFromHoldPos()
    end
    if self.selected_text and self.selected_text.pos0 and self.selected_text.pos1 then
        local datetime = os.date("%Y-%m-%d %H:%M:%S")
        local page = self.ui.document.info.has_pages and
                self.hold_pos.page or self.selected_text.pos0
        return {
            page = page,
            pos0 = self.selected_text.pos0,
            pos1 = self.selected_text.pos1,
            datetime = datetime,
            notes = self.selected_text.text,
            highlighted = true,
        }
    end
end

function ReaderHighlight:saveHighlight()
    self.ui:handleEvent(Event:new("AddHighlight"))
    logger.dbg("save highlight")
    local page = self.hold_pos.page
    if self.hold_pos and self.selected_text and self.selected_text.pos0
        and self.selected_text.pos1 then
        if not self.view.highlight.saved[page] then
            self.view.highlight.saved[page] = {}
        end
        local datetime = os.date("%Y-%m-%d %H:%M:%S")
        local hl_item = {
            datetime = datetime,
            text = self.selected_text.text,
            pos0 = self.selected_text.pos0,
            pos1 = self.selected_text.pos1,
            pboxes = self.selected_text.pboxes,
            drawer = self.view.highlight.saved_drawer,
        }
        table.insert(self.view.highlight.saved[page], hl_item)
        local bookmark_item = self:getHighlightBookmarkItem()
        if bookmark_item then
            self.ui.bookmark:addBookmark(bookmark_item)
        end
        --[[
        -- disable exporting hightlights to My Clippings
        -- since it's not portable and there is a better Evernote plugin
        -- to do the same thing
        if self.selected_text.text ~= "" then
            self:exportToClippings(page, hl_item)
        end
        --]]
        if self.selected_text.pboxes then
            self:exportToDocument(page, hl_item)
        end
    end
end

--[[
function ReaderHighlight:exportToClippings(page, item)
    logger.dbg("export highlight to clippings", item)
    local clippings = io.open("/mnt/us/documents/My Clippings.txt", "a+")
    if clippings and item.text then
        local current_locale = os.setlocale()
        os.setlocale("C")
        clippings:write(self.document.file:gsub("(.*/)(.*)", "%2").."\n")
        clippings:write("- KOReader Highlight Page "..page.." ")
        clippings:write("| Added on "..os.date("%A, %b %d, %Y %I:%M:%S %p\n\n"))
        -- My Clippings only holds one line of highlight
        clippings:write(item["text"]:gsub("\n", " ").."\n")
        clippings:write("==========\n")
        clippings:close()
        os.setlocale(current_locale)
    end
end
--]]

function ReaderHighlight:exportToDocument(page, item)
    logger.dbg("export highlight to document", item)
    self.ui.document:saveHighlight(page, item)
end

function ReaderHighlight:addNote()
    self:handleEvent(Event:new("addNote"))
    logger.dbg("add Note")
end

function ReaderHighlight:lookupWikipedia()
    if self.selected_text then
        self.ui:handleEvent(Event:new("LookupWikipedia", self.selected_text.text))
    end
end

function ReaderHighlight:onHighlightSearch()
    logger.dbg("search highlight")
    self:highlightFromHoldPos()
    if self.selected_text then
        local text = require("util").stripePunctuations(self.selected_text.text)
        self.ui:handleEvent(Event:new("ShowSearchDialog", text))
    end
end

function ReaderHighlight:onHighlightDictLookup()
    logger.dbg("dictionary lookup highlight")
    self:highlightFromHoldPos()
    if self.selected_text then
        self.ui:handleEvent(Event:new("LookupWord", self.selected_text.text))
    end
end

function ReaderHighlight:shareHighlight()
    logger.info("share highlight")
end

function ReaderHighlight:moreAction()
    logger.info("more action")
end

function ReaderHighlight:deleteHighlight(page, i)
    self.ui:handleEvent(Event:new("DelHighlight"))
    logger.dbg("delete highlight")
    local removed = table.remove(self.view.highlight.saved[page], i)
    self.ui.bookmark:removeBookmark({
        page = self.ui.document.info.has_pages and page or removed.pos0,
        datetime = removed.datetime,
    })
end

function ReaderHighlight:editHighlight()
    logger.info("edit highlight")
end

function ReaderHighlight:onReadSettings(config)
    self.view.highlight.saved_drawer = config:readSetting("highlight_drawer") or self.view.highlight.saved_drawer
    local disable_highlight = config:readSetting("highlight_disabled")
    if disable_highlight == nil then
        disable_highlight = G_reader_settings:readSetting("highlight_disabled") or false
    end
    self.view.highlight.disabled = disable_highlight
end

function ReaderHighlight:onSaveSettings()
    self.ui.doc_settings:saveSetting("highlight_drawer", self.view.highlight.saved_drawer)
    self.ui.doc_settings:saveSetting("highlight_disabled", self.view.highlight.disabled)
end

function ReaderHighlight:onClose()
    UIManager:close(self.highlight_dialog)
    -- clear highlighted text
    self:clear()
end

function ReaderHighlight:makeDefault(highlight_disabled)
    local new_text
    if highlight_disabled then
        new_text = _("Disable highlight by default.")
    else
        new_text = _("Enable highlight by default.")
    end
    UIManager:show(ConfirmBox:new{
        text = new_text,
        ok_callback = function()
            G_reader_settings:saveSetting("highlight_disabled", highlight_disabled)
        end,
    })
    self.view.highlight.disabled = highlight_disabled
end

return ReaderHighlight
