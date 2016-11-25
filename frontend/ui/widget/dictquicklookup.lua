local InputContainer = require("ui/widget/container/inputcontainer")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local OverlapGroup = require("ui/widget/overlapgroup")
local CloseButton = require("ui/widget/closebutton")
local ButtonTable = require("ui/widget/buttontable")
local InputDialog = require("ui/widget/inputdialog")
local TextWidget = require("ui/widget/textwidget")
local LineWidget = require("ui/widget/linewidget")
local GestureRange = require("ui/gesturerange")
local Button = require("ui/widget/button")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Device = require("device")
local Geom = require("ui/geometry")
local Event = require("ui/event")
local Font = require("ui/font")
local DEBUG = require("dbg")
local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")

--[[
Display quick lookup word definition
]]
local DictQuickLookup = InputContainer:new{
    results = nil,
    lookupword = nil,
    dictionary = nil,
    definition = nil,
    dict_index = 1,
    title_face = Font:getFace("tfont", 22),
    word_face = Font:getFace("tfont", 22),
    content_face = Font:getFace("cfont", DDICT_FONT_SIZE),
    width = nil,
    height = nil,
    -- box of highlighted word, quick lookup window tries to not hide the word
    word_box = nil,

    title_padding = Screen:scaleBySize(5),
    title_margin = Screen:scaleBySize(2),
    word_padding = Screen:scaleBySize(5),
    word_margin = Screen:scaleBySize(2),
    definition_padding = Screen:scaleBySize(2),
    definition_margin = Screen:scaleBySize(2),
    button_padding = Screen:scaleBySize(14),
}

function DictQuickLookup:init()
    self:changeToDefaultDict()
    if Device:hasKeys() then
        self.key_events = {
            Close = { {"Back"}, doc = "close quick lookup" }
        }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            TapCloseDict = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    }
                },
            },
            Swipe = {
                GestureRange:new{
                    ges = "swipe",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    }
                },
            },
            HoldWord = {
                GestureRange:new{
                    ges = "hold",
                    range = function()
                        return self.region
                    end,
                },
                -- callback function when HoldWord is handled as args
                args = function(word)
                    self.ui:handleEvent(
                        Event:new("LookupWord", word, self.word_box, self.highlight))
                end
            },
        }
        table.insert(self.dict_bar,
                     CloseButton:new{ window = self, })
    end
end

function DictQuickLookup:update()
    local orig_dimen = self.dict_frame and self.dict_frame.dimen or Geom:new{}
    -- calculate window dimension and try to not hide highlighted word
    self.align = "center"
    self.region = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    if self.word_box then
        local box = self.word_box
        if box.y + box.h/2 < Screen:getHeight()*0.3 then
            self.region.y = box.y + box.h
            self.region.h = Screen:getHeight() - box.y - box.h
            self.align = "top"
        elseif box.y + box.h/2 > Screen:getHeight()*0.7 then
            self.region.y = 0
            self.region.h = box.y
            self.align = "bottom"
        end
    end
    self.height = math.min(self.region.h*0.7, Screen:getHeight()*0.5)
    -- dictionary title
    self.dict_title = FrameContainer:new{
        padding = self.title_padding,
        margin = self.title_margin,
        bordersize = 0,
        TextWidget:new{
            text = self.dictionary,
            face = self.title_face,
            bold = true,
            width = self.width,
        }
    }
    -- lookup word
    local lookup_word = Button:new{
        padding = self.word_padding,
        margin = self.word_margin,
        bordersize = 0,
        text = self.lookupword,
        text_font_face = "tfont",
        text_font_size = 22,
        hold_callback = function() self:lookupInputWord(self.lookupword) end,
    }
    -- word definition
    local definition = FrameContainer:new{
        padding = self.definition_padding,
        margin = self.definition_margin,
        bordersize = 0,
        ScrollTextWidget:new{
            text = self.definition,
            face = self.content_face,
            width = self.width,
            height = self.height*0.7,
            dialog = self,
        },
    }
    local button_table = ButtonTable:new{
        width = math.max(self.width, definition:getSize().w),
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = {
            {
                {
                    text = "<<",
                    enabled = self:isPrevDictAvaiable(),
                    callback = function()
                        self:changeToPrevDict()
                    end,
                },
                {
                    text = self:getHighlightText(),
                    enabled = select(2, self:getHighlightText()),
                    callback = function()
                        self.ui:handleEvent(Event:new("Highlight"))
                        self:update()
                    end,
                },
                {
                    text = ">>",
                    enabled = self:isNextDictAvaiable(),
                    callback = function()
                        self:changeToNextDict()
                    end,
                },
            },
            {
                {
                    text = _("Wikipedia"),
                    enabled = not self.wiki,
                    callback = function()
                        UIManager:scheduleIn(0.1, function()
                            self:lookupWikipedia()
                        end)
                    end,
                },
                {
                    text = _("Add Note"),
                    enabled = false,
                    callback = function()
                        self.ui:handleEvent(Event:new("HighlightAddNote"))
                    end,
                },
                {
                    text = _("Search"),
                    callback = function()
                        self.ui:handleEvent(Event:new("HighlightSearch"))
                        UIManager:close(self)
                    end,
                },
            },
        },
        zero_sep = true,
        show_parent = self,
    }
    local title_bar = LineWidget:new{
        dimen = Geom:new{
            w = button_table:getSize().w + self.button_padding,
            h = Screen:scaleBySize(2),
        }
    }

    self.dict_bar = OverlapGroup:new{
        dimen = {
            w = button_table:getSize().w + self.button_padding,
            h = self.dict_title:getSize().h
        },
        self.dict_title,
    }

    self.dict_frame = FrameContainer:new{
        radius = 8,
        bordersize = 3,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.dict_bar,
            title_bar,
            -- word
            LeftContainer:new{
                dimen = Geom:new{
                    w = title_bar:getSize().w,
                    h = lookup_word:getSize().h,
                },
                lookup_word,
            },
            -- definition
            CenterContainer:new{
                dimen = Geom:new{
                    w = title_bar:getSize().w,
                    h = definition:getSize().h,
                },
                definition,
            },
            -- buttons
            CenterContainer:new{
                dimen = Geom:new{
                    w = title_bar:getSize().w,
                    h = button_table:getSize().h,
                },
                button_table,
            }
        }
    }
    self[1] = WidgetContainer:new{
        align = self.align,
        dimen = self.region,
        FrameContainer:new{
            bordersize = 0,
            padding = Screen:scaleBySize(5),
            self.dict_frame,
        }
    }
    UIManager:setDirty("all", function()
        local update_region = self.dict_frame.dimen:combine(orig_dimen)
        DEBUG("update dict region", update_region)
        return "partial", update_region
    end)
end

function DictQuickLookup:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self.dict_frame.dimen
    end)
    return true
end

function DictQuickLookup:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.dict_frame.dimen
    end)
    return true
end

function DictQuickLookup:getHighlightedItem()
    if not self.ui then return end
    return self.ui.highlight:getHighlightBookmarkItem()
end

function DictQuickLookup:getHighlightText()
    local item = self:getHighlightedItem()
    if not item then
        return _("Highlight"), false
    elseif self.ui.bookmark:isBookmarkAdded(item) then
        return _("Unhighlight"), false
    else
        return _("Highlight"), true
    end
end

function DictQuickLookup:isPrevDictAvaiable()
    return self.dict_index > 1
end

function DictQuickLookup:isNextDictAvaiable()
    return self.dict_index < #self.results
end

function DictQuickLookup:changeToPrevDict()
    self:changeDictionary(self.dict_index - 1)
end

function DictQuickLookup:changeToNextDict()
    self:changeDictionary(self.dict_index + 1)
end

function DictQuickLookup:changeDictionary(index)
    if not self.results[index] then return end
    self.dict_index = index
    self.dictionary = self.results[index].dict
    self.lookupword = self.results[index].word
    self.definition = self.results[index].definition

    self:update()
end

function DictQuickLookup:changeToDefaultDict()
    if self.dictionary then
        -- dictionaries that have definition of the first word(accurate word)
        -- excluding Fuzzy queries.
        local n_accurate_dicts = nil
        local default_word = self.results[1].word
        for i=1, #self.results do
            if self.results[i].word == default_word then
                n_accurate_dicts = i
            else
                break
            end
        end
        -- change to dictionary specified by self.dictionary
        for i=1, n_accurate_dicts do
            if self.results[i].dict == self.dictionary then
                self:changeDictionary(i)
                break
            end
            -- cannot find definition in default dictionary
            if i == n_accurate_dicts then
                self:changeDictionary(1)
            end
        end
    else
        self:changeDictionary(1)
    end
end

function DictQuickLookup:onAnyKeyPressed()
    -- triggered by our defined key events
    UIManager:close(self)
    return true
end

function DictQuickLookup:onTapCloseDict(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.dict_frame.dimen) then
        self:onClose()
        return true
    elseif not ges_ev.pos:notIntersectWith(self.dict_title.dimen) then
        self.ui:handleEvent(Event:new("UpdateDefaultDict", self.dictionary))
        return true
    end
    return true
end

function DictQuickLookup:onClose()
    UIManager:close(self)
    for i = #self.window_list, 1, -1 do
        local window = self.window_list[i]
        if window == self then
            table.remove(self.window_list, i)
        end
    end
    if self.highlight then
        self.highlight:clear()
    end
    return true
end

function DictQuickLookup:onHoldClose()
    self:onClose()
    for i = #self.window_list, 1, -1 do
        local window = self.window_list[i]
        UIManager:close(window)
        table.remove(self.window_list, i)
    end
    return true
end

function DictQuickLookup:onSwipe(arg, ges)
    if ges.direction == "west" then
        self:changeToNextDict()
    elseif ges.direction == "east" then
        self:changeToPrevDict()
    end
    return true
end

function DictQuickLookup:lookupInputWord(hint)
    self:onClose()
    self.input_dialog = InputDialog:new{
        title = _("Input lookup word"),
        input = hint,
        input_hint = hint or "",
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self:closeInputDialog()
                    end,
                },
                {
                    text = _("Lookup"),
                    is_enter_default = true,
                    callback = function()
                        self:closeInputDialog()
                        self:inputLookup()
                    end,
                },
            }
        },
    }
    self.input_dialog:onShowKeyboard()
    UIManager:show(self.input_dialog)
end

function DictQuickLookup:inputLookup()
    local word = self.input_dialog:getInputText()
    if word and word ~= "" then
        local event = self.wiki and "LookupWikipedia" or "LookupWord"
        self.ui:handleEvent(Event:new(event, word))
    end
end

function DictQuickLookup:closeInputDialog()
    UIManager:close(self.input_dialog)
end

function DictQuickLookup:lookupWikipedia()
    self.ui:handleEvent(Event:new("LookupWikipedia", self.word, self.word_box))
end

return DictQuickLookup
