local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
local Device = require("ui/device")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local ButtonDialog = require("ui/widget/buttondialog")
local DEBUG = require("dbg")
local _ = require("gettext")

local ReaderHighlight = InputContainer:new{}

function ReaderHighlight:init()
    self.ui.menu:registerToMainMenu(self)
end

function ReaderHighlight:initGesListener()
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
        Hold = {
            GestureRange:new{
                ges = "hold",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight()
                }
            }
        },
        HoldRelease = {
            GestureRange:new{
                ges = "hold_release",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight()
                }
            }
        },
        HoldPan = {
            GestureRange:new{
                ges = "hold_pan",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight()
                },
                rate = 2.0,
            }
        },
    }
end

function ReaderHighlight:addToMainMenu(tab_item_table)
    -- insert table to main reader menu
    table.insert(tab_item_table.typeset, {
        text = _("Set highlight drawer "),
        sub_item_table = self:genHighlightDrawerMenu(),
    })
end

function ReaderHighlight:genHighlightDrawerMenu()
    return {
        {
            text = _("Lighten"),
            checked_func = function()
                return self.view.highlight.saved_drawer == "lighten"
            end,
            callback = function()
                self.view.highlight.saved_drawer = "lighten"
            end
        },
        {
            text = _("Underscore"),
            checked_func = function()
                return self.view.highlight.saved_drawer == "underscore"
            end,
            callback = function()
                self.view.highlight.saved_drawer = "underscore"
            end
        },
        {
            text = _("Invert"),
            checked_func = function()
                return self.view.highlight.saved_drawer == "invert"
            end,
            callback = function()
                self.view.highlight.saved_drawer = "invert"
            end
        },
    }
end

function ReaderHighlight:onSetDimensions(dimen)
    -- update listening according to new screen dimen
    if Device:isTouchDevice() then
        self:initGesListener()
    end
end

function ReaderHighlight:onTap(arg, ges)
    if self.hold_pos then
        if self.ui.document.info.has_pages then
            self.view.highlight.temp[self.hold_pos.page] = nil
        else
            self.ui.document:clearSelection()
        end
        self.hold_pos = nil
        UIManager:setDirty(self.dialog, "partial")
        return true
    end
    if self.ui.document.info.has_pages then
        return self:onTapPageSavedHighlight(ges)
    else
        return self:onTapXPointerSavedHighlight(ges)
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
        if not items then items = {} end
        for i = 1, #items do
            local pos0, pos1 = items[i].pos0, items[i].pos1
            local boxes = self.ui.document:getPageBoxesFromPositions(page, pos0, pos1)
            if boxes then
                for index, box in pairs(boxes) do
                    if inside_box(pos, box) then
                        DEBUG("Tap on hightlight")
                        return self:onShowHighlightDialog(page, i)
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
        if not items then items = {} end
        for i = 1, #items do
            local pos0, pos1 = items[i].pos0, items[i].pos1
            local boxes = self.ui.document:getScreenBoxesFromPositions(pos0, pos1)
            if boxes then
                for index, box in pairs(boxes) do
                    if inside_box(pos, box) then
                        DEBUG("Tap on hightlight")
                        return self:onShowHighlightDialog(page, i)
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
                        UIManager:close(self.edit_highlight_dialog)
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
    self.hold_pos = self.view:screenToPageTransform(ges.pos)
    DEBUG("hold position in page", self.hold_pos)
    if not self.hold_pos then
        DEBUG("not inside page area")
        return true
    end

    local ok, word = pcall(self.ui.document.getWordFromPosition, self.ui.document, self.hold_pos)
    if ok and word then
        DEBUG("selected word:", word)
        self.selected_word = word
        if self.ui.document.info.has_pages then
            local boxes = {}
            table.insert(boxes, self.selected_word.sbox)
            self.view.highlight.temp[self.hold_pos.page] = boxes
        end
        UIManager:setDirty(self.dialog, "partial")
    end
    return true
end

function ReaderHighlight:onHoldPan(arg, ges)
    if self.hold_pos == nil then
        DEBUG("no previous hold position")
        return true
    end
    self.holdpan_pos = self.view:screenToPageTransform(ges.pos)
    DEBUG("holdpan position in page", self.holdpan_pos)
    self.selected_text = self.ui.document:getTextFromPositions(self.hold_pos, self.holdpan_pos)
    DEBUG("selected text:", self.selected_text)
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
    UIManager:setDirty(self.dialog, "partial")
end

function ReaderHighlight:lookup(selected_word)
    -- if we extracted text directly
    if selected_word.word then
        local word_box = self.view:pageToScreenTransform(self.hold_pos.page, selected_word.sbox)
        self.ui:handleEvent(Event:new("LookupWord", self, selected_word.word, word_box))
    -- or we will do OCR
    elseif selected_word.sbox and self.hold_pos then
        local word = self.ui.document:getOCRWord(self.hold_pos.page, selected_word)
        DEBUG("OCRed word:", word)
        local word_box = self.view:pageToScreenTransform(self.hold_pos.page, selected_word.sbox)
        self.ui:handleEvent(Event:new("LookupWord", self, word, word_box))
    end
end

function ReaderHighlight:translate(selected_text)
    if selected_text.text ~= "" then
        self.ui:handleEvent(Event:new("TranslateText", self, selected_text.text))
    -- or we will do OCR
    else
        local text = self.ui.document:getOCRText(self.hold_pos.page, selected_text)
        DEBUG("OCRed text:", text)
        self.ui:handleEvent(Event:new("TranslateText", self, text))
    end
end

function ReaderHighlight:onHoldRelease(arg, ges)
    if self.selected_word then
        self:lookup(self.selected_word)
        self.selected_word = nil
    elseif self.selected_text then
        DEBUG("show highlight dialog")
        self.highlight_dialog = ButtonDialog:new{
            buttons = {
                {
                    {
                        text = _("Highlight"),
                        callback = function()
                            self:saveHighlight()
                            UIManager:close(self.highlight_dialog)
                            self:handleEvent(Event:new("Tap"))
                        end,
                    },
                    {
                        text = _("Add Note"),
                        enabled = false,
                        callback = function()
                            self:addNote()
                            UIManager:close(self.highlight_dialog)
                            self:handleEvent(Event:new("Tap"))
                        end,
                    },
                },
                {
                    {
                        text = _("Translate"),
                        enabled = false,
                        callback = function()
                            self:translate(self.selected_text)
                            UIManager:close(self.highlight_dialog)
                            self:handleEvent(Event:new("Tap"))
                        end,
                    },
                    {
                        text = _("Share"),
                        enabled = false,
                        callback = function()
                            self:shareHighlight()
                            UIManager:close(self.highlight_dialog)
                            self:handleEvent(Event:new("Tap"))
                        end,
                    },
                },
                {
                    {
                        text = _("More"),
                        enabled = false,
                        callback = function()
                            self:moreAction()
                            UIManager:close(self.highlight_dialog)
                            self:handleEvent(Event:new("Tap"))
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

function ReaderHighlight:saveHighlight()
    DEBUG("save highlight")
    local page = self.hold_pos.page
    if self.hold_pos and self.selected_text then
        if not self.view.highlight.saved[page] then
            self.view.highlight.saved[page] = {}
        end
        local hl_item = {}
        hl_item["text"] = self.selected_text.text
        hl_item["pos0"] = self.selected_text.pos0
        hl_item["pos1"] = self.selected_text.pos1
        hl_item["pboxes"] = self.selected_text.pboxes
        hl_item["datetime"] = os.date("%Y-%m-%d %H:%M:%S")
        hl_item["drawer"] = self.view.highlight.saved_drawer
        table.insert(self.view.highlight.saved[page], hl_item)
        if self.selected_text.text ~= "" then
            -- disable exporting hightlights to My Clippings
            -- since it's not potable and there is a better Evernote plugin
            -- to do the same thing
            --self:exportToClippings(page, hl_item)
        end
        if self.selected_text.pboxes then
            self:exportToDocument(page, hl_item)
        end
    end
    --DEBUG("saved hightlights", self.view.highlight.saved[page])
end

function ReaderHighlight:exportToClippings(page, item)
    DEBUG("export highlight to clippings", item)
    local clippings = io.open("/mnt/us/documents/My Clippings.txt", "a+")
    if clippings and item.text then
        local current_locale = os.setlocale()
        os.setlocale("C")
        clippings:write(self.document.file:gsub("(.*/)(.*)", "%2").."\n")
        clippings:write("- Koreader Highlight Page "..page.." ")
        clippings:write("| Added on "..os.date("%A, %b %d, %Y %I:%M:%S %p\n\n"))
        -- My Clippings only holds one line of highlight
        clippings:write(item["text"]:gsub("\n", " ").."\n")
        clippings:write("==========\n")
        clippings:close()
        os.setlocale(current_locale)
    end
end

function ReaderHighlight:exportToDocument(page, item)
    DEBUG("export highlight to document", item)
    self.ui.document:saveHighlight(page, item)
end

function ReaderHighlight:addNote()
    DEBUG("add Note")
end

function ReaderHighlight:shareHighlight()
    DEBUG("share highlight")
end

function ReaderHighlight:moreAction()
    DEBUG("more action")
end

function ReaderHighlight:deleteHighlight(page, i)
    DEBUG("delete highlight")
    table.remove(self.view.highlight.saved[page], i)
end

function ReaderHighlight:editHighlight()
    DEBUG("edit highlight")
end

function ReaderHighlight:onReadSettings(config)
    self.view.highlight.saved_drawer = config:readSetting("highlight_drawer") or self.view.highlight.saved_drawer
end

function ReaderHighlight:onSaveSettings()
    self.ui.doc_settings:saveSetting("highlight_drawer", self.view.highlight.saved_drawer)
end

return ReaderHighlight
