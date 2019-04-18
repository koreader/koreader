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
                or self.ui.document.default_css
    local tweaks_css = self.ui.styletweak:getCssText()
    self.ui.document:setStyleSheet(self.css, tweaks_css)

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

    -- set render DPI
    self.render_dpi = config:readSetting("render_dpi") or
        G_reader_settings:readSetting("copt_render_dpi") or 96
    self:setRenderDPI(self.render_dpi)

    -- uncomment if we want font size to follow DPI changes
    -- self.ui.document:setRenderScaleFontWithDPI(1)

    -- set page margins
    self:onSetPageMargins(
        config:readSetting("copt_page_margins") or
        G_reader_settings:readSetting("copt_page_margins") or
        DCREREADER_CONFIG_MARGIN_SIZES_MEDIUM)

    -- default to disable floating punctuation
    -- the floating punctuation should not be boolean value for the following
    -- expression otherwise a false value will never be returned but numerical
    -- values will survive this expression
    self.floating_punctuation = config:readSetting("floating_punctuation") or
        G_reader_settings:readSetting("floating_punctuation") or 0
    self:toggleFloatingPunctuation(self.floating_punctuation)

    -- default to disable TXT formatting as it does more harm than good
    self.txt_preformatted = config:readSetting("txt_preformatted") or
        G_reader_settings:readSetting("txt_preformatted") or 1
    self:toggleTxtPreFormatted(self.txt_preformatted)

    -- default to disable smooth scaling for now.
    self.smooth_scaling = config:readSetting("smooth_scaling")
    if self.smooth_scaling == nil then
        local global = G_reader_settings:readSetting("copt_smooth_scaling")
        self.smooth_scaling = (global == nil or global == 0) and 0 or 1
    end
    self:toggleImageScaling(self.smooth_scaling)
end

function ReaderTypeset:onSaveSettings()
    self.ui.doc_settings:saveSetting("css", self.css)
    self.ui.doc_settings:saveSetting("embedded_css", self.embedded_css)
    self.ui.doc_settings:saveSetting("floating_punctuation", self.floating_punctuation)
    self.ui.doc_settings:saveSetting("embedded_fonts", self.embedded_fonts)
    self.ui.doc_settings:saveSetting("render_dpi", self.render_dpi)
    self.ui.doc_settings:saveSetting("smooth_scaling", self.smooth_scaling)
end

function ReaderTypeset:onToggleEmbeddedStyleSheet(toggle)
    self:toggleEmbeddedStyleSheet(toggle)
    return true
end

function ReaderTypeset:onToggleEmbeddedFonts(toggle)
    self:toggleEmbeddedFonts(toggle)
    return true
end

function ReaderTypeset:onToggleImageScaling(toggle)
    self:toggleImageScaling(toggle)
    return true
end

-- June 2018: epub.css has been cleaned to be more conforming to HTML specs
-- and to not include class name based styles (with conditional compatiblity
-- styles for previously opened documents). It should be usable on all
-- HTML based documents, except FB2 which has some incompatible specs.
-- These other css files have not been updated in the same way, and are
-- kept as-is for when a previously opened document requests one of them.
local OBSOLETED_CSS = {
    "chm.css",
    "cr3.css",
    "doc.css",
    "dict.css",
    "htm.css",
    "rtf.css",
    "txt.css",
}

function ReaderTypeset:onSetRenderDPI(dpi)
    self:setRenderDPI(dpi)
    return true
end

function ReaderTypeset:genStyleSheetMenu()
    local getStyleMenuItem = function(text, css_file, separator)
        return {
            text_func = function()
                return text .. (css_file == G_reader_settings:readSetting("copt_css") and "   ★" or "")
            end,
            callback = function()
                self:setStyleSheet(css_file or self.ui.document.default_css)
            end,
            hold_callback = function(touchmenu_instance)
                self:makeDefaultStyleSheet(css_file, text, touchmenu_instance)
            end,
            checked_func = function()
                if not css_file then -- "Auto"
                    return self.css == self.ui.document.default_css
                end
                return css_file == self.css
            end,
            separator = separator,
        }
    end

    local style_table = {}
    local obsoleted_table = {}

    table.insert(style_table, getStyleMenuItem(_("Clear all external styles"), ""))
    table.insert(style_table, getStyleMenuItem(_("Auto"), nil, true))

    local css_files = {}
    for f in lfs.dir("./data") do
        if lfs.attributes("./data/"..f, "mode") == "file" and string.match(f, "%.css$") then
            css_files[f] = "./data/"..f
        end
    end
    -- Add the 2 main styles
    if css_files["epub.css"] then
        table.insert(style_table, getStyleMenuItem(_("HTML / EPUB (epub.css)"), css_files["epub.css"]))
        css_files["epub.css"] = nil
    end
    if css_files["fb2.css"] then
        table.insert(style_table, getStyleMenuItem(_("FictionBook (fb2.css)"), css_files["fb2.css"], true))
        css_files["fb2.css"] = nil
    end
    -- Add the obsoleted ones to the Obsolete sub menu
    local obsoleted_css = {} -- for check_func of the Obsolete sub menu itself
    for __, css in ipairs(OBSOLETED_CSS) do
        obsoleted_css[css_files[css]] = css
        if css_files[css] then
            table.insert(obsoleted_table, getStyleMenuItem(css, css_files[css]))
            css_files[css] = nil
        end
    end
    -- Sort and add the remaining (user added) files if any
    local user_files = {}
    for css, css_file in pairs(css_files) do
        table.insert(user_files, css)
    end
    table.sort(user_files)
    for __, css in ipairs(user_files) do
        table.insert(style_table, getStyleMenuItem(css, css_files[css]))
    end

    style_table[#style_table].separator = true
    table.insert(style_table, {
        text_func = function()
            local text = _("Obsolete")
            if obsoleted_css[self.css] then
                text = T(_("Obsolete (%1)"), obsoleted_css[self.css])
            end
            if obsoleted_css[G_reader_settings:readSetting("copt_css")] then
                text = text .. "   ★"
            end
            return text
        end,
        sub_item_table = obsoleted_table,
        checked_func = function()
            return obsoleted_css[self.css] ~= nil
        end
    })
    return style_table
end

function ReaderTypeset:onApplyStyleSheet()
    local tweaks_css = self.ui.styletweak:getCssText()
    self.ui.document:setStyleSheet(self.css, tweaks_css)
    self.ui:handleEvent(Event:new("UpdatePos"))
    return true
end

function ReaderTypeset:setStyleSheet(new_css)
    if new_css ~= self.css then
        self.css = new_css
        local tweaks_css = self.ui.styletweak:getCssText()
        self.ui.document:setStyleSheet(new_css, tweaks_css)
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

function ReaderTypeset:toggleImageScaling(toggle)
    if toggle and (toggle == true or toggle == 1) then
        self.smooth_scaling = true
        self.ui.document:setImageScaling(true)
    else
        self.smooth_scaling = false
        self.ui.document:setImageScaling(false)
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

function ReaderTypeset:setRenderDPI(dpi)
    self.render_dpi = dpi
    self.ui.document:setRenderDPI(dpi)
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

function ReaderTypeset:makeDefaultStyleSheet(css, text, touchmenu_instance)
    UIManager:show(ConfirmBox:new{
        text = T( _("Set default style to %1?"), text),
        ok_callback = function()
            G_reader_settings:saveSetting("copt_css", css)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
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
