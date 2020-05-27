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
local CloseButton = require("ui/widget/closebutton")
local Device = require("device")
local Font = require("ui/font")
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
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Input = Device.input
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")

local KeyValueTitle = VerticalGroup:new{
    kv_page = nil,
    title = "",
    tface = Font:getFace("tfont"),
    align = "left",
    use_top_page_count = false,
}

function KeyValueTitle:init()
    self.close_button = CloseButton:new{ window = self }
    local btn_width = self.close_button:getSize().w
    -- title and close button
    table.insert(self, OverlapGroup:new{
        dimen = { w = self.width },
        TextWidget:new{
            text = self.title,
            max_width = self.width - btn_width,
            face = self.tface,
        },
        self.close_button,
    })
    -- page count and separation line
    self.title_bottom = OverlapGroup:new{
        dimen = { w = self.width, h = Size.line.thick },
        LineWidget:new{
            dimen = Geom:new{ w = self.width, h = Size.line.thick },
            background = Blitbuffer.COLOR_DARK_GRAY,
            style = "solid",
        },
    }
    if self.use_top_page_count then
        self.page_cnt = FrameContainer:new{
            padding = Size.padding.default,
            margin = 0,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            -- overlap offset x will be updated in setPageCount method
            overlap_offset = {0, -15},
            TextWidget:new{
                text = "",  -- page count
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                face = Font:getFace("smallffont"),
            },
        }
        table.insert(self.title_bottom, self.page_cnt)
    end
    table.insert(self, self.title_bottom)
    table.insert(self, VerticalSpan:new{ width = Size.span.vertical_large })
end

function KeyValueTitle:setPageCount(curr, total)
    if total == 1 then
        -- remove page count if there is only one page
        table.remove(self.title_bottom, 2)
        return
    end
    self.page_cnt[1]:setText(curr .. "/" .. total)
    self.page_cnt.overlap_offset[1] = (self.width - self.page_cnt:getSize().w - 10)
    self.title_bottom[2] = self.page_cnt
end

function KeyValueTitle:onClose()
    self.kv_page:onClose()
    return true
end


local KeyValueItem = InputContainer:new{
    key = nil,
    value = nil,
    value_lang = nil,
    cface = Font:getFace("smallinfofont"),
    tface = Font:getFace("smallinfofontbold"),
    width = nil,
    height = nil,
    textviewer_width = nil,
    textviewer_height = nil,
    value_overflow_align = "left",
        -- "right": only align right if value overflow 1/2 width
        -- "right_always": align value right even when small and
        --                 only key overflows 1/2 width
}

function KeyValueItem:init()
    self.dimen = Geom:new{w = self.width, h = self.height}

    -- self.value may contain some control characters (\n \t...) that would
    -- be rendered as a square. Replace them with a shorter and nicer '|'.
    -- (Let self.value untouched, as with Hold, the original value can be
    -- displayed correctly in TextViewer.)
    local tvalue = tostring(self.value)
    tvalue = tvalue:gsub("[\n\t]", "|")

    local frame_padding = Size.padding.default
    local frame_internal_width = self.width - frame_padding * 2
    local middle_padding = Size.padding.default -- min enforced padding between key and value
    local available_width = frame_internal_width - middle_padding

    -- Default widths (and position of value widget) if each text fits in 1/2 screen width
    local key_w = frame_internal_width / 2 - middle_padding
    local value_w = frame_internal_width / 2

    local key_widget = TextWidget:new{
        text = self.key,
        max_width = available_width,
        face = self.tface,
    }
    local value_widget = TextWidget:new{
        text = tvalue,
        max_width = available_width,
        face = self.cface,
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
            -- Allow for displaying the non-truncated text with Hold
            if Device:isTouchDevice() then
                self.ges_events.Hold = {
                    GestureRange:new{
                        ges = "hold",
                        range = self.dimen,
                    }
                }
                -- If no tap callback, allow for displaying the non-truncated
                -- text with Tap too
                if not self.callback then
                    self.callback = function()
                        self:onHold()
                    end
                end
            end
        else
            -- Both can fit: break the 1/2 widths
            if self.value_align == "right" or self.value_overflow_align == "right_always"
                    or (self.value_overflow_align == "right" and value_w_rendered > value_w) then
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
        -- add some padding to key_w so value is pushed to the screen right border
        key_w = key_w + ( value_w - value_widget:getWidth() )
    end
    key_widget:setMaxWidth(key_w)

    -- For debugging positioning:
    -- value_widget = FrameContainer:new{ padding=0, margin=0, bordersize=1, value_widget }

    if self.callback and Device:isTouchDevice() then
        self.ges_events.Tap = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            }
        }
    end

    self[1] = FrameContainer:new{
        padding = frame_padding,
        bordersize = 0,
        HorizontalGroup:new{
            dimen = self.dimen:copy(),
            LeftContainer:new{
                dimen = {
                    w = key_w,
                    h = self.height
                },
                key_widget,
            },
            HorizontalSpan:new{
                width = middle_padding,
            },
            LeftContainer:new{
                dimen = {
                    w = value_w,
                    h = self.height
                },
                value_widget,
            }
        }
    }
end

function KeyValueItem:onTap()
    if self.callback then
        if G_reader_settings:isFalse("flash_ui") then
            self.callback()
        else
            self[1].invert = true
            UIManager:widgetRepaint(self[1], self[1].dimen.x, self[1].dimen.y)
            UIManager:setDirty(nil, function()
                return "fast", self[1].dimen
            end)
            UIManager:tickAfterNext(function()
                self.callback()
                self[1].invert = false
                UIManager:widgetRepaint(self[1], self[1].dimen.x, self[1].dimen.y)
                UIManager:setDirty(nil, function()
                    return "ui", self[1].dimen
                end)
            end)
        end
    end
    return true
end

function KeyValueItem:onHold()
    local textviewer = TextViewer:new{
        title = self.key,
        text = self.value,
        lang = self.value_lang,
        width = self.textviewer_width,
        height = self.textviewer_height,
    }
    UIManager:show(textviewer)
    return true
end


local KeyValuePage = InputContainer:new{
    title = "",
    width = nil,
    height = nil,
    values_lang = nil,
    -- index for the first item to show
    show_page = 1,
    use_top_page_count = false,
    -- aligment of value when key or value overflows its reserved width (for
    -- now: 50%): "left" (stick to key), "right" (stick to scren right border)
    value_overflow_align = "left",
}

function KeyValuePage:init()
    self.dimen = Geom:new{
        w = self.width or Screen:getWidth(),
        h = self.height or Screen:getHeight(),
    }
    if self.dimen.w == Screen:getWidth() and self.dimen.h == Screen:getHeight() then
        self.covers_fullscreen = true -- hint for UIManager:_repaint()
    end

    if Device:hasKeys() then
        self.key_events = {
            Close = { {"Back"}, doc = "close page" },
            NextPage = {{Input.group.PgFwd}, doc = "next page"},
            PrevPage = {{Input.group.PgBack}, doc = "prev page"},
        }
    end
    if Device:isTouchDevice() then
        self.ges_events.Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = self.dimen,
            }
        }
    end

    -- return button
    --- @todo: alternative icon if BD.mirroredUILayout()
    self.page_return_arrow = Button:new{
        icon = "resources/icons/appbar.arrow.left.up.png",
        callback = function() self:onReturn() end,
        bordersize = 0,
        show_parent = self,
    }
    -- group for page info
    local chevron_left = "resources/icons/appbar.chevron.left.png"
    local chevron_right = "resources/icons/appbar.chevron.right.png"
    local chevron_first = "resources/icons/appbar.chevron.first.png"
    local chevron_last = "resources/icons/appbar.chevron.last.png"
    if BD.mirroredUILayout() then
        chevron_left, chevron_right = chevron_right, chevron_left
        chevron_first, chevron_last = chevron_last, chevron_first
    end
    self.page_info_left_chev = Button:new{
        icon = chevron_left,
        callback = function() self:prevPage() end,
        bordersize = 0,
        show_parent = self,
    }
    self.page_info_right_chev = Button:new{
        icon = chevron_right,
        callback = function() self:nextPage() end,
        bordersize = 0,
        show_parent = self,
    }
    self.page_info_first_chev = Button:new{
        icon = chevron_first,
        callback = function() self:goToPage(1) end,
        bordersize = 0,
        show_parent = self,
    }
    self.page_info_last_chev = Button:new{
        icon = chevron_last,
        callback = function() self:goToPage(self.pages) end,
        bordersize = 0,
        show_parent = self,
    }
    self.page_info_spacer = HorizontalSpan:new{
        width = Screen:scaleBySize(32),
    }
    self.page_return_spacer = HorizontalSpan:new{
        width = self.page_return_arrow:getSize().w
    }

    if self.callback_return == nil and self.return_button == nil then
        self.page_return_arrow:hide()
    elseif self.callback_return == nil then
        self.page_return_arrow:disable()
    end

    self.page_info_left_chev:hide()
    self.page_info_right_chev:hide()
    self.page_info_first_chev:hide()
    self.page_info_last_chev:hide()

    self.page_info_text = Button:new{
        text = "",
        hold_input = {
            title = _("Enter page number"),
            type = "number",
            hint_func = function()
                return "(" .. "1 - " .. self.pages .. ")"
            end,
            callback = function(input)
                local page = tonumber(input)
                if page and page >= 1 and page <= self.pages then
                    self:goToPage(page)
                end
            end,
        },
        bordersize = 0,
        margin = Screen:scaleBySize(20),
        text_font_face = "pgfont",
        text_font_bold = false,
    }
    self.page_info = HorizontalGroup:new{
        self.page_return_arrow,
        self.page_info_first_chev,
        self.page_info_spacer,
        self.page_info_left_chev,
        self.page_info_text,
        self.page_info_right_chev,
        self.page_info_spacer,
        self.page_info_last_chev,
        self.page_return_spacer,
    }

    local footer = BottomContainer:new{
        dimen = self.dimen:copy(),
        self.page_info,
    }

    local padding = Size.padding.large
    self.item_width = self.dimen.w - 2 * padding
    self.item_height = Size.item.height_default
    -- setup title bar
    self.title_bar = KeyValueTitle:new{
        title = self.title,
        width = self.item_width,
        height = self.item_height,
        use_top_page_count = self.use_top_page_count,
        kv_page = self,
    }
    -- setup main content
    self.item_margin = self.item_height / 4
    local line_height = self.item_height + 2 * self.item_margin
    local content_height = self.dimen.h - self.title_bar:getSize().h - self.page_info:getSize().h
    self.items_per_page = math.floor(content_height / line_height)
    self.pages = math.ceil(#self.kv_pairs / self.items_per_page)
    self.main_content = VerticalGroup:new{}

    -- set textviewer height to let our title fully visible
    self.textviewer_width = self.item_width
    self.textviewer_height = self.dimen.h - 2*self.title_bar:getSize().h

    self:_populateItems()

    local content = OverlapGroup:new{
        dimen = self.dimen:copy(),
        allow_mirroring = false,
        VerticalGroup:new{
            align = "left",
            self.title_bar,
            self.main_content,
        },
        footer,
    }
    -- assemble page
    self[1] = FrameContainer:new{
        height = self.dimen.h,
        padding = padding,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content
    }
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

-- make sure self.item_margin and self.item_height are set before calling this
function KeyValuePage:_populateItems()
    self.page_info:resetLayout()
    self.main_content:clear()
    local idx_offset = (self.show_page - 1) * self.items_per_page
    for idx = 1, self.items_per_page do
        local entry = self.kv_pairs[idx_offset + idx]
        if entry == nil then break end

        table.insert(self.main_content,
                     VerticalSpan:new{ width = self.item_margin })
        if type(entry) == "table" then
            table.insert(
                self.main_content,
                KeyValueItem:new{
                    height = self.item_height,
                    width = self.item_width,
                    key = entry[1],
                    value = entry[2],
                    value_lang = self.values_lang,
                    callback = entry.callback,
                    callback_back = entry.callback_back,
                    textviewer_width = self.textviewer_width,
                    textviewer_height = self.textviewer_height,
                    value_overflow_align = self.value_overflow_align,
                    value_align = self.value_align,
                    show_parent = self,
                }
            )
        elseif type(entry) == "string" then
            local c = string.sub(entry, 1, 1)
            if c == "-" then
                table.insert(self.main_content,
                             VerticalSpan:new{ width = self.item_margin })
                table.insert(self.main_content, LineWidget:new{
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                    dimen = Geom:new{
                        w = self.item_width,
                        h = Size.line.thick
                    },
                    style = "solid",
                })
            end
        end
        table.insert(self.main_content,
                     VerticalSpan:new{ width = self.item_margin })
    end
    self.page_info_text:setText(T(_("Page %1 of %2"), self.show_page, self.pages))
    self.page_info_left_chev:showHide(self.pages > 1)
    self.page_info_right_chev:showHide(self.pages > 1)
    self.page_info_first_chev:showHide(self.pages > 2)
    self.page_info_last_chev:showHide(self.pages > 2)

    self.page_info_left_chev:enableDisable(self.show_page > 1)
    self.page_info_right_chev:enableDisable(self.show_page < self.pages)
    self.page_info_first_chev:enableDisable(self.show_page > 1)
    self.page_info_last_chev:enableDisable(self.show_page < self.pages)

    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
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

function KeyValuePage:onClose()
    UIManager:close(self)
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
