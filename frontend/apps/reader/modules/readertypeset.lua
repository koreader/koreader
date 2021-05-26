local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local Math = require("optmath")
local Notification = require("ui/widget/notification")
local lfs = require("libs/libkoreader-lfs")
local optionsutil = require("ui/data/optionsutil")
local _ = require("gettext")
local Screen = require("device").screen
local T = require("ffi/util").template

local ReaderTypeset = InputContainer:new{
    css_menu_title = _("Style"),
    css = nil,
    internal_css = true,
    unscaled_margins = nil,
}

function ReaderTypeset:init()
    self.ui.menu:registerToMainMenu(self)
end

function ReaderTypeset:onReadSettings(config)
    self.css = config:readSetting("css")
            or G_reader_settings:readSetting("copt_css")
            or self.ui.document.default_css
    local tweaks_css = self.ui.styletweak:getCssText()
    self.ui.document:setStyleSheet(self.css, tweaks_css)

    if config:has("embedded_fonts") then
        self.embedded_fonts = config:isTrue("embedded_fonts")
    else
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

    if config:has("embedded_css") then
        self.embedded_css = config:isTrue("embedded_css")
    else
        -- default to enable embedded CSS
        -- note that it's a bit confusing here:
        -- global settings store 0/1, while document settings store false/true
        -- we leave it that way for now to maintain backwards compatibility
        local global = G_reader_settings:readSetting("copt_embedded_css")
        self.embedded_css = (global == nil or global == 1) and true or false
    end
    self.ui.document:setEmbeddedStyleSheet(self.embedded_css and 1 or 0)

    -- Block rendering mode: stay with legacy rendering for books
    -- previously opened so bookmarks and highlights stay valid.
    -- For new books, use 'web' mode below in BLOCK_RENDERING_FLAGS
    if config:has("copt_block_rendering_mode") then
        self.block_rendering_mode = config:readSetting("copt_block_rendering_mode")
    else
        if config:has("last_xpointer") then
            -- We have a last_xpointer: this book was previously opened
            self.block_rendering_mode = 0
        else
            self.block_rendering_mode = G_reader_settings:readSetting("copt_block_rendering_mode")
                                     or 3 -- default to 'web' mode
        end
        -- Let ConfigDialog know so it can update it on screen and have it saved on quit
        self.ui.document.configurable.block_rendering_mode = self.block_rendering_mode
    end
    self:setBlockRenderingMode(self.block_rendering_mode)

    -- set render DPI
    self.render_dpi = config:readSetting("render_dpi")
                   or G_reader_settings:readSetting("copt_render_dpi")
                   or 96
    self:setRenderDPI(self.render_dpi)

    -- uncomment if we want font size to follow DPI changes
    -- self.ui.document:setRenderScaleFontWithDPI(1)

    -- set page margins
    local h_margins = config:readSetting("copt_h_page_margins")
                   or G_reader_settings:readSetting("copt_h_page_margins")
                   or DCREREADER_CONFIG_H_MARGIN_SIZES_MEDIUM
    local t_margin = config:readSetting("copt_t_page_margin")
                  or G_reader_settings:readSetting("copt_t_page_margin")
                  or DCREREADER_CONFIG_T_MARGIN_SIZES_LARGE
    local b_margin = config:readSetting("copt_b_page_margin")
                  or G_reader_settings:readSetting("copt_b_page_margin")
                  or DCREREADER_CONFIG_B_MARGIN_SIZES_LARGE
    self.unscaled_margins = { h_margins[1], t_margin, h_margins[2], b_margin }
    self:onSetPageMargins(self.unscaled_margins)
    self.sync_t_b_page_margins = config:readSetting("copt_sync_t_b_page_margins")
                              or G_reader_settings:readSetting("copt_sync_t_b_page_margins")
                              or 0
    self.sync_t_b_page_margins = self.sync_t_b_page_margins == 1 and true or false

    -- default to disable TXT formatting as it does more harm than good
    self.txt_preformatted = config:readSetting("txt_preformatted")
                         or G_reader_settings:readSetting("txt_preformatted")
                         or 1
    self:toggleTxtPreFormatted(self.txt_preformatted)

    -- default to disable smooth scaling for now.
    if config:has("smooth_scaling") then
        self.smooth_scaling = config:isTrue("smooth_scaling")
    else
        local global = G_reader_settings:readSetting("copt_smooth_scaling")
        self.smooth_scaling = global == 1 and true or false
    end
    self:toggleImageScaling(self.smooth_scaling)

    -- default to automagic nightmode-friendly handling of images
    if config:has("nightmode_images") then
        self.nightmode_images = config:isTrue("nightmode_images")
    else
        local global = G_reader_settings:readSetting("copt_nightmode_images")
        self.nightmode_images = (global == nil or global == 1) and true or false
    end
    self:toggleNightmodeImages(self.nightmode_images)
end

function ReaderTypeset:onSaveSettings()
    self.ui.doc_settings:saveSetting("css", self.css)
    self.ui.doc_settings:saveSetting("embedded_css", self.embedded_css)
    self.ui.doc_settings:saveSetting("embedded_fonts", self.embedded_fonts)
    self.ui.doc_settings:saveSetting("render_dpi", self.render_dpi)
    self.ui.doc_settings:saveSetting("smooth_scaling", self.smooth_scaling)
    self.ui.doc_settings:saveSetting("nightmode_images", self.nightmode_images)
end

function ReaderTypeset:onToggleEmbeddedStyleSheet(toggle)
    self:toggleEmbeddedStyleSheet(toggle)
    if toggle then
        Notification:notify(_("Enabled embedded styles."))
    else
        Notification:notify(_("Disabled embedded styles."))
    end
    return true
end

function ReaderTypeset:onToggleEmbeddedFonts(toggle)
    self:toggleEmbeddedFonts(toggle)
    if toggle then
        Notification:notify(_("Enabled embedded fonts."))
    else
        Notification:notify(_("Disabled embedded fonts."))
    end
    return true
end

function ReaderTypeset:onToggleImageScaling(toggle)
    self:toggleImageScaling(toggle)
    Notification:notify(T( _("Image scaling set to: %1"), optionsutil:getOptionText("ToggleImageScaling", toggle)))
    return true
end

function ReaderTypeset:onToggleNightmodeImages(toggle)
    self:toggleNightmodeImages(toggle)
    return true
end

function ReaderTypeset:onSetBlockRenderingMode(mode)
    self:setBlockRenderingMode(mode)
    Notification:notify(T( _("Render mode set to: %1"), optionsutil:getOptionText("SetBlockRenderingMode", mode)))
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
    Notification:notify(T( _("Zoom set to: %1"), optionsutil:getOptionText("SetRenderDPI", dpi)))
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

    table.insert(style_table, getStyleMenuItem(_("None"), ""))
    table.insert(style_table, getStyleMenuItem(_("Auto"), nil, true))

    local css_files = {}
    for f in lfs.dir("./data") do
        if lfs.attributes("./data/"..f, "mode") == "file" and string.match(f, "%.css$") then
            css_files[f] = "./data/"..f
        end
    end
    -- Add the 3 main styles
    if css_files["epub.css"] then
        table.insert(style_table, getStyleMenuItem(_("HTML / EPUB (epub.css)"), css_files["epub.css"]))
        css_files["epub.css"] = nil
    end
    if css_files["html5.css"] then
        table.insert(style_table, getStyleMenuItem(_("HTML5 (html5.css)"), css_files["html5.css"]))
        css_files["html5.css"] = nil
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
                text = T(_("Obsolete (%1)"), BD.filename(obsoleted_css[self.css]))
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

-- crengine enhanced block rendering feature/flags (see crengine/include/lvrend.h):
--                                               legacy flat book web
-- ENHANCED                           0x00000001          x    x   x
-- ALLOW_PAGE_BREAK_WHEN_NO_CONTENT   0x00000002                   x
--
-- COLLAPSE_VERTICAL_MARGINS          0x00000010          x    x   x
-- ALLOW_VERTICAL_NEGATIVE_MARGINS    0x00000020          x    x   x
-- ALLOW_NEGATIVE_COLLAPSED_MARGINS   0x00000040                   x
--
-- ENSURE_MARGIN_AUTO_ALIGNMENT       0x00000100               x   x
-- ALLOW_HORIZONTAL_NEGATIVE_MARGINS  0x00000200                   x
-- ALLOW_HORIZONTAL_BLOCK_OVERFLOW    0x00000400                   x
-- ALLOW_HORIZONTAL_PAGE_OVERFLOW     0x00000800                   x
--
-- USE_W3C_BOX_MODEL                  0x00001000          x    x   x
-- ALLOW_STYLE_W_H_ABSOLUTE_UNITS     0x00002000                   x
-- ENSURE_STYLE_WIDTH                 0x00004000               x   x
-- ENSURE_STYLE_HEIGHT                0x00008000                   x
--
-- WRAP_FLOATS                        0x00010000          x    x   x
-- PREPARE_FLOATBOXES                 0x00020000          x    x   x
-- FLOAT_FLOATBOXES                   0x00040000               x   x
-- DO_NOT_CLEAR_OWN_FLOATS            0x00100000               x   x
-- ALLOW_EXACT_FLOATS_FOOTPRINTS      0x00200000               x   x
--
-- BOX_INLINE_BLOCKS                  0x01000000          x    x   x
-- COMPLETE_INCOMPLETE_TABLES         0x02000000          x    x   x

local BLOCK_RENDERING_FLAGS = {
    0x00000000, -- legacy block rendering
    0x03030031, -- flat mode (with prepared floatBoxes, so inlined, to avoid display hash mismatch)
    0x03375131, -- book mode (floating floatBoxes, limited widths support)
    0x7FFFFFFF, -- web mode, all features/flags
}

function ReaderTypeset:setBlockRenderingMode(mode)
    -- mode starts for now with 0 = legacy, so we may later be able
    -- to remove it and then start with 1 = flat
    -- (Ensure we don't crash if we added and removed some options)
    if mode + 1 > #BLOCK_RENDERING_FLAGS then
        mode = #BLOCK_RENDERING_FLAGS - 1
    end
    local flags = BLOCK_RENDERING_FLAGS[mode + 1]
    if not flags then
        return
    end
    self.block_rendering_mode = mode
    if self.ensure_saner_block_rendering_flags then -- see next function
        -- Don't enable BOX_INLINE_BLOCKS
        -- inlineBoxes have been around and allowed on older DOM_VERSION
        -- for a few weeks - let's disable it: it may break highlights
        -- made during this time, but may resurrect others made during
        -- a longer previous period of time.
        flags = bit.band(flags, bit.bnot(0x01000000))
        -- Don't enable COMPLETE_INCOMPLETE_TABLES, as they may add
        -- many boxing elements around huge amount of text, and break
        -- some past highlights made on the non-boxed elements.
        flags = bit.band(flags, bit.bnot(0x02000000))
    end
    self.ui.document:setBlockRenderingFlags(flags)
    self.ui:handleEvent(Event:new("UpdatePos"))
end

function ReaderTypeset:ensureSanerBlockRenderingFlags(mode)
    -- Called by ReaderRolling:onReadSettings() when old
    -- DOM version requested, before normalized xpointers,
    -- asking us to unset some of the flags set previously.
    self.ensure_saner_block_rendering_flags = true
    self:setBlockRenderingMode(self.block_rendering_mode)
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

function ReaderTypeset:toggleNightmodeImages(toggle)
    if toggle and (toggle == true or toggle == 1) then
        self.nightmode_images = true
        self.ui.document:setNightmodeImages(true)
    else
        self.nightmode_images = false
        self.ui.document:setNightmodeImages(false)
    end
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
end

function ReaderTypeset:makeDefaultStyleSheet(css, text, touchmenu_instance)
    UIManager:show(ConfirmBox:new{
        text = T( _("Set default style to %1?"), BD.filename(text)),
        ok_callback = function()
            G_reader_settings:saveSetting("copt_css", css)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
end

function ReaderTypeset:onSetPageHorizMargins(h_margins, when_applied_callback)
    self.unscaled_margins = { h_margins[1], self.unscaled_margins[2], h_margins[2], self.unscaled_margins[4] }
    self.ui:handleEvent(Event:new("SetPageMargins", self.unscaled_margins, when_applied_callback))
end

function ReaderTypeset:onSetPageTopMargin(t_margin, when_applied_callback)
    self.unscaled_margins = { self.unscaled_margins[1], t_margin, self.unscaled_margins[3], self.unscaled_margins[4] }
    if self.sync_t_b_page_margins then
        self.unscaled_margins[4] = t_margin
        -- Let ConfigDialog know so it can update it on screen and have it saved on quit
        self.ui.document.configurable.b_page_margin = t_margin
    end
    self.ui:handleEvent(Event:new("SetPageMargins", self.unscaled_margins, when_applied_callback))
end

function ReaderTypeset:onSetPageBottomMargin(b_margin, when_applied_callback)
    self.unscaled_margins = { self.unscaled_margins[1], self.unscaled_margins[2], self.unscaled_margins[3], b_margin }
    if self.sync_t_b_page_margins then
        self.unscaled_margins[2] = b_margin
        -- Let ConfigDialog know so it can update it on screen and have it saved on quit
        self.ui.document.configurable.t_page_margin = b_margin
    end
    self.ui:handleEvent(Event:new("SetPageMargins", self.unscaled_margins, when_applied_callback))
end

function ReaderTypeset:onSetPageTopAndBottomMargin(t_b_margins, when_applied_callback)
    local t_margin, b_margin = t_b_margins[1], t_b_margins[2]
    self.unscaled_margins = { self.unscaled_margins[1], t_margin, self.unscaled_margins[3], b_margin }
    if t_margin ~= b_margin then
        -- Set Sync T/B Margins toggle to off, as user explicitly made them differ
        self.sync_t_b_page_margins = false
        self.ui.document.configurable.sync_t_b_page_margins = 0
    end
    self.ui:handleEvent(Event:new("SetPageMargins", self.unscaled_margins, when_applied_callback))
end

function ReaderTypeset:onSyncPageTopBottomMargins(toggle, when_applied_callback)
    self.sync_t_b_page_margins = not self.sync_t_b_page_margins
    if self.sync_t_b_page_margins then
        -- Adjust current top and bottom margins if needed
        if self.unscaled_margins[2] ~= self.unscaled_margins[4] then
            -- Taking the rounded mean can change the vertical page height,
            -- and so the previous lines layout. We could have used the mean
            -- for the top, and the delta from the mean for the bottom (and
            -- have them possibly not equal), but as these are unscaled here,
            -- and later scaled, the end result could still be different.
            -- So just take the mean and make them equal.
            local mean_margin = Math.round((self.unscaled_margins[2] + self.unscaled_margins[4]) / 2)
            self.ui.document.configurable.t_page_margin = mean_margin
            self.ui.document.configurable.b_page_margin = mean_margin
            self.unscaled_margins = { self.unscaled_margins[1], mean_margin, self.unscaled_margins[3], mean_margin }
            self.ui:handleEvent(Event:new("SetPageMargins", self.unscaled_margins, when_applied_callback))
            when_applied_callback = nil
        end
    end
    if when_applied_callback then
        when_applied_callback()
    end
end

function ReaderTypeset:onSetPageMargins(margins, when_applied_callback)
    local left = Screen:scaleBySize(margins[1])
    local top = Screen:scaleBySize(margins[2])
    local right = Screen:scaleBySize(margins[3])
    local bottom
    if self.view.footer.reclaim_height then
        bottom = Screen:scaleBySize(margins[4])
    else
        bottom = Screen:scaleBySize(margins[4]) + self.view.footer:getHeight()
    end
    self.ui.document:setPageMargins(left, top, right, bottom)
    self.ui:handleEvent(Event:new("UpdatePos"))
    if when_applied_callback then
        -- Provided when hide_on_apply, and ConfigDialog temporarily hidden:
        -- show an InfoMessage with the unscaled & scaled values,
        -- and call when_applied_callback on dismiss
        UIManager:show(InfoMessage:new{
            text = T(_([[
Margins set to:

  left: %1 (%2px)
  right: %3 (%4px)
  top: %5 (%6px)
  bottom: %7 (%8px)

Tap to dismiss.]]),
            margins[1], left, margins[3], right, margins[2], top, margins[4], bottom),
            dismiss_callback = when_applied_callback,
        })
    end
end

return ReaderTypeset
