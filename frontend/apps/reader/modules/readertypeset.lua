local ConfirmBox = require("ui/widget/confirmbox")
local Event = require("ui/event")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local Screen = require("device").screen
local T = require("ffi/util").template

local ReaderTypeset = InputContainer:new{
    css_menu_title = _("Style"),
    css = nil,
    internal_css = true,
}

function ReaderTypeset:init()
    self.ui.menu:registerToMainMenu(self)
end

function ReaderTypeset:onReadSettings(config)
    self.css = config:readSetting("css") or G_reader_settings:readSetting("copt_css")
    if self.css then
        self.ui.document:setStyleSheet(self.css)
    else
        self.ui.document:setStyleSheet(self.ui.document.default_css)
        self.css = self.ui.document.default_css
    end

    self.embedded_fonts = config:readSetting("embedded_fonts")
    if self.embedded_fonts == nil then
        -- default to enable embedded fonts
        -- note that it's a bit confusing here:
        -- global settins store 0/1, while document settings store false/true
        -- we leave it that way for now to maintain backwards compatibility
        local global = G_reader_settings:readSetting("copt_embedded_fonts")
        self.embedded_fonts = (global == nil or global == 1) and true or false
    end
    -- As this is new, call it only when embedded_fonts are explicitely disabled
    -- self.ui.document:setEmbeddedFonts(self.embedded_fonts and 1 or 0)
    if not self.embedded_fonts then
        self.ui.document:setEmbeddedFonts(0)
    end

    self.embedded_css = config:readSetting("embedded_css")
    if self.embedded_css == nil then
        -- default to enable embedded CSS
        -- note that it's a bit confusing here:
        -- global settins store 0/1, while document settings store false/true
        -- we leave it that way for now to maintain backwards compatibility
        local global = G_reader_settings:readSetting("copt_embedded_css")
        self.embedded_css = (global == nil or global == 1) and true or false
    end
    self.ui.document:setEmbeddedStyleSheet(self.embedded_css and 1 or 0)

    -- set page margins
    self:onSetPageMargins(
        config:readSetting("copt_page_margins") or
        G_reader_settings:readSetting("copt_page_margins") or
        DCREREADER_CONFIG_MARGIN_SIZES_MEDIUM)

    -- default to enable floating punctuation
    -- the floating punctuation should not be boolean value for the following
    -- expression otherwise a false value will never be returned but numerical
    -- values will survive this expression
    self.floating_punctuation = config:readSetting("floating_punctuation") or
        G_reader_settings:readSetting("floating_punctuation") or 1
    self:toggleFloatingPunctuation(self.floating_punctuation)

    -- default to disable TXT formatting as it does more harm than good
    self.txt_preformatted = config:readSetting("txt_preformatted") or
        G_reader_settings:readSetting("txt_preformatted") or 1
    self:toggleTxtPreFormatted(self.txt_preformatted)
end

function ReaderTypeset:onSaveSettings()
    self.ui.doc_settings:saveSetting("css", self.css)
    self.ui.doc_settings:saveSetting("embedded_css", self.embedded_css)
    self.ui.doc_settings:saveSetting("floating_punctuation", self.floating_punctuation)
    self.ui.doc_settings:saveSetting("embedded_fonts", self.embedded_fonts)
end

function ReaderTypeset:onToggleEmbeddedStyleSheet(toggle)
    self:toggleEmbeddedStyleSheet(toggle)
    return true
end

function ReaderTypeset:onToggleEmbeddedFonts(toggle)
    self:toggleEmbeddedFonts(toggle)
    return true
end

function ReaderTypeset:genStyleSheetMenu()
    local style_table = {}
    local file_list = {
        {
            text = _("Clear all external styles"),
            css = ""
        },
        {
            text = _("Auto"),
            css = self.ui.document.default_css
        },
    }
    for f in lfs.dir("./data") do
        if lfs.attributes("./data/"..f, "mode") == "file" and string.match(f, "%.css$") then
            table.insert(file_list, {
                text = f,
                css = "./data/"..f
            })
        end
    end
    table.sort(file_list, function(v1,v2) return v1.text < v2.text end) -- sort by name
    for i,file in ipairs(file_list) do
        table.insert(style_table, {
            text = file["text"],
            callback = function()
                self:setStyleSheet(file["css"])
            end,
            hold_callback = function()
                self:makeDefaultStyleSheet(file["css"], file["text"])
            end,
            checked_func = function()
                return file.css == self.css
            end
        })
    end
    return style_table
end

function ReaderTypeset:setStyleSheet(new_css)
    if new_css ~= self.css then
        self.css = new_css
        self.ui.document:setStyleSheet(new_css)
        self.ui:handleEvent(Event:new("UpdatePos"))
    end
end

function ReaderTypeset:setEmbededStyleSheetOnly()
    if self.css ~= nil then
        -- clear applied css
        self.ui.document:setStyleSheet("")
        self.ui.document:setEmbeddedStyleSheet(1)
        self.css = nil
        self.ui:handleEvent(Event:new("UpdatePos"))
    end
end

function ReaderTypeset:toggleEmbeddedStyleSheet(toggle)
    if not toggle then
        self.embedded_css = false
        self:setStyleSheet(self.ui.document.default_css)
        self.ui.document:setEmbeddedStyleSheet(0)
    else
        self.embedded_css = true
        --self:setStyleSheet(self.ui.document.default_css)
        self.ui.document:setEmbeddedStyleSheet(1)
    end
    self.ui:handleEvent(Event:new("UpdatePos"))
end

function ReaderTypeset:toggleEmbeddedFonts(toggle)
    if not toggle then
        self.embedded_fonts = false
        self.ui.document:setEmbeddedFonts(0)
    else
        self.embedded_fonts = true
        self.ui.document:setEmbeddedFonts(1)
    end
    self.ui:handleEvent(Event:new("UpdatePos"))
end

function ReaderTypeset:toggleFloatingPunctuation(toggle)
    -- for some reason the toggle value read from history files may stay boolean
    -- and there seems no more elegant way to convert boolean values to numbers
    if toggle == true then
        toggle = 1
    elseif toggle == false then
        toggle = 0
    end
    self.ui.document:setFloatingPunctuation(toggle)
    self.ui:handleEvent(Event:new("UpdatePos"))
end

function ReaderTypeset:toggleTxtPreFormatted(toggle)
    self.ui.document:setTxtPreFormatted(toggle)
    self.ui:handleEvent(Event:new("UpdatePos"))
end

function ReaderTypeset:addToMainMenu(menu_items)
    -- insert table to main reader menu
    menu_items.set_render_style = {
        text = self.css_menu_title,
        sub_item_table = self:genStyleSheetMenu(),
    }
    menu_items.floating_punctuation = {
        text = _("Floating punctuation"),
        checked_func = function() return self.floating_punctuation == 1 end,
        callback = function()
            self.floating_punctuation = self.floating_punctuation == 1 and 0 or 1
            self:toggleFloatingPunctuation(self.floating_punctuation)
        end,
        hold_callback = function() self:makeDefaultFloatingPunctuation() end,
    }
end

function ReaderTypeset:makeDefaultFloatingPunctuation()
    local toggler = self.floating_punctuation == 1 and _("On") or _("Off")
    UIManager:show(ConfirmBox:new{
        text = T(
            _("Set default floating punctuation to %1?"),
            toggler
        ),
        ok_callback = function()
            G_reader_settings:saveSetting("floating_punctuation", self.floating_punctuation)
        end,
    })
end

function ReaderTypeset:makeDefaultStyleSheet(css, text)
    text = text or css
    if css then
        UIManager:show(ConfirmBox:new{
            text = T( _("Set default style to %1?"), text),
            ok_callback = function()
                G_reader_settings:saveSetting("copt_css", css)
            end,
        })
    end
end

function ReaderTypeset:onSetPageMargins(margins)
    local left = Screen:scaleBySize(margins[1])
    local top = Screen:scaleBySize(margins[2])
    local right = Screen:scaleBySize(margins[3])
    local bottom
    if self.view.footer.has_no_mode then
        bottom = Screen:scaleBySize(margins[4])
    else
        bottom = Screen:scaleBySize(margins[4] + DMINIBAR_HEIGHT)
    end
    self.ui.document:setPageMargins(left, top, right, bottom)
    self.ui:handleEvent(Event:new("UpdatePos"))
    return true
end

return ReaderTypeset
