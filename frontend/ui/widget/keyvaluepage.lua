--[[--
Widget that presents a multi-page to show key value pairs.

Example:

    local Foo = KeyValuePage:new{
        title = "Statistics",
        kv_pairs = {
            {"Current period", "00:00:00"},
            -- single or more "-" will generate a solid line
            "----------------------------",
            {"Page to read", "5"},
            {"Time to read", "00:01:00"},
            {"Press me", "will invoke the callback",
             callback = function() print("hello") end },
        },
    }
    UIManager:show(Foo)

]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("ui/widget/button")
local Device = require("device")
local Font = require("ui/font")
local FocusManager = require("ui/widget/focusmanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextViewer = require("ui/widget/textviewer")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Input = Device.input
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")

local KeyValueItem = InputContainer:extend{
    show_parent = nil,
    key = nil,
    value = nil,
    value_lang = nil,
    font_size = 20, -- will be adjusted depending on keyvalues_per_page
    frame_padding = Size.padding.default,
    middle_padding = Size.padding.default, -- min enforced padding between key and value
    key_font_name = "smallinfofontbold",
    value_font_name = "smallinfofont",
    width = nil,
    height = nil,
    textviewer_width = nil,
    textviewer_height = nil,
    value_overflow_align = "left",
        -- "right": only align right if value overflow 1/2 width
        -- "right_always": align value right even when small and
        --                 only key overflows 1/2 width
    close_callback = nil,
}

function KeyValueItem:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }

    -- self.value may contain some control characters (\n \t...) that would
    -- be rendered as a square. Replace them with a shorter and nicer '|'.
    -- (Let self.value untouched, as with Hold, the original value can be
    -- displayed correctly in TextViewer.)
    local tvalue = tostring(self.value)
    tvalue = tvalue:gsub("[\n\t]", "|")

    local frame_padding = self.frame_padding
    local frame_internal_width = self.width - frame_padding * 2
    local middle_padding = self.middle_padding
    local available_width = frame_internal_width - middle_padding

    -- Default widths (and position of value widget) if each text fits in 1/2 screen width
    local ratio = self.width_ratio or 0.5
    local key_w = math.floor(frame_internal_width * ratio - middle_padding)
    local value_w = math.floor(frame_internal_width * (1-ratio))

    if self.key_bold == false then
        self.key_font_name = self.value_font_name
    end
    local key_widget = TextWidget:new{
        text = self.key,
        max_width = available_width,
        face = Font:getFace(self.key_font_name, self.font_size),
    }
    local value_widget = TextWidget:new{
        text = tvalue,
        max_width = available_width,
        face = Font:getFace(self.value_font_name, self.font_size),
        lang = self.value_lang,
    }
    local key_w_rendered = key_widget:getWidth()
    local value_w_rendered = value_widget:getWidth()

    -- As both key_widget and value_width will be in a HorizontalGroup,
    -- and key is always left aligned, we can just tweak the key width
    -- to position the value_widget
    local value_align_right = false
    local fit_right_align = true -- by default, really right align

    if key_w_rendered > key_w or value_w_rendered > value_w then
        -- One (or both) does not fit in 1/2 width
        if key_w_rendered + value_w_rendered > available_width then
            -- Both do not fit: one has to be truncated so they fit
            if key_w_rendered >= value_w_rendered then
                -- Rare case: key larger than value.
                -- We should have kept our keys small, smaller than 1/2 width.
                -- If it is larger than value, it's that value is kinda small,
                -- so keep the whole value, and truncate the key
                key_w = available_width - value_w_rendered
            else
                -- Usual case: value larger than key.
                -- Keep our small key, fit the value in the remaining width.
                key_w = key_w_rendered
            end
            value_align_right = true -- so the ellipsis touches the screen right border
            if self.value_align ~= "right" and self.value_overflow_align ~= "right"
                    and self.value_overflow_align ~= "right_always" then
                -- Don't adjust the ellipsis to the screen right border,
                -- so the left of text is aligned with other truncated texts
                fit_right_align = false
            end
            -- Allow for displaying the non-truncated text with Tap or Hold if not already used
            self.is_truncated = true
        else
            -- Both can fit: break the 1/2 widths
            if self.value_align == "right" or self.value_overflow_align == "right_always"
                    or (self.value_overflow_align == "right" and value_w_rendered > value_w)
                    or key_w_rendered < key_w then -- it's the value that can't fit (longer), this way it stays closest to border
                key_w = available_width - value_w_rendered
                value_align_right = true
            else
                key_w = key_w_rendered
            end
        end
        -- In all the above case, we set the right key_w to include any
        -- needed additional in-between padding: value_w is what's left.
        value_w = available_width - key_w
    else
        if self.value_align == "right" then
            key_w = available_width - value_w_rendered
            value_w = value_w_rendered
            value_align_right = true
        end
    end

    -- Adjust widgets' max widths if needed
    value_widget:setMaxWidth(value_w)
    if fit_right_align and value_align_right and value_widget:getWidth() < value_w then
        -- Because of truncation at glyph boundaries, value_widget
        -- may be a tad smaller than the specified value_w:
        -- adjust key_w so value is pushed to the screen right border
        value_w = value_widget:getWidth()
        key_w = available_width - value_w
    end
    key_widget:setMaxWidth(key_w)

    -- For debugging positioning:
    -- value_widget = FrameContainer:new{ padding=0, margin=0, bordersize=1, value_widget }

    self.ges_events.Tap = {
        GestureRange:new{
            ges = "tap",
            range = self.dimen,
        }
    }
    self.ges_events.Hold = {
        GestureRange:new{
            ges = "hold",
            range = self.dimen,
        }
    }
    local content_dimen = self.dimen:copy()
    content_dimen.h = content_dimen.h - Size.border.thin * 2 -- reduced by 2 border sizes
    content_dimen.w = content_dimen.w - Size.border.thin * 2 -- reduced by 2 border sizes
    self[1] = FrameContainer:new{
        padding = frame_padding,
        padding_top = 0,
        padding_bottom = 0,
        bordersize = 0,
        focusable = true,
        focus_border_size = Size.border.thin,
        focus_inner_border = true,
        background = Blitbuffer.COLOR_WHITE,
        HorizontalGroup:new{
            dimen = content_dimen,
            LeftContainer:new{
                dimen = Geom:new{
                    w = key_w,
                    h = content_dimen.h
                },
                key_widget,
            },
            HorizontalSpan:new{
                width = middle_padding,
            },
            LeftContainer:new{
                dimen = {
                    w = value_w,
                    h = content_dimen.h
                },
                value_widget,
            }
        }
    }
end

function KeyValueItem:onTap()
    if self.callback then
        if G_reader_settings:isFalse("flash_ui") then
            self.callback(self.kv_page, self)
        else
            -- c.f., ui/widget/iconbutton for the canonical documentation about the flash_ui code flow

            -- Highlight
            --
            self[1].invert = true
            UIManager:widgetInvert(self[1], self[1].dimen.x, self[1].dimen.y)
            UIManager:setDirty(nil, "fast", self[1].dimen)

            UIManager:forceRePaint()
            UIManager:yieldToEPDC()

            -- Unhighlight
            --
            self[1].invert = false
            UIManager:widgetInvert(self[1], self[1].dimen.x, self[1].dimen.y)
            UIManager:setDirty(nil, "ui", self[1].dimen)

            -- Callback
            --
            self.callback(self.kv_page, self)

            UIManager:forceRePaint()
        end
    else
        -- If no tap callback, allow for displaying the non-truncated
        -- text with Tap too
        if self.is_truncated then
            self:onShowKeyValue()
        end
    end
    return true
end

function KeyValueItem:onHold()
    if self.hold_callback then
        self.hold_callback(self.kv_page, self)
    else
        if self.is_truncated then
            self:onShowKeyValue()
        end
    end
    return true
end

function KeyValueItem:onShowKeyValue()
    local textviewer = TextViewer:new{
        title = self.key,
        title_multilines = true, -- in case it's key/title that is too long
        text = self.value,
        lang = self.value_lang,
        width = self.textviewer_width,
        height = self.textviewer_height,
    }
    UIManager:show(textviewer)
    return true
end


local KeyValuePage = FocusManager:extend{
    show_parent = nil,
    kv_pairs = nil, -- not mandatory
    title = "",
    width = nil,
    height = nil,
    values_lang = nil,
    -- index for the first item to show
    show_page = 1,
    -- alignment of value when key or value overflows its reserved width (for
    -- now: 50%): "left" (stick to key), "right" (stick to screen's right border)
    value_overflow_align = "left",
    single_page = nil, -- show all items on one single page (and make them small)
    title_bar_align = "left",
    title_bar_left_icon = nil,
    title_bar_left_icon_tap_callback = nil,
    title_bar_left_icon_hold_callback = nil,
}

function KeyValuePage:init()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    self.show_parent = self.show_parent or self
    self.kv_pairs = self.kv_pairs or {}
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.width or screen_w,
        h = self.height or screen_h,
    }
    if self.dimen.w == screen_w and self.dimen.h == screen_h then
        self.covers_fullscreen = true -- hint for UIManager:_repaint()
    end

    if Device:hasKeys() then
        self.key_events.CloseWithKey = { { Input.group.Back } }
        self.key_events.NextPage = { { Input.group.PgFwd } }
        self.key_events.PrevPage = { { Input.group.PgBack } }
        if Device:hasScreenKB() or Device:hasKeyboard() then
            local modifier = Device:hasScreenKB() and "ScreenKB" or "Shift"
            self.key_events.FirstPage = { { modifier, Input.group.PgFwd }, event = "GoToPage", args = 1 }
            self.key_events.LastPage = { { modifier, Input.group.PgBack }, event = "GoToPage", args = self.pages}
        end
    end
    if Device:isTouchDevice() then
        self.ges_events.Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = self.dimen,
            }
        }
        self.ges_events.MultiSwipe = {
            GestureRange:new{
                ges = "multiswipe",
                range = self.dimen,
            }
        }
    end

    -- return button
    --- @todo: alternative icon if BD.mirroredUILayout()
    self.page_return_arrow = self.page_return_arrow or Button:new{
        icon = BD.mirroredUILayout() and "back.top.rtl" or "back.top",
        callback = function() self:onReturn() end,
        bordersize = 0,
        show_parent = self.show_parent,
    }
    -- group for page info
    local chevron_left = "chevron.left"
    local chevron_right = "chevron.right"
    local chevron_first = "chevron.first"
    local chevron_last = "chevron.last"
    if BD.mirroredUILayout() then
        chevron_left, chevron_right = chevron_right, chevron_left
        chevron_first, chevron_last = chevron_last, chevron_first
    end
    self.page_info_left_chev = self.page_info_left_chev or Button:new{
        icon = chevron_left,
        callback = function() self:prevPage() end,
        bordersize = 0,
        show_parent = self.show_parent,
    }
    self.page_info_right_chev = self.page_info_right_chev or Button:new{
        icon = chevron_right,
        callback = function() self:nextPage() end,
        bordersize = 0,
        show_parent = self.show_parent,
    }
    self.page_info_first_chev = self.page_info_first_chev or Button:new{
        icon = chevron_first,
        callback = function() self:goToPage(1) end,
        bordersize = 0,
        show_parent = self.show_parent,
    }
    self.page_info_last_chev = self.page_info_last_chev or Button:new{
        icon = chevron_last,
        callback = function() self:goToPage(self.pages) end,
        bordersize = 0,
        show_parent = self.show_parent,
    }
    self.page_info_spacer = HorizontalSpan:new{
        width = Screen:scaleBySize(32),
    }

    if self.callback_return == nil and self.return_button == nil then
        self.page_return_arrow:hide()
    elseif self.callback_return == nil then
        self.page_return_arrow:disable()
    end
    self.return_button = HorizontalGroup:new{
        HorizontalSpan:new{
            width = Size.span.horizontal_small,
        },
        self.page_return_arrow,
        HorizontalSpan:new{
            width = self.dimen.w - self.page_return_arrow:getSize().w - Size.span.horizontal_small,
        },
    }

    self.page_info_left_chev:hide()
    self.page_info_right_chev:hide()
    self.page_info_first_chev:hide()
    self.page_info_last_chev:hide()

    self.page_info_text = self.page_info_text or Button:new{
        text = "",
        hold_input = {
            title = _("Enter page number"),
            input_type = "number",
            hint_func = function()
                return string.format("(1 - %s)", self.pages)
            end,
            callback = function(input)
                local page = tonumber(input)
                if page and page >= 1 and page <= self.pages then
                    self:goToPage(page)
                end
            end,
            ok_text = _("Go to page"),
        },
        call_hold_input_on_tap = true,
        bordersize = 0,
        text_font_face = "pgfont",
        text_font_bold = false,
    }
    self.page_info = HorizontalGroup:new{
        self.page_info_first_chev,
        self.page_info_spacer,
        self.page_info_left_chev,
        self.page_info_spacer,
        self.page_info_text,
        self.page_info_spacer,
        self.page_info_right_chev,
        self.page_info_spacer,
        self.page_info_last_chev,
    }

    local padding = Size.padding.large
    self.item_width = self.dimen.w - 2 * padding

    local footer = BottomContainer:new{
        dimen = self.dimen:copy(),
        self.page_info,
    }
    if self.single_page then
        footer = nil
    end

    local page_return = BottomContainer:new{
        dimen = self.dimen:copy(),
        self.return_button,
    }

    self.title_bar = TitleBar:new{
        title = self.title,
        fullscreen = self.covers_fullscreen,
        width = self.width,
        align = self.title_bar_align,
        with_bottom_line = true,
        bottom_line_color = Blitbuffer.COLOR_DARK_GRAY,
        bottom_line_h_padding = padding,
        left_icon = self.title_bar_left_icon,
        left_icon_tap_callback = self.title_bar_left_icon_tap_callback,
        left_icon_hold_callback = self.title_bar_left_icon_hold_callback,
        close_callback = function() self:onClose() end,
        show_parent = self.show_parent or self,
    }

    -- setup main content
    local available_height = self.dimen.h
                         - self.title_bar:getHeight()
                         - Size.span.vertical_large -- for above page_info (as title_bar adds one itself)
                         - (self.single_page and 0 or self.page_info:getSize().h)
                         - 2*Size.line.thick
                            -- account for possibly 2 separator lines added

    local nb_items_landscape, nb_items_portrait = KeyValuePage.getCurrentItemsPerPage()
    self.items_per_page = screen_h < screen_w and nb_items_landscape or nb_items_portrait
    if self.single_page and self.items_per_page < #self.kv_pairs then
        self.items_per_page = #self.kv_pairs
    end
    self.item_height = math.floor(available_height / self.items_per_page)
    -- Put half of the pixels lost by floor'ing between title and content
    local content_height = self.items_per_page * self.item_height
    local span_height = math.floor((available_height - content_height) / 2)

    -- Font size is not configurable: we can get a good one from the following
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local line_extra_height = 1.0 -- ~ 2em -- unscaled_size_check: ignore
        -- (gives a font size similar to the fixed one from former implementation at 14 items per page)
    self.items_font_size = math.min(TextBoxWidget:getFontSizeToFitHeight(self.item_height, 1, line_extra_height), 22)

    self.pages = math.ceil(#self.kv_pairs / self.items_per_page)
    self.main_content = VerticalGroup:new{}

    -- set textviewer height to let our title fully visible (but hide the bottom line)
    self.textviewer_width = self.item_width
    self.textviewer_height = self.dimen.h - 2 * (self.title_bar:getHeight() - Size.padding.default - Size.line.thick)

    self:_populateItems()

    local content = OverlapGroup:new{
        allow_mirroring = false,
        dimen = self.dimen:copy(),
        VerticalGroup:new{
            align = "left",
            self.title_bar,
            VerticalSpan:new{ width = span_height },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = padding },
                self.main_content,
            }
        },
        page_return,
        footer,
    }
    -- assemble page
    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        padding = 0,
        margin = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }
end

function KeyValuePage.getDefaultItemsPerPage()
    -- Get a default according to Screen DPI (roughly following
    -- the former implementation building logic)
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    if screen_w > screen_h then
        screen_w, screen_h = screen_h, screen_w
    end
    local default_item_height = Size.item.height_default * 1.5 -- we were adding 1/2 as margin
    local nb_items_landscape = math.floor(screen_w / default_item_height) - 3 -- account for title and footer heights
    local nb_items_portrait = math.floor(screen_h / default_item_height) - 3
    return nb_items_landscape, nb_items_portrait
end

function KeyValuePage.getCurrentItemsPerPage(nb_items_landscape_default, nb_items_portrait_default)
    if nb_items_landscape_default == nil then
        nb_items_landscape_default, nb_items_portrait_default = KeyValuePage.getDefaultItemsPerPage()
    end
    local nb_items_landscape = G_reader_settings:readSetting("keyvalues_per_page_landscape") or nb_items_landscape_default
    local nb_items_portrait = G_reader_settings:readSetting("keyvalues_per_page") or nb_items_portrait_default
    return nb_items_landscape, nb_items_portrait
end

function KeyValuePage:nextPage()
    local new_page = math.min(self.show_page+1, self.pages)
    if new_page > self.show_page then
        self.show_page = new_page
        self:_populateItems()
    end
end

function KeyValuePage:prevPage()
    local new_page = math.max(self.show_page-1, 1)
    if new_page < self.show_page then
        self.show_page = new_page
        self:_populateItems()
    end
end

function KeyValuePage:goToPage(page)
    self.show_page = page
    self:_populateItems()
end

function KeyValuePage:onGoToPage(page)
    self:goToPage(page)
    return true
end

-- make sure self.item_margin and self.item_height are set before calling this
function KeyValuePage:_populateItems()
    self.layout = {}
    self.page_info:resetLayout()
    self.return_button:resetLayout()
    self.main_content:clear()
    local idx_offset = (self.show_page - 1) * self.items_per_page

    -- for flexible middle ratio calculation
    -- in sync with KeyValueItem actual computation
    local frame_padding = KeyValueItem.frame_padding
    local frame_internal_width = self.item_width - frame_padding * 2
    local middle_padding = KeyValueItem.middle_padding
    local available_width = frame_internal_width - middle_padding
    -- Default widths (and position of value widget) if each text fits in 1/2 screen width
    local key_w = math.floor(frame_internal_width / 2 - middle_padding)
    local value_w = math.floor(frame_internal_width / 2)

    local key_widget = TextWidget:new{
        text = " ",
        max_width = available_width,
        face = Font:getFace("smallinfofontbold", self.items_font_size),
    }
    local value_widget = TextWidget:new{
        text = " ",
        max_width = available_width,
        face = Font:getFace("smallinfofont", self.items_font_size),
        lang = self.values_lang,
    }
    local key_widths = {}
    local value_widths = {}
    local tvalue
    for idx=1, self.items_per_page do
        local kv_pairs_idx = idx_offset + idx
        local entry = self.kv_pairs[kv_pairs_idx]
        if entry == nil then break end
        if type(entry) == "table" and entry[2] ~= "" then
            tvalue = tostring(entry[2])
            tvalue = tvalue:gsub("[\n\t]", "|")

            key_widget:setText(entry[1])
            value_widget:setText(tvalue)

            table.insert(key_widths, key_widget:getWidth())
            table.insert(value_widths, value_widget:getWidth())
        end
    end
    key_widget:free()
    value_widget:free()
    table.sort(key_widths)
    table.sort(value_widths)
    -- first we check if no unfit item at all
    local width_ratio
    if (#self.kv_pairs == 0) or
        (#key_widths == 0) or
        (key_widths[#key_widths] <= key_w and value_widths[#value_widths] <= value_w) then
        width_ratio = 1/2
    end
    if not width_ratio then
        -- has to adjust, not fitting 1/2 ratio
        local least_cut_key_index = #key_widths; -- the key index from which there are least number of cuts
        local least_cut_count = #key_widths; -- the nb of cuts
        for vi = #value_widths, 1, -1 do
            -- from longest to shortest
            local key_width_limit = available_width - value_widths[vi]

            -- if we were to draw a vertical line at the start of the value item,
            -- i.e. the border between keys and values, we want the less items cross it the better,
            -- as the keys/values that cross the line (being cut) make clean alignment impossible
            -- we track their number and find the line that cuts the least key/value items
            local key_cut_count = 0
            local key_index
            for ki = #key_widths, 1, -1 do
                -- from longest to shortest for keys too
                if key_widths[ki] > key_width_limit then
                    key_cut_count = key_cut_count + 1 -- got cut
                else
                    key_index = ki
                    break -- others are all shorter so no more cut
                end
            end
            local total_cut_count = key_cut_count + (#value_widths - vi) -- latter is value_cut_count, as with each increased index, the previous one got cut
            if total_cut_count == 0 then
                -- no cross-over
                if key_widths[#key_widths] >= key_w then
                    width_ratio = (key_widths[#key_widths] + middle_padding) / frame_internal_width
                else
                    width_ratio = 1 - value_widths[#value_widths] / frame_internal_width
                end
                break
            elseif total_cut_count < least_cut_count and key_index then
                least_cut_count = total_cut_count
                least_cut_key_index = key_index
            end
        end
        if not width_ratio then
            width_ratio = (key_widths[least_cut_key_index] + middle_padding) / frame_internal_width
        end
    end

    width_ratio = width_ratio or 0.5

    for idx = 1, self.items_per_page do
        local kv_pairs_idx = idx_offset + idx
        local entry = self.kv_pairs[kv_pairs_idx]
        if entry == nil then break end

        if type(entry) == "table" then
            local kv_item = KeyValueItem:new{
                height = self.item_height,
                width = self.item_width,
                width_ratio = width_ratio,
                font_size = self.items_font_size,
                key_bold = entry.key_bold,
                key = entry[1],
                value = entry[2],
                value_lang = self.values_lang,
                callback = entry.callback,
                hold_callback = entry.hold_callback,
                textviewer_width = self.textviewer_width,
                textviewer_height = self.textviewer_height,
                value_overflow_align = self.value_overflow_align,
                value_align = self.value_align,
                kv_pairs_idx = kv_pairs_idx,
                kv_page = self,
                show_parent = self.show_parent,
            }
            table.insert(self.main_content, kv_item)
            table.insert(self.layout, { kv_item })
            if entry.separator then
                table.insert(self.main_content, LineWidget:new{
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                    dimen = Geom:new{
                        w = self.item_width,
                        h = Size.line.thick,
                    },
                    style = "solid",
                })
            end
        elseif type(entry) == "string" then
            -- deprecated, use separator=true on a regular k/v table
            -- (kept in case some user plugins would use this)
            local c = string.sub(entry, 1, 1)
            if c == "-" then
                table.insert(self.main_content, LineWidget:new{
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                    dimen = Geom:new{
                        w = self.item_width,
                        h = Size.line.thick,
                    },
                    style = "solid",
                })
            end
        end
    end

    -- update page information
    if self.pages >= 1 then
        self.page_info_text:setText(T(_("Page %1 of %2"), self.show_page, self.pages))
        if self.pages > 1 then
            self.page_info_text:enable()
        else
            self.page_info_text:disableWithoutDimming()
        end
        self.page_info_left_chev:show()
        self.page_info_right_chev:show()
        self.page_info_first_chev:show()
        self.page_info_last_chev:show()

        self.page_info_left_chev:enableDisable(self.show_page > 1)
        self.page_info_right_chev:enableDisable(self.show_page < self.pages)
        self.page_info_first_chev:enableDisable(self.show_page > 1)
        self.page_info_last_chev:enableDisable(self.show_page < self.pages)
    else
        self.page_info_text:setText(_("No items"))
        self.page_info_text:disableWithoutDimming()

        self.page_info_left_chev:hide()
        self.page_info_right_chev:hide()
        self.page_info_first_chev:hide()
        self.page_info_last_chev:hide()
    end
    self:moveFocusTo(1, 1, bit.bor(FocusManager.FOCUS_ONLY_ON_NT, FocusManager.NOT_UNFOCUS))
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function KeyValuePage:removeKeyValueItem(kv_item)
    if kv_item.kv_pairs_idx then
        table.remove(self.kv_pairs, kv_item.kv_pairs_idx)
        self.pages = math.ceil(#self.kv_pairs / self.items_per_page)
        self.show_page = math.min(self.show_page, self.pages)
        self:_populateItems()
    end
end

function KeyValuePage:onNextPage()
    self:nextPage()
    return true
end

function KeyValuePage:onPrevPage()
    self:prevPage()
    return true
end

function KeyValuePage:onSwipe(arg, ges_ev)
    local direction = BD.flipDirectionIfMirroredUILayout(ges_ev.direction)
    if direction == "west" then
        self:nextPage()
        return true
    elseif direction == "east" then
        self:prevPage()
        return true
    elseif direction == "south" then
        -- Allow easier closing with swipe down
        self:onClose()
    elseif direction == "north" then
        -- no use for now
        do end -- luacheck: ignore 541
    else -- diagonal swipe
        -- trigger full refresh
        UIManager:setDirty(nil, "full")
        -- a long diagonal swipe may also be used for taking a screenshot,
        -- so let it propagate
        return false
    end
end

function KeyValuePage:onMultiSwipe(arg, ges_ev)
    -- For consistency with other fullscreen widgets where swipe south can't be
    -- used to close and where we then allow any multiswipe to close, allow any
    -- multiswipe to close this widget too.
    self:onClose()
    return true
end

function KeyValuePage:setTitleBarLeftIcon(icon)
    self.title_bar:setLeftIcon(icon)
end

function KeyValuePage:onClose()
    UIManager:close(self)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

function KeyValuePage:onCloseWithKey()
    if self.page_return_arrow and self.callback_return then
        self:callback_return()
    end
    self:onClose()
    return true
end

function KeyValuePage:onReturn()
    if self.callback_return then
        self:callback_return()
        UIManager:close(self)
        UIManager:setDirty(nil, "ui")
    end
end

return KeyValuePage
