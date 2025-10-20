local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local OverlapGroup = require("ui/widget/overlapgroup")
local SpinWidget = require("ui/widget/spinwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local N_ = _.ngettext
local Screen = Device.screen
local T = require("ffi/util").template

local ReaderPageMap = WidgetContainer:extend{
    label_font_face = "ffont",
    label_default_font_size = 14,
    -- Black so it's readable (and non-gray-flashing on GloHD)
    label_color = Blitbuffer.COLOR_BLACK,
    show_page_labels = nil,
    use_page_labels = nil,
    page_labels_cache = nil, -- hash table
    chars_per_synthetic_page_default = 1500, -- see https://github.com/koreader/koreader/issues/9020#issuecomment-2046025613
    chars_per_synthetic_page = nil, -- not nil means the synthetic pagemap has been created
}

function ReaderPageMap:init()
    self.has_pagemap = false
    self.container = nil
    self.max_left_label_width = 0
    self.max_right_label_width = 0
    self.label_font_size = G_reader_settings:readSetting("pagemap_label_font_size")
                                or self.label_default_font_size
    self.use_textbox_widget = nil
    self.initialized = false
    self.ui:registerPostInitCallback(function()
        self:_postInit()
    end)
    self.ui.menu:registerToMainMenu(self)
end

function ReaderPageMap:_postInit()
    self.initialized = true
    self.has_pagemap_document_provided = self.ui.document:hasPageMapDocumentProvided()
    -- chars_per_synthetic_page is saved to cr3 cache by crengine on first building of synthetic pagemap.
    -- It's possible that the crengine doc cache is inconsistent with our setting
    -- (cache from a past opening, settings sync'ed from another device).
    -- Make sure we're consistent, honoring the cre cache values to avoid a document reload.
    local chars_per_synthetic_page = self.ui.document:getSyntheticPageMapCharsPerPage()
    if chars_per_synthetic_page > 0 then
        self.chars_per_synthetic_page = chars_per_synthetic_page
        self.ui.doc_settings:saveSetting("pagemap_chars_per_synthetic_page", chars_per_synthetic_page)
    else
        if self.ui.document.is_new then
            chars_per_synthetic_page = G_reader_settings:readSetting("pagemap_chars_per_synthetic_page")
            if chars_per_synthetic_page and
                    (not self.has_pagemap_document_provided
                      or G_reader_settings:isTrue("pagemap_synthetic_overrides")) then
                self.chars_per_synthetic_page = chars_per_synthetic_page
                self.ui.doc_settings:saveSetting("pagemap_chars_per_synthetic_page", chars_per_synthetic_page)
                self.ui.document:buildSyntheticPageMap(chars_per_synthetic_page)
            end
        else
            chars_per_synthetic_page = self.ui.doc_settings:readSetting("pagemap_chars_per_synthetic_page")
            if chars_per_synthetic_page then
                self.chars_per_synthetic_page = chars_per_synthetic_page
                self.ui.document:buildSyntheticPageMap(chars_per_synthetic_page)
            end
        end
    end
    if self.ui.document:hasPageMap() then
        self.has_pagemap = true
        self:resetLayout()
        self.view:registerViewModule("pagemap", self)
        if self.ui.document.is_new and self.has_pagemap_document_provided
                and G_reader_settings:isTrue("pagemap_notify_document_provided") then
            if self.use_page_labels or self.show_page_labels then
                self:showDocumentProvidedInfo()
            else
                UIManager:show(ConfirmBox:new{
                    text = self:showDocumentProvidedInfo(true) .. "\n\n" .. _("Do you want to use them?"),
                    ok_callback = function()
                        if not self.use_page_labels then
                            self.page_labels_cache = nil
                            self.use_page_labels = true
                            self.ui.doc_settings:saveSetting("pagemap_use_page_labels", true)
                            UIManager:broadcastEvent(Event:new("UsePageLabelsUpdated"))
                        end
                        if not self.show_page_labels then
                            self.show_page_labels = true
                            self.ui.doc_settings:saveSetting("pagemap_show_page_labels", true)
                            self:resetLayout()
                            self:updateVisibleLabels()
                        end
                        UIManager:setDirty(self.view.dialog, "partial")
                    end,
                })
            end
        end
    end
end

function ReaderPageMap:resetLayout()
    if not self.initialized then
        return
    end
    if self[1] then
        self[1]:free()
        self[1] = nil
    end
    if not self.show_page_labels then
        return
    end
    self.container = OverlapGroup:new{
        dimen = Screen:getSize(),
        -- Pages in 2-page mode are not mirrored, so we'll
        -- have to handle any mirroring tweak ourselves
        allow_mirroring = false,
    }
    self[1] = self.container

    -- Get some metric for label min width
    self.label_face = Font:getFace(self.label_font_face, self.label_font_size)
    local textw = TextWidget:new{
        text = " ",
        face = self.label_face,
    }
    self.space_width = textw:getWidth()
    textw:setText("8")
    self.number_width = textw:getWidth()
    textw:free()
    self.min_label_width = self.space_width * 2 + self.number_width
end

function ReaderPageMap:onReadSettings(config)
    local h_margins = self.ui.document.configurable.h_page_margins
    self.max_left_label_width = Screen:scaleBySize(h_margins[1])
    self.max_right_label_width = Screen:scaleBySize(h_margins[2])

    if config:has("pagemap_show_page_labels") then
        self.show_page_labels = config:isTrue("pagemap_show_page_labels")
    else
        self.show_page_labels = G_reader_settings:isTrue("pagemap_show_page_labels")
    end
    if config:has("pagemap_use_page_labels") then
        self.use_page_labels = config:isTrue("pagemap_use_page_labels")
    else
        self.use_page_labels = G_reader_settings:isTrue("pagemap_use_page_labels")
    end
end

function ReaderPageMap:onSetPageMargins(margins)
    if not self.has_pagemap then
        return
    end
    self.max_left_label_width = Screen:scaleBySize(margins[1])
    self.max_right_label_width = Screen:scaleBySize(margins[3])
    self:resetLayout()
end

function ReaderPageMap:cleanPageLabel(label)
    -- Cleanup page label, that may contain some noise (as they
    -- were meant to be shown in a list, like a TOC)
    label = label:gsub("[Pp][Aa][Gg][Ee]%s*", "") -- remove leading "Page " from "Page 123"
    return label
end

function ReaderPageMap:updateVisibleLabels()
    -- This might be triggered before PostInitCallback is
    if not self.initialized then
        return
    end
    if not self.has_pagemap then
        return
    end
    if not self.show_page_labels then
        return
    end
    self.container:clear()
    local page_labels = self.ui.document:getPageMapVisiblePageLabels()
    local footer_height = ((self.view.footer_visible and not self.view.footer.settings.reclaim_height) and 1 or 0) * self.view.footer:getHeight()
    local max_y = Screen:getHeight() - footer_height
    local last_label_bottom_y = 0
    local on_second_page = false
    for _, page in ipairs(page_labels) do
        local in_left_margin = BD.mirroredUILayout()
        if self.ui.document:getVisiblePageCount() > 1 then
            -- Pages in 2-page mode are not mirrored, so we'll
            -- have to handle any mirroring tweak ourselves
            in_left_margin = page.screen_page == 1
            if not on_second_page and page.screen_page == 2 then
                on_second_page = true
                last_label_bottom_y = 0 -- reset this
            end
        end
        local max_label_width = in_left_margin and self.max_left_label_width or self.max_right_label_width
        if max_label_width < self.min_label_width then
            max_label_width = self.min_label_width
        end
        local label_width = max_label_width - 2 * self.space_width -- one space to screen edge, one to content
        local text = self:cleanPageLabel(page.label)
        local label_widget = TextBoxWidget:new{
            text = text,
            width = label_width,
            face = self.label_face,
            line_height = 0, -- no additional line height
            fgcolor = self.label_color,
            alignment = not in_left_margin and "right",
            alignment_strict = true,
        }
        local label_height = label_widget:getTextHeight()
        local frame = FrameContainer:new{
            bordersize = 0,
            padding = 0,
            padding_left = in_left_margin and self.space_width,
            padding_right = not in_left_margin and self.space_width,
            label_widget,
            allow_mirroring = false,
        }
        local offset_x = in_left_margin and 0 or Screen:getWidth() - frame:getSize().w
        local offset_y = page.screen_y
        if offset_y < last_label_bottom_y then
            -- Avoid consecutive labels to overwrite themselbes
            offset_y = last_label_bottom_y
        end
        if offset_y + label_height > max_y then
            -- Push label up so it's fully above footer
            offset_y = max_y - label_height
        end
        last_label_bottom_y = offset_y + label_height
        frame.overlap_offset = {offset_x, offset_y}
        table.insert(self.container, frame)
    end
end

-- Events that may change page draw offset, and might need visible labels
-- to be updated to get their correct screen y
ReaderPageMap.onPageUpdate = ReaderPageMap.updateVisibleLabels
ReaderPageMap.onPosUpdate = ReaderPageMap.updateVisibleLabels
ReaderPageMap.onChangeViewMode = ReaderPageMap.updateVisibleLabels
ReaderPageMap.onSetStatusLine = ReaderPageMap.updateVisibleLabels

function ReaderPageMap:onShowPageList()
    -- build up item_table
    local cur_page = self.ui.document:getCurrentPage()
    local cur_page_idx = 0
    local page_list = self.ui.document:getPageMap()
    for k, v in ipairs(page_list) do
        v.text = v.label
        v.mandatory = v.page
        if v.page <= cur_page then
            cur_page_idx = k
        end
    end
    if cur_page_idx > 0 then
        -- Have Menu jump to the current page and show it in bold
        page_list.current = cur_page_idx
    end

    -- We use the per-page and font-size settings set for the ToC
    local items_per_page = G_reader_settings:readSetting("toc_items_per_page") or 14
    local items_font_size = G_reader_settings:readSetting("toc_items_font_size") or Menu.getItemFontSize(items_per_page)
    local items_with_dots = G_reader_settings:nilOrTrue("toc_items_with_dots")

    local pl_menu = Menu:new{
        title = _("Stable page number list"),
        item_table = page_list,
        is_borderless = true,
        is_popout = false,
        items_per_page = items_per_page,
        items_font_size = items_font_size,
        line_color = require("ffi/blitbuffer").COLOR_WHITE,
        single_line = true,
        align_baselines = true,
        with_dots = items_with_dots,
        on_close_ges = {
            GestureRange:new{
                ges = "two_finger_swipe",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                },
                direction = BD.flipDirectionIfMirroredUILayout("east")
            }
        }
    }

    self.pagelist_menu = CenterContainer:new{
        dimen = Screen:getSize(),
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        pl_menu,
    }

    -- build up menu widget method as closure
    local pagemap = self
    function pl_menu:onMenuChoice(item)
        pagemap.ui.link:addCurrentLocationToStack()
        pagemap.ui.rolling:onGotoXPointer(item.xpointer)
    end

    pl_menu.close_callback = function()
        UIManager:close(self.pagelist_menu)
    end

    pl_menu.show_parent = self.pagelist_menu
    self.refresh = function()
        pl_menu:updateItems()
    end

    UIManager:show(self.pagelist_menu)
    return true
end

function ReaderPageMap:wantsPageLabels()
    return self.has_pagemap and self.use_page_labels
end

function ReaderPageMap:getCurrentPageLabel(clean_label)
    -- Note: in scroll mode with PDF, when multiple pages are shown on
    -- the screen, the advertised page number is the greatest page number
    -- among the pages shown (so, the page number of the partial page
    -- shown at bottom of screen).
    -- For consistency, getPageMapCurrentPageLabel() returns the last page
    -- label shown in the view if there are more than one (or the previous
    -- one if there is none).
    local label, idx, count = self.ui.document:getPageMapCurrentPageLabel()
    if clean_label then
        label = self:cleanPageLabel(label)
    end
    return label, idx, count
end

function ReaderPageMap:getFirstPageLabel(clean_label)
    local label = self.ui.document:getPageMapFirstPageLabel()
    return clean_label and self:cleanPageLabel(label) or label
end

function ReaderPageMap:getLastPageLabel(clean_label)
    local label = self.ui.document:getPageMapLastPageLabel()
    return clean_label and self:cleanPageLabel(label) or label
end

function ReaderPageMap:getXPointerPageLabel(xp, clean_label)
    local label = self.ui.document:getPageMapXPointerPageLabel(xp)
    return clean_label and self:cleanPageLabel(label) or label
end

function ReaderPageMap:getPageLabelProps(page_label)
    if self.page_labels_cache == nil then -- fill the cache
        local page_list = self.ui.document:getPageMap()
        self.page_labels_cache = { #page_list }
        for i, v in ipairs(page_list) do
            local label = self:cleanPageLabel(v.label)
            self.page_labels_cache[label] = { i, v.page }
        end
    end
    -- expects cleaned page_label
    if page_label then
        local props = self.page_labels_cache[page_label]
        if props then
            return props[1], props[2] -- index, rendered page
        end
    else
        return self.page_labels_cache[1] -- total number of labels
    end
end

function ReaderPageMap:onDocumentRerendered()
    self.page_labels_cache = nil
end

function ReaderPageMap:showDocumentProvidedInfo(get_text)
    local t = _([[
Publisher page numbers available.
Page numbers: %1 - %2
Source (print edition):
%3]])
    local source = self.ui.document:getPageMapSource()
    if source == nil or source == "" then
        source = _("N/A")
    end
    local text = T(t, self:getFirstPageLabel(true), self:getLastPageLabel(true), source)
    if get_text then
        return text
    end
    UIManager:show(InfoMessage:new{ text = text })
end

function ReaderPageMap:addToMainMenu(menu_items)
    menu_items.page_map = {
        -- @translators This and the other related ones refer to alternate page numbers provided in some EPUB books, that usually reference page numbers in a specific hardcopy edition of the book.
        text_func = function()
            local title = _("Stable page numbers")
            if self.has_pagemap then
                local text
                if self.chars_per_synthetic_page then
                    -- @translators characters per page
                    text = T(N_("1 char per page", "%1 chars per page", self.chars_per_synthetic_page), self.chars_per_synthetic_page)
                    if self.has_pagemap_document_provided then
                        text = "℗ / " .. text
                    end
                else
                    text = "℗"
                end
                title = title .. ": " .. text
            end
            return title
        end,
        checked_func = function()
            return self.has_pagemap and self.use_page_labels
        end,
        sub_item_table = {
            {
                text = _("About stable page numbers"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = _([[
By default, one screen equals one page. Any change in the book's formatting will therefore result in renumbering: new total pages, different chapter lengths, new locations in TOC and bookmarks, etc.

Select stable page numbers if you prefer page numbers that are independent of layout settings and consistent across devices:
1. Publisher page numbers (℗): normally equivalent to a specific physical edition. Only available if supplied by the publisher.
2. Characters per page: a page will be counted for this amount of characters (sometimes called logical or synthetic page numbers). Use this if no publisher page numbers are available or if you prefer to have consistent page lengths for all books.

Since stable page numbers can start anywhere on the screen, you can choose to display them in the margin, regardless of other settings.

'Stable page number list' shows a table of all stable page numbers and their corresponding screen page numbers.]]),
                        width = Screen:getWidth() * 0.8,
                    })
                end,
                separator = true,
            },
            {
                text_func = function()
                    return T(_("Characters per page: %1"), self.chars_per_synthetic_page or _("disabled"))
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    UIManager:show(SpinWidget:new{
                        title_text = _("Characters per page"),
                        value = self.chars_per_synthetic_page or self.chars_per_synthetic_page_default,
                        value_min = 500,
                        value_max = 3000,
                        value_hold_step = 20,
                        default_value = self.chars_per_synthetic_page_default,
                        ok_always_enabled = true,
                        keep_shown_on_apply = true,
                        callback = function(spin)
                            spin:onClose()
                            if not self.has_pagemap then
                                self.has_pagemap = true
                                self:resetLayout()
                                self.view:registerViewModule("pagemap", self)
                            end
                            self.chars_per_synthetic_page = spin.value
                            self.ui.doc_settings:saveSetting("pagemap_chars_per_synthetic_page", spin.value)
                            self.page_labels_cache = nil
                            self.ui.document:buildSyntheticPageMap(spin.value)
                            self:updateVisibleLabels()
                            UIManager:setDirty(self.view.dialog, "partial")
                            UIManager:broadcastEvent(Event:new("UsePageLabelsUpdated"))
                            touchmenu_instance:updateItems()
                        end,
                        extra_text = self.has_pagemap_document_provided and self.chars_per_synthetic_page
                            and _("Use publisher page numbers"),
                        extra_callback = function(spin)
                            UIManager:show(ConfirmBox:new{
                                text = _("Use publisher page numbers?\nThe document will be reloaded."),
                                ok_callback = function()
                                    spin:onClose()
                                    self.ui.doc_settings:delSetting("pagemap_chars_per_synthetic_page")
                                    self.ui.document:invalidateCacheFile()
                                    local after_open_callback = function(ui)
                                        ui.annotation:setNeedsUpdateFlag()
                                    end
                                    self.ui:reloadDocument(nil, nil, after_open_callback)
                                end,
                            })
                        end,
                    })
                end,
            },
            {
                text = _("Use stable page numbers"),
                enabled_func = function()
                    return self.has_pagemap
                end,
                checked_func = function()
                    return self.has_pagemap and self.use_page_labels
                end,
                callback = function()
                    self.page_labels_cache = nil
                    self.use_page_labels = not self.use_page_labels
                    self.ui.doc_settings:saveSetting("pagemap_use_page_labels", self.use_page_labels)
                    UIManager:broadcastEvent(Event:new("UsePageLabelsUpdated"))
                    UIManager:setDirty(self.view.dialog, "partial")
                end,
            },
            {
                text = _("Show stable page numbers in margin"),
                enabled_func = function()
                    return self.has_pagemap
                end,
                checked_func = function()
                    return self.has_pagemap and self.show_page_labels
                end,
                callback = function()
                    self.show_page_labels = not self.show_page_labels
                    self.ui.doc_settings:saveSetting("pagemap_show_page_labels", self.show_page_labels)
                    self:resetLayout()
                    self:updateVisibleLabels()
                    UIManager:setDirty(self.view.dialog, "partial")
                end,
                separator = true,
            },
            {
                text = _("Stable page number list"),
                enabled_func = function()
                    return self.has_pagemap
                end,
                callback = function()
                    self:onShowPageList()
                end,
            },
            {
                -- @translators This shows the <dc:source> in the EPUB that usually tells which hardcopy edition the reference page numbers refers to.
                text = _("Publisher page numbers source info"),
                enabled_func = function()
                    return self.has_pagemap and self.ui.document:getPageMapSource() and true or false
                end,
                keep_menu_open = true,
                callback = function()
                    self:showDocumentProvidedInfo()
                end,
                separator = true,
            },
            {
                text = _("Default settings for new books"),
                sub_item_table = {
                    {
                        text_func = function()
                            local chars_per_page = G_reader_settings:readSetting("pagemap_chars_per_synthetic_page")
                            return T(_("Characters per page: %1"), chars_per_page or _("disabled"))
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            UIManager:show(SpinWidget:new{
                                title_text = _("Characters per page"),
                                value = G_reader_settings:readSetting("pagemap_chars_per_synthetic_page")
                                    or self.chars_per_synthetic_page_default,
                                value_min = 500,
                                value_max = 3000,
                                value_hold_step = 20,
                                default_value = self.chars_per_synthetic_page_default,
                                ok_always_enabled = true,
                                callback = function(spin)
                                    G_reader_settings:saveSetting("pagemap_chars_per_synthetic_page", spin.value)
                                    touchmenu_instance:updateItems()
                                end,
                                extra_text = _("Disable"),
                                extra_callback = function()
                                    G_reader_settings:delSetting("pagemap_chars_per_synthetic_page")
                                    touchmenu_instance:updateItems()
                                end,
                            })
                        end,
                    },
                    {
                        text = _("Override publisher page numbers"),
                        enabled_func = function()
                            return G_reader_settings:readSetting("pagemap_chars_per_synthetic_page") and true or false
                        end,
                        checked_func = function()
                            return G_reader_settings:readSetting("pagemap_chars_per_synthetic_page")
                                and G_reader_settings:isTrue("pagemap_synthetic_overrides")
                        end,
                        callback = function()
                            G_reader_settings:toggle("pagemap_synthetic_overrides")
                        end,
                    },
                    {
                        text = _("Prompt when publisher page numbers available"),
                        checked_func = function()
                            return G_reader_settings:isTrue("pagemap_notify_document_provided")
                        end,
                        callback = function()
                            G_reader_settings:toggle("pagemap_notify_document_provided")
                        end,
                        separator = true,
                    },
                    {
                        text = _("Use stable page numbers"),
                        checked_func = function()
                            return G_reader_settings:isTrue("pagemap_use_page_labels")
                        end,
                        callback = function()
                            G_reader_settings:toggle("pagemap_use_page_labels")
                        end,
                    },
                    {
                        text = _("Show stable page numbers in margin"),
                        checked_func = function()
                            return G_reader_settings:isTrue("pagemap_show_page_labels")
                        end,
                        callback = function()
                            G_reader_settings:toggle("pagemap_show_page_labels")
                        end,
                    },
                    {
                        text_func = function()
                            return T(_("Page numbers font size: %1"), self.label_font_size)
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            UIManager:show(SpinWidget:new{
                                title_text = _("Page numbers font size"),
                                value = self.label_font_size,
                                value_min = 8,
                                value_max = 20,
                                default_value = self.label_default_font_size,
                                keep_shown_on_apply = true,
                                callback = function(spin)
                                    self.label_font_size = spin.value
                                    G_reader_settings:saveSetting("pagemap_label_font_size", self.label_font_size)
                                    touchmenu_instance:updateItems()
                                    self:resetLayout()
                                    self:updateVisibleLabels()
                                    UIManager:setDirty(self.view.dialog, "partial")
                                end,
                            })
                        end,
                    },
                },
            },
        },
    }
end

return ReaderPageMap
