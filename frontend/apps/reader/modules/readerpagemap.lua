local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Menu = require("ui/widget/menu")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")

local ReaderPageMap = InputContainer:new{
    label_font_face = "ffont",
    label_default_font_size = 14,
    -- Black so it's readable (and non-gray-flashing on GloHD)
    label_color = Blitbuffer.COLOR_BLACK,
    show_page_labels = nil,
    use_page_labels = nil,
    _mirroredUI = BD.mirroredUILayout(),
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
end

function ReaderPageMap:_postInit()
    self.initialized = true
    if self.ui.document.info.has_pages then
        return
    end
    if not self.ui.document:hasPageMap() then
        return
    end
    self.has_pagemap = true
    self:resetLayout()
    self.ui.menu:registerToMainMenu(self)
    self.view:registerViewModule("pagemap", self)
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
    local h_margins = config:readSetting("copt_h_page_margins")
                   or G_reader_settings:readSetting("copt_h_page_margins")
                   or DCREREADER_CONFIG_H_MARGIN_SIZES_MEDIUM
    self.max_left_label_width = Screen:scaleBySize(h_margins[1])
    self.max_right_label_width = Screen:scaleBySize(h_margins[2])

    if config:has("pagemap_show_page_labels") then
        self.show_page_labels = config:isTrue("pagemap_show_page_labels")
    else
        self.show_page_labels = G_reader_settings:nilOrTrue("pagemap_show_page_labels")
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
    for _, page in ipairs(page_labels) do
        local in_left_margin = self._mirroredUI
        if self.ui.document:getVisiblePageCount() > 1 then
            -- Pages in 2-page mode are not mirrored, so we'll
            -- have to handle any mirroring tweak ourselves
            in_left_margin = page.screen_page == 1
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
        title = _("Reference page numbers list"),
        item_table = page_list,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        cface = Font:getFace("x_smallinfofont"),
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

    -- buid up menu widget method as closure
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
    -- the screen, the advertized page number is the greatest page number
    -- among the pages shown (so, the page number of the partial page
    -- shown at bottom of screen).
    -- For consistency, getPageMapCurrentPageLabel() returns the last page
    -- label shown in the view if there are more than one (or the previous
    -- one if there is none).
    local label = self.ui.document:getPageMapCurrentPageLabel()
    return clean_label and self:cleanPageLabel(label) or label
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

function ReaderPageMap:getRenderedPageNumber(page_label, cleaned)
    -- Only used from ReaderGoTo. As page_label is a string, no
    -- way to use a binary search: do a full scan of the PageMap
    -- here in Lua, even if it's not cheap.
    local page_list = self.ui.document:getPageMap()
    for k, v in ipairs(page_list) do
        local label = cleaned and self:cleanPageLabel(v.label) or v.label
        if label == page_label then
            return v.page
        end
    end
end

function ReaderPageMap:addToMainMenu(menu_items)
    menu_items.page_map = {
        -- @translators This and the other related ones refer to alternate page numbers provided in some EPUB books, that usually reference page numbers in a specific hardcopy edition of the book.
        text = _("Reference pages"),
        sub_item_table ={
            {
                -- @translators This shows the <dc:source> in the EPUB that usually tells which hardcopy edition the reference page numbers refers to.
                text = _("Reference source info"),
                enabled_func = function() return self.ui.document:getPageMapSource() ~= nil end,
                callback = function()
                    local text = T(_("Source (book hardcopy edition) of reference page numbers:\n\n%1"),
                                    self.ui.document:getPageMapSource())
                    local InfoMessage = require("ui/widget/infomessage")
                    local infomsg = InfoMessage:new{
                        text = text,
                    }
                    UIManager:show(infomsg)
                end,
                keep_menu_open = true,
            },
            {
                text = _("Reference page numbers list"),
                callback = function()
                    self:onShowPageList()
                end,
            },
            {
                text = _("Use reference page numbers"),
                checked_func = function() return self.use_page_labels end,
                callback = function()
                    self.use_page_labels = not self.use_page_labels
                    self.ui.doc_settings:saveSetting("pagemap_use_page_labels", self.use_page_labels)
                    -- Reset a few stuff that may use page labels
                    self.ui.toc:resetToc()
                    self.ui.view.footer:onUpdateFooter()
                    UIManager:setDirty(self.view.dialog, "partial")
                end,
                hold_callback = function(touchmenu_instance)
                    local use_page_labels = G_reader_settings:isTrue("pagemap_use_page_labels")
                    UIManager:show(MultiConfirmBox:new{
                        text = use_page_labels and _("The default (★) for newly opened books that have a reference page numbers map is to use these reference page numbers instead of the renderer page numbers.\n\nWould you like to change it?")
                        or _("The default (★) for newly opened books that have a reference page numbers map is to not use these reference page numbers and keep using the renderer page numbers.\n\nWould you like to change it?"),
                        choice1_text_func = function()
                            return use_page_labels and _("Renderer") or _("Renderer (★)")
                        end,
                        choice1_callback = function()
                             G_reader_settings:makeFalse("pagemap_use_page_labels")
                             if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                        choice2_text_func = function()
                            return use_page_labels and _("Reference (★)") or _("Reference")
                        end,
                        choice2_callback = function()
                            G_reader_settings:makeTrue("pagemap_use_page_labels")
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    })
                end,
                separator = true,
            },
            {
                text = _("Show reference page labels in margin"),
                checked_func = function() return self.show_page_labels end,
                callback = function()
                    self.show_page_labels = not self.show_page_labels
                    self.ui.doc_settings:saveSetting("pagemap_show_page_labels", self.show_page_labels)
                    self:resetLayout()
                    self:updateVisibleLabels()
                    UIManager:setDirty(self.view.dialog, "partial")
                end,
                hold_callback = function(touchmenu_instance)
                    local show_page_labels = G_reader_settings:nilOrTrue("pagemap_show_page_labels")
                    UIManager:show(MultiConfirmBox:new{
                        text = show_page_labels and _("The default (★) for newly opened books that have a reference page numbers map is to show reference page number labels in the margin.\n\nWould you like to change it?")
                        or _("The default (★) for newly opened books that have a reference page numbers map is to not show reference page number labels in the margin.\n\nWould you like to change it?"),
                        choice1_text_func = function()
                            return show_page_labels and _("Hide") or _("Hide (★)")
                        end,
                        choice1_callback = function()
                             G_reader_settings:makeFalse("pagemap_show_page_labels")
                             if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                        choice2_text_func = function()
                            return show_page_labels and _("Show (★)") or _("Show")
                        end,
                        choice2_callback = function()
                            G_reader_settings:makeTrue("pagemap_show_page_labels")
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    })
                end,
            },
            {
                text_func = function()
                    return T(_("Page labels font size (%1)"), self.label_font_size)
                end,
                enabled_func = function() return self.show_page_labels end,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local spin_w = SpinWidget:new{
                        width = math.floor(Screen:getWidth() * 0.6),
                        value = self.label_font_size,
                        value_min = 8,
                        value_max = 20,
                        default_value = self.label_default_font_size,
                        title_text =  _("Page labels font size"),
                        keep_shown_on_apply = true,
                        callback = function(spin)
                            self.label_font_size = spin.value
                            G_reader_settings:saveSetting("pagemap_label_font_size", self.label_font_size)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                            self:resetLayout()
                            self:updateVisibleLabels()
                            UIManager:setDirty(self.view.dialog, "partial")
                        end,
                    }
                    UIManager:show(spin_w)
                end,
                keep_menu_open = true,
            },
        },
    }
end

return ReaderPageMap
