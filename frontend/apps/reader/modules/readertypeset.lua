local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local Math = require("optmath")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local optionsutil = require("ui/data/optionsutil")
local _ = require("gettext")
local C_ = _.pgettext
local Screen = require("device").screen
local T = require("ffi/util").template

local ReaderTypeset = WidgetContainer:extend{
    -- @translators This is style in the sense meant by CSS (cascading style sheets), relating to the layout and presentation of the document. See <https://en.wikipedia.org/wiki/CSS> for more information.
    css_menu_title = C_("CSS", "Style"),
    css = nil,
    unscaled_margins = nil,
}

function ReaderTypeset:init()
    self.ui.menu:registerToMainMenu(self)
end

function ReaderTypeset:onReadSettings(config)
    self.css = config:readSetting("css")
    if not self.css then
        if self.ui.document.is_fb2 then
            self.css = G_reader_settings:readSetting("copt_fb2_css")
        else
            self.css = G_reader_settings:readSetting("copt_css")
        end
    end
    if not self.css then
        self.css = self.ui.document.default_css
    end
    local tweaks_css = self.ui.styletweak:getCssText()
    self.ui.document:setStyleSheet(self.css, tweaks_css)

    -- default to enable embedded fonts
    self.ui.document:setEmbeddedFonts(self.configurable.embedded_fonts)

    -- default to enable embedded CSS
    self.ui.document:setEmbeddedStyleSheet(self.configurable.embedded_css)

    -- Block rendering mode: stay with legacy rendering for books
    -- previously opened so bookmarks and highlights stay valid.
    -- For new books, use 'web' mode below in BLOCK_RENDERING_FLAGS
    if config:has("copt_block_rendering_mode") then
        self.block_rendering_mode = config:readSetting("copt_block_rendering_mode")
    else
        if config:has("last_xpointer") and not config:has("docsettings_reset_done") then
            -- We have a last_xpointer: this book was previously opened
            self.block_rendering_mode = 0
        else
            self.block_rendering_mode = G_reader_settings:readSetting("copt_block_rendering_mode")
                                     or 3 -- default to 'web' mode
        end
        -- Let ConfigDialog know so it can update it on screen and have it saved on quit
        self.configurable.block_rendering_mode = self.block_rendering_mode
    end
    self:setBlockRenderingMode(self.block_rendering_mode)

    -- default to 96 dpi
    self.ui.document:setRenderDPI(self.configurable.render_dpi)

    -- uncomment if we want font size to follow DPI changes
    -- self.ui.document:setRenderScaleFontWithDPI(1)

    -- set page margins
    self.unscaled_margins = { self.configurable.h_page_margins[1], self.configurable.t_page_margin,
                              self.configurable.h_page_margins[2], self.configurable.b_page_margin }
    self:onSetPageMargins(self.unscaled_margins)
    self.sync_t_b_page_margins = self.configurable.sync_t_b_page_margins == 1 and true or false

    if self.ui.document.is_txt then
        -- default to no fancy detection and formatting, leave lines as is
        self.txt_preformatted = config:readSetting("txt_preformatted")
                             or G_reader_settings:readSetting("txt_preformatted")
                             or 1
    else
        -- for other formats than txt, we should keep this setting fixed
        -- or it could create multiple cache files
        self.txt_preformatted = 1
    end
    self.ui.document:setTxtPreFormatted(self.txt_preformatted)

    -- default to disable smooth scaling
    self.ui.document:setImageScaling(self.configurable.smooth_scaling == 1)

    -- default to automagic nightmode-friendly handling of images
    self.ui.document:setNightmodeImages(self.configurable.nightmode_images == 1)
end

function ReaderTypeset:onReaderReady()
    -- Initial detection of fb2 may be wrong
    local doc_format = self.ui.document:getDocumentFormat()
    local is_fb2 = doc_format:sub(1, 11) == "FictionBook"
    if self.ui.document.is_fb2 ~= is_fb2 then
        self.ui.document.is_fb2 = is_fb2
        self.ui.document.default_css = is_fb2 and "./data/fb2.css" or "./data/epub.css"
        if self.ui.document.is_new then
            local css = G_reader_settings:readSetting(is_fb2 and "copt_fb2_css" or "copt_css")
            self:setStyleSheet(css or self.ui.document.default_css)
        end
    end
end

function ReaderTypeset:onSaveSettings()
    self.ui.doc_settings:saveSetting("css", self.css)
end

function ReaderTypeset:onToggleEmbeddedStyleSheet(toggle)
    local text
    if toggle then
        self.configurable.embedded_css = 1
        text = _("Enabled embedded styles.")
    else
        self.configurable.embedded_css = 0
        text = _("Disabled embedded styles.")
    end
    self.ui.document:setEmbeddedStyleSheet(self.configurable.embedded_css)
    self.ui:handleEvent(Event:new("UpdatePos"))
    Notification:notify(text)
    return true
end

function ReaderTypeset:onToggleEmbeddedFonts(toggle)
    local text
    if toggle then
        self.configurable.embedded_fonts = 1
        text = _("Enabled embedded fonts.")
    else
        self.configurable.embedded_fonts = 0
        text = _("Disabled embedded fonts.")
    end
    self.ui.document:setEmbeddedFonts(self.configurable.embedded_fonts)
    self.ui:handleEvent(Event:new("UpdatePos"))
    Notification:notify(text)
    return true
end

function ReaderTypeset:onToggleImageScaling(toggle)
    self.configurable.smooth_scaling = toggle and 1 or 0
    self.ui.document:setImageScaling(toggle)
    self.ui:handleEvent(Event:new("UpdatePos"))
    local text = T(_("Image scaling set to: %1"), optionsutil:getOptionText("ToggleImageScaling", toggle))
    Notification:notify(text)
    return true
end

function ReaderTypeset:onToggleNightmodeImages(toggle)
    self.configurable.nightmode_images = toggle and 1 or 0
    self.ui.document:setNightmodeImages(toggle)
    self.ui:handleEvent(Event:new("UpdatePos"))
    return true
end

function ReaderTypeset:onSetBlockRenderingMode(mode)
    self:setBlockRenderingMode(mode)
    local text = T(_("Render mode set to: %1"), optionsutil:getOptionText("SetBlockRenderingMode", mode))
    Notification:notify(text)
    return true
end

function ReaderTypeset:onSetRenderDPI(dpi)
    self.configurable.render_dpi = dpi
    self.ui.document:setRenderDPI(dpi)
    self.ui:handleEvent(Event:new("UpdatePos"))
    local text = T(_("Zoom set to: %1"), optionsutil:getOptionText("SetRenderDPI", dpi))
    Notification:notify(text)
    return true
end

-- June 2018: epub.css has been cleaned to be more conforming to HTML specs
-- and to not include class name based styles (with conditional compatibility
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

function ReaderTypeset:genStyleSheetMenu()
    local getStyleMenuItem = function(text, css_file, description, fb2_compatible, separator)
        return {
            text_func = function()
                local css_opt = self.ui.document.is_fb2 and "copt_fb2_css" or "copt_css"
                return text .. (css_file == G_reader_settings:readSetting(css_opt) and "   ★" or "")
            end,
            callback = function()
                self:setStyleSheet(css_file or self.ui.document.default_css)
            end,
            hold_callback = function(touchmenu_instance)
                self:makeDefaultStyleSheet(css_file, text, description, touchmenu_instance)
            end,
            checked_func = function()
                if not css_file then -- "Auto"
                    return self.css == self.ui.document.default_css
                end
                return css_file == self.css
            end,
            enabled_func = function()
                if fb2_compatible == true and not (self.ui.document.is_fb2 or self.ui.document.is_txt) then
                    return false
                end
                if fb2_compatible == false and self.ui.document.is_fb2 then
                    return false
                end
                -- if fb2_compatible==nil, we don't know (user css file)
                return true
            end,
            separator = separator,
        }
    end

    local style_table = {}
    local obsoleted_table = {}

    table.insert(style_table, getStyleMenuItem(
        _("None"),
        "",
        _("This sets an empty User-Agent stylesheet, and expects the document stylesheet to style everything (which publishers probably don't).\nThis is mostly only interesting for testing.")
    ))
    table.insert(style_table, getStyleMenuItem(
        _("Auto"),
        nil,
        _("This selects the default and preferred stylesheet for the document type."),
        nil,
        true -- separator
    ))

    local css_files = {}
    for f in lfs.dir("./data") do
        if lfs.attributes("./data/"..f, "mode") == "file" and string.match(f, "%.css$") then
            css_files[f] = "./data/"..f
        end
    end
    -- Add the 3 main styles
    if css_files["epub.css"] then
        table.insert(style_table, getStyleMenuItem(
            _("Traditional book look (epub.css)"),
            css_files["epub.css"],
            _([[
This is our book look-alike stylesheet: it extends the HTML standard stylesheet with styles aimed at making HTML content look more like a paper book (with justified text and indentation on paragraphs) than like a web page.
It is perfect for unstyled books, and might make styled books more readable.
It may cause some small issues on some books (miscentered titles, headings or separators, or unexpected text indentation), as publishers don't expect to have our added styles at play and need to reset them; try switching to html5.css when you notice such issues.]]),
            false -- not fb2_compatible
        ))
        css_files["epub.css"] = nil
    end
    if css_files["html5.css"] then
        table.insert(style_table, getStyleMenuItem(
            _("HTML Standard rendering (html5.css)"),
            css_files["html5.css"],
            _([[
This stylesheet conforms to the HTML Standard rendering suggestions (with a few limitations), similar to what most web browsers use.
As most publishers nowadays make and test their book with tools based on web browser engines, it is the stylesheet to use to see a book as these publishers intended.
On unstyled books though, it may give them the look of a web page (left aligned paragraphs without indentation and with spacing between them); try switching to epub.css when that happens.]]),
            false -- not fb2_compatible
        ))
        css_files["html5.css"] = nil
    end
    if css_files["fb2.css"] then
        table.insert(style_table, getStyleMenuItem(
            _("FictionBook (fb2.css)"),
            css_files["fb2.css"],
            _([[
This stylesheet is to be used only with FB2 and FB3 documents, which are not classic HTML, and need some specific styling.
(FictionBook 2 & 3 are open XML-based e-book formats which originated and gained popularity in Russia.)]]),
            true, -- fb2_compatible
            true -- separator
        ))
        css_files["fb2.css"] = nil
    end
    -- Add the obsoleted ones to the Obsolete sub menu
    local obsoleted_css = {} -- for check_func of the Obsolete sub menu itself
    for __, css in ipairs(OBSOLETED_CSS) do
        obsoleted_css[css_files[css]] = css
        if css_files[css] then
            table.insert(obsoleted_table, getStyleMenuItem(css, css_files[css], _("This stylesheet is obsolete: don't use it. It is kept solely to be able to open documents last read years ago and to migrate their highlights.")))
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
        table.insert(style_table, getStyleMenuItem(css, css_files[css], _("This is a user added stylesheet.")))
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
        checked_func = function()
            return obsoleted_css[self.css] ~= nil
        end,
        sub_item_table = obsoleted_table,
        separator = true,
    })
    if self.ui.document.is_txt then
        table.insert(style_table, {
            text_func = function()
                return _("Auto-detect TXT files layout") .. (G_reader_settings:has("txt_preformatted") and "   ★" or "")
            end,
            checked_func = function()
                return self.txt_preformatted == 0
            end,
            callback = function()
                self.txt_preformatted = self.txt_preformatted == 1 and 0 or 1
                self.ui.doc_settings:saveSetting("txt_preformatted", self.txt_preformatted)
                -- Calling document:setTxtPreFormatted() here could cause a segfault (there is something
                -- really fishy about its handling, like bits of partial rerenderings happening while it is
                -- disabled...). It's safer to just not notify crengine, and propose the user to reload the
                -- document and restart from a sane state.
                self.ui.rolling:showSuggestReloadConfirmBox()
            end,
            hold_callback = function(touchmenu_instance)
                if G_reader_settings:has("txt_preformatted") then
                    G_reader_settings:delSetting("txt_preformatted")
                else
                    G_reader_settings:saveSetting("txt_preformatted", 0)
                end
                touchmenu_instance:updateItems()
            end,
        })
    end
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

-- Not used
function ReaderTypeset:setEmbededStyleSheetOnly()
    if self.css ~= nil then
        -- clear applied css
        self.ui.document:setStyleSheet("")
        self.ui.document:setEmbeddedStyleSheet(1)
        self.css = nil
        self.ui:handleEvent(Event:new("UpdatePos"))
    end
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

function ReaderTypeset:addToMainMenu(menu_items)
    -- insert table to main reader menu
    menu_items.set_render_style = {
        text = self.css_menu_title,
        sub_item_table = self:genStyleSheetMenu(),
    }
end

function ReaderTypeset:makeDefaultStyleSheet(css, name, description, touchmenu_instance)
    local text = self.ui.document.is_fb2 and T(_("Set default style for FB2 documents to %1?"), BD.filename(name))
                                          or T(_("Set default style to %1?"), BD.filename(name))
    if description then
        text = text .. "\n\n" .. description
    end
    UIManager:show(ConfirmBox:new{
        text = text,
        ok_callback = function()
            if self.ui.document.is_fb2 then
                G_reader_settings:saveSetting("copt_fb2_css", css)
            else
                G_reader_settings:saveSetting("copt_css", css)
            end
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
        self.configurable.b_page_margin = t_margin
    end
    self.ui:handleEvent(Event:new("SetPageMargins", self.unscaled_margins, when_applied_callback))
end

function ReaderTypeset:onSetPageBottomMargin(b_margin, when_applied_callback)
    self.unscaled_margins = { self.unscaled_margins[1], self.unscaled_margins[2], self.unscaled_margins[3], b_margin }
    if self.sync_t_b_page_margins then
        self.unscaled_margins[2] = b_margin
        -- Let ConfigDialog know so it can update it on screen and have it saved on quit
        self.configurable.t_page_margin = b_margin
    end
    self.ui:handleEvent(Event:new("SetPageMargins", self.unscaled_margins, when_applied_callback))
end

function ReaderTypeset:onSetPageTopAndBottomMargin(t_b_margins, when_applied_callback)
    local t_margin, b_margin = t_b_margins[1], t_b_margins[2]
    self.unscaled_margins = { self.unscaled_margins[1], t_margin, self.unscaled_margins[3], b_margin }
    if t_margin ~= b_margin then
        -- Set Sync T/B Margins toggle to off, as user explicitly made them differ
        self.sync_t_b_page_margins = false
        self.configurable.sync_t_b_page_margins = 0
    end
    self.ui:handleEvent(Event:new("SetPageMargins", self.unscaled_margins, when_applied_callback))
end

function ReaderTypeset:onSyncPageTopBottomMargins(toggle, when_applied_callback)
    if toggle == nil then
        self.sync_t_b_page_margins = not self.sync_t_b_page_margins
    else
        self.sync_t_b_page_margins = toggle
    end
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
            self.configurable.t_page_margin = mean_margin
            self.configurable.b_page_margin = mean_margin
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

  left: %1
  right: %2
  top: %3
  bottom: %4

  footer: %5 px

Tap to dismiss.]]),
            optionsutil.formatFlexSize(margins[1]),
            optionsutil.formatFlexSize(margins[3]),
            optionsutil.formatFlexSize(margins[2]),
            optionsutil.formatFlexSize(margins[4]),
            self.view.footer.reclaim_height and 0 or self.view.footer:getHeight()),
            dismiss_callback = when_applied_callback,
        })
    end
end

return ReaderTypeset
