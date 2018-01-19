--[[--
Widget that displays a shortcut icon for menu item.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RenderText = require("ui/rendertext")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("ffi/util")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen
local getMenuText = require("util").getMenuText

local ItemShortCutIcon = WidgetContainer:new{
    dimen = Geom:new{ w = Screen:scaleBySize(22), h = Screen:scaleBySize(22) },
    key = nil,
    bordersize = Size.border.default,
    radius = 0,
    style = "square",
}

function ItemShortCutIcon:init()
    if not self.key then
        return
    end

    local radius = 0
    local background = Blitbuffer.COLOR_WHITE
    if self.style == "rounded_corner" then
        radius = math.floor(self.width/2)
    elseif self.style == "grey_square" then
        background = Blitbuffer.gray(0.2)
    end

    --@TODO calculate font size by icon size  01.05 2012 (houqp)
    local sc_face
    if self.key:len() > 1 then
        sc_face = Font:getFace("ffont", 14)
    else
        sc_face = Font:getFace("scfont", 22)
    end

    self[1] = FrameContainer:new{
        padding = 0,
        bordersize = self.bordersize,
        radius = radius,
        background = background,
        dimen = self.dimen,
        CenterContainer:new{
            dimen = self.dimen,
            TextWidget:new{
                text = self.key,
                face = sc_face,
            },
        },
    }
end

--[[
NOTICE:
@menu entry must be provided in order to close the menu
--]]
local MenuCloseButton = InputContainer:new{
    overlap_align = "right",
    padding_right = 0,
    menu = nil,
    dimen = Geom:new{},
}

function MenuCloseButton:init()
    self[1] = TextWidget:new{
        text = "×",
        face = Font:getFace("cfont", 30), -- this font size align nicely with title
    }

    local text_size = self[1]:getSize()
    -- The text box height is greater than its width, and we want this × to
    -- be diagonally aligned with our top right border
    local text_width_pad = (text_size.h - text_size.w) / 2
    -- We also add the provided padding_right
    self.dimen = Geom:new{
        w = text_size.w + text_width_pad + self.padding_right,
        h = text_size.h,
    }

    self.ges_events.Close = {
        GestureRange:new{
            ges = "tap",
            range = self.dimen,
        },
        doc = "Close menu",
    }
end

function MenuCloseButton:onClose()
    self.menu:onClose()
    return true
end

--[[
Widget that displays an item for menu
--]]
local MenuItem = InputContainer:new{
    text = nil,
    show_parent = nil,
    detail = nil,
    face = Font:getFace("cfont", 30),
    info_face = Font:getFace("infont", 15),
    font = "cfont",
    font_size = 24,
    infont = "infont",
    infont_size = 18,
    dimen = nil,
    shortcut = nil,
    shortcut_style = "square",
    _underline_container = nil,
    linesize = Size.line.medium,
}

function MenuItem:init()
    self.content_width = self.dimen.w - 2 * Size.padding.fullscreen
    local shortcut_icon_dimen = Geom:new()
    if self.shortcut then
        shortcut_icon_dimen.w = math.floor(self.dimen.h*4/5)
        shortcut_icon_dimen.h = shortcut_icon_dimen.w
        self.content_width = self.content_width - shortcut_icon_dimen.w - Size.span.horizontal_default
    end

    self.detail = self.text

    -- we need this table per-instance, so we declare it here
    if Device:isTouchDevice() then
        self.ges_events = {
            TapSelect = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
                doc = "Select Menu Item",
            },
            HoldSelect = {
                GestureRange:new{
                    ges = "hold",
                    range = self.dimen,
                },
                doc = "Hold Menu Item",
            },
        }
    end
    if Device:hasKeys() then
        self.active_key_events = {
            Select = { {"Press"}, doc = "chose selected item" },
        }
    end

    local text_mandatory_padding = 0
    local text_ellipsis_mandatory_padding = 0
    if self.mandatory then
        text_mandatory_padding = Size.span.horizontal_default
        -- Smaller padding when ellipsis for better visual feeling
        text_ellipsis_mandatory_padding = Size.span.horizontal_small
    end
    local mandatory = self.mandatory and ""..self.mandatory or ""

    local state_button_width = self.state_size.w or 0
    local state_button = self.state or HorizontalSpan:new{
        width = state_button_width,
    }
    local state_indent = self.state and self.state.indent or ""
    local item_name
    local mandatory_widget

    if self.single_line then  -- items only in single line
        self.info_face = Font:getFace(self.infont, self.infont_size)
        self.face = Font:getFace(self.font, self.font_size)

        local mandatory_w = RenderText:sizeUtf8Text(0, self.dimen.w, self.info_face, ""..mandatory, true, self.bold).x

        local my_text = self.text and ""..self.text or ""
        local w = RenderText:sizeUtf8Text(0, self.dimen.w, self.face, my_text, true, self.bold).x
        if w + mandatory_w + state_button_width + text_mandatory_padding >= self.content_width then
            if Device:hasKeyboard() then
                self.active_key_events.ShowItemDetail = {
                    {"Right"}, doc = "show item detail"
                }
            end
            local indicator = "\226\128\166 " -- an ellipsis
            local indicator_w = RenderText:sizeUtf8Text(0, self.dimen.w, self.face,
                indicator, true, self.bold).x
            self.text = RenderText:getSubTextByWidth(my_text, self.face,
                self.content_width - indicator_w - mandatory_w - state_button_width - text_ellipsis_mandatory_padding,
                true, self.bold) .. indicator
        end

        item_name = TextWidget:new{
            text = self.text,
            face = self.face,
            bold = self.bold,
            fgcolor = self.dim and Blitbuffer.COLOR_GREY or nil,
        }
        mandatory_widget = TextWidget:new{
            text = mandatory,
            face = self.info_face,
            bold = self.bold,
            fgcolor = self.dim and Blitbuffer.COLOR_GREY or nil,
        }
    else
        while true do
            -- Free previously made widgets to avoid memory leaks
            if mandatory_widget then
                mandatory_widget:free()
            end
            mandatory_widget = TextWidget:new {
                text = mandatory,
                face = Font:getFace(self.infont, self.infont_size),
                bold = self.bold,
                fgcolor = self.dim and Blitbuffer.COLOR_GREY or nil,
            }
            local height = mandatory_widget:getSize().h


            if height < self.dimen.h - 2 * self.linesize then -- we fit !
                break
            end
            -- Don't go too low
            if self.infont_size < 12 then
                break;
            else
                -- If we don't fit, decrease font size
                self.infont_size = self.infont_size - 1
            end
        end
        self.info_face = Font:getFace(self.infont, self.infont_size)

        local mandatory_w = RenderText:sizeUtf8Text(0, self.dimen.w, self.info_face, "" .. mandatory, true, self.bold).x
        while true do
            -- Free previously made widgets to avoid memory leaks
            if item_name then
                item_name:free()
            end
            item_name = TextBoxWidget:new {
                text = self.text,
                face = Font:getFace(self.font, self.font_size),
                width = self.content_width - mandatory_w - state_button_width - text_mandatory_padding,
                alignment = "left",
                bold = self.bold,
                fgcolor = self.dim and Blitbuffer.COLOR_GREY or nil,
            }
            local height = item_name:getSize().h
            if height < self.dimen.h - 2 * self.linesize then -- we fit !
                break
            end
            -- Don't go too low, and then truncate text
            if self.font_size < 12 then
                self.text = self.text:sub(1, -5) .. "…"
            else
                -- If we don't fit, decrease font size
                self.font_size = self.font_size - 2
            end
        end
        self.face = Font:getFace(self.font, self.font_size)
    end

    local state_container = LeftContainer:new{
        dimen = Geom:new{w = self.content_width/2, h = self.dimen.h},
        HorizontalGroup:new{
            HorizontalSpan:new{
                width = RenderText:sizeUtf8Text(0, self.dimen.w, self.face,
                    state_indent, true, self.bold).x,
            },
            state_button,
        }
    }
    local text_container = LeftContainer:new{
        dimen = Geom:new{w = self.content_width, h = self.dimen.h},
        HorizontalGroup:new{
            HorizontalSpan:new{
                width = self.state_size.w,
            },
            item_name,
        }
    }

    local mandatory_container = RightContainer:new{
        dimen = Geom:new{w = self.content_width, h = self.dimen.h},
        mandatory_widget,
    }

    self._underline_container = UnderlineContainer:new{
        color = self.line_color,
        linesize = self.linesize,
        vertical_align = "center",
        padding = 0,
        dimen = Geom:new{
            w = self.content_width,
            h = self.dimen.h
        },
        HorizontalGroup:new{
            align = "center",
            OverlapGroup:new{
                dimen = Geom:new{w = self.content_width, h = self.dimen.h},
                state_container,
                text_container,
                mandatory_container,
            },
        }
    }
    local hgroup = HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = Size.padding.fullscreen },
    }
    if self.shortcut then
        table.insert(hgroup, ItemShortCutIcon:new{
            dimen = shortcut_icon_dimen,
            key = self.shortcut,
            style = self.shortcut_style,
        })
        table.insert(hgroup, HorizontalSpan:new{ width = Size.span.horizontal_default })
    end
    table.insert(hgroup, self._underline_container)

    self[1] = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        hgroup,
    }
end

function MenuItem:onFocus()
    self._underline_container.color = Blitbuffer.COLOR_BLACK
    self.key_events = self.active_key_events
    return true
end

function MenuItem:onUnfocus()
    self._underline_container.color = self.line_color
    self.key_events = {}
    return true
end

function MenuItem:onShowItemDetail()
    UIManager:show(InfoMessage:new{ text = self.detail, })
    return true
end

function MenuItem:getGesPosition(ges)
    local dimen = self[1].dimen
    return {
        x = (ges.pos.x - dimen.x)/dimen.w,
        y = (ges.pos.y - dimen.y)/dimen.h,
    }
end

function MenuItem:onTapSelect(arg, ges)
    local pos = self:getGesPosition(ges)
    if G_reader_settings:isFalse("flash_ui") then
        logger.dbg("creating coroutine for menu select")
        local co = coroutine.create(function()
            self.menu:onMenuSelect(self.table, pos)
        end)
        coroutine.resume(co)
    else
        self[1].invert = true
        local refreshfunc = function()
            return "ui", self[1].dimen
        end
        UIManager:setDirty(self.show_parent, refreshfunc)
        UIManager:scheduleIn(0.1, function()
            self[1].invert = false
            UIManager:setDirty(self.show_parent, refreshfunc)
            logger.dbg("creating coroutine for menu select")
            local co = coroutine.create(function()
                self.menu:onMenuSelect(self.table, pos)
            end)
            coroutine.resume(co)
        end)
    end
    return true
end

function MenuItem:onHoldSelect(arg, ges)
    local pos = self:getGesPosition(ges)
    if G_reader_settings:isFalse("flash_ui") then
        self.menu:onMenuHold(self.table, pos)
    else
        self[1].invert = true
        local refreshfunc = function()
            return "ui", self[1].dimen
        end
        UIManager:setDirty(self.show_parent, refreshfunc)
        UIManager:scheduleIn(0.1, function()
            self[1].invert = false
            UIManager:setDirty(self.show_parent, refreshfunc)
            self.menu:onMenuHold(self.table, pos)
        end)
    end
    return true
end

--[[
Widget that displays menu
--]]
local Menu = FocusManager:new{
    show_parent = nil,
    -- face for displaying item contents
    cface = Font:getFace("cfont"),
    -- face for menu title
    tface = Font:getFace("tfont"),
    -- face for paging info display
    fface = Font:getFace("ffont"),
    -- font for item shortcut
    sface = Font:getFace("scfont"),

    title = "No Title",
    -- default width and height
    width = nil,
    -- height will be calculated according to item number if not given
    height = nil,
    header_padding = Size.padding.large,
    dimen = Geom:new{},
    item_table = {},
    item_shortcuts = {
        "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P",
        "A", "S", "D", "F", "G", "H", "J", "K", "L", "Del",
        "Z", "X", "C", "V", "B", "N", "M", ".", "Sym", "Enter",
    },
    item_table_stack = nil,
    is_enable_shortcut = true,

    item_dimen = nil,
    page = 1,

    item_group = nil,
    page_info = nil,
    page_return = nil,

    paths = {},  -- table to trace navigation path

    -- set this to true to not paint as popup menu
    is_borderless = false,
    -- if you want to embed the menu widget into another widget, set
    -- this to false
    is_popout = true,
    -- set this to true to add close button
    has_close_button = true,
    -- close_callback is a function, which is executed when menu is closed
    -- it is usually set by the widget which creates the menu
    close_callback = nil,
    linesize = Size.line.medium,
    perpage = G_reader_settings:readSetting("items_per_page") or 14,
    line_color = Blitbuffer.COLOR_GREY,
}

function Menu:_recalculateDimen()
    self.perpage = G_reader_settings:readSetting("items_per_page") or 14
    self.span_width = 0
    self.dimen.w = self.width
    self.dimen.h = self.height
    if self.dimen.h > Screen:getHeight() or self.dimen.h == nil then
        self.dimen.h = Screen:getHeight()
    end
    self.item_dimen = Geom:new{
        w = self.dimen.w,
        h = Screen:scaleBySize(46),
    }
    local height_dim
    local bottom_height = 0
    local top_height = 0
    if self.page_return_arrow and self.page_info_text then
        bottom_height = math.max(self.page_return_arrow:getSize().h, self.page_info_text:getSize().h)
            + 2 * Size.padding.button
    end
    if self.menu_title and not self.no_title then
        top_height = self.menu_title:getSize().h + 2 * Size.padding.small
    end
    height_dim = self.dimen.h - bottom_height - top_height
    self.item_dimen.h = math.floor(height_dim / self.perpage)
    self.span_width = math.floor((height_dim - (self.perpage * (self.item_dimen.h ))) / 2 -1 )
    self.page_num = math.ceil(#self.item_table / self.perpage)
    -- fix current page if out of range
    if self.page_num > 0 and self.page > self.page_num then self.page = self.page_num end
end

function Menu:init()
    self.show_parent = self.show_parent or self
    self.item_table_stack = {}
    self.dimen.w = self.width
    self.dimen.h = self.height
    if self.dimen.h > Screen:getHeight() or self.dimen.h == nil then
        self.dimen.h = Screen:getHeight()
    end
    self.page = 1

    -----------------------------------
    -- start to set up widget layout --
    -----------------------------------
    self.menu_title = TextWidget:new{
        overlap_align = "center",
        text = self.title,
        face = self.tface,
    }
    -- group for title bar
    self.title_bar = OverlapGroup:new{
        dimen = {w = self.dimen.w, h = self.menu_title:getSize().h},
        self.menu_title,
    }
    -- group for items
    self.item_group = VerticalGroup:new{}
    -- group for page info
    self.page_info_left_chev = Button:new{
        icon = "resources/icons/appbar.chevron.left.png",
        callback = function() self:onPrevPage() end,
        bordersize = 0,
        show_parent = self,
    }
    self.page_info_right_chev = Button:new{
        icon = "resources/icons/appbar.chevron.right.png",
        callback = function() self:onNextPage() end,
        bordersize = 0,
        show_parent = self,
    }
    self.page_info_first_chev = Button:new{
        icon = "resources/icons/appbar.chevron.first.png",
        callback = function() self:onFirstPage() end,
        bordersize = 0,
        show_parent = self,
    }
    self.page_info_last_chev = Button:new{
        icon = "resources/icons/appbar.chevron.last.png",
        callback = function() self:onLastPage() end,
        bordersize = 0,
        show_parent = self,
    }
    self.page_info_spacer = HorizontalSpan:new{
        width = Screen:scaleBySize(32),
    }
    self.page_info_left_chev:hide()
    self.page_info_right_chev:hide()
    self.page_info_first_chev:hide()
    self.page_info_last_chev:hide()

    self.page_info_text = Button:new{
        text = "",
        hold_input = {
            title = _("Input page number"),
            type = "number",
            hint_func = function()
                return "(" .. "1 - " .. self.page_num .. ")"
            end,
            callback = function(input)
                local page = tonumber(input)
                if page and page >= 1 and page <= self.page_num then
                    self:onGotoPage(page)
                end
            end,
        },
        bordersize = 0,
        text_font_face = "cfont",
        text_font_size = 20,
        text_font_bold = false,
    }
    self.page_info = HorizontalGroup:new{
        self.page_info_first_chev,
        self.page_info_spacer,
        self.page_info_left_chev,
        self.page_info_text,
        self.page_info_right_chev,
        self.page_info_spacer,
        self.page_info_last_chev,
    }

    -- return button
    self.page_return_arrow = Button:new{
        icon = "resources/icons/appbar.arrow.left.up.png",
        callback = function() self:onReturn() end,
        bordersize = 0,
        show_parent = self,
    }
    self.page_return_arrow:hide()
    self.return_button = HorizontalGroup:new{
        HorizontalSpan:new{
            width = Size.span.horizontal_small,
        },
        self.page_return_arrow,
    }

    local header = VerticalGroup:new{
        VerticalSpan:new{width = self.header_padding},
        self.title_bar,
    }
    local body = self.item_group
    local footer = BottomContainer:new{
        dimen = self.dimen:copy(),
        self.page_info,
    }
    local page_return = BottomContainer:new{
        dimen = self.dimen:copy(),
        WidgetContainer:new{
            dimen = Geom:new{
                w = Screen:getWidth(),
                h = self.page_return_arrow:getSize().h,
            },
            self.return_button,
        }
    }

    self:_recalculateDimen()
    self.vertical_span = HorizontalGroup:new{
        VerticalSpan:new{ width = self.span_width }
    }
    if self.no_title then
        self.content_group = VerticalGroup:new{
            align = "left",
            self.vertical_span,
            body,
        }
    else
        self.content_group = VerticalGroup:new{
            align = "left",
            header,
            self.vertical_span,
            body,
        }
    end
    local content = OverlapGroup:new{
        dimen = self.dimen:copy(),
        self.content_group,
        page_return,
        footer,
    }

    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = self.is_borderless and 0 or 2,
        padding = 0,
        margin = 0,
        radius = self.is_popout and math.floor(self.dimen.w/20) or 0,
        content
    }
    ------------------------------------------
    -- start to set up input event callback --
    ------------------------------------------
    if Device:isTouchDevice() then
        if self.has_close_button then
            table.insert(self.title_bar, MenuCloseButton:new{
                menu = self,
                padding_right = self.header_padding,
            })
        end
        -- watch for outer region if it's a self contained widget
        if self.is_popout then
            self.ges_events.TapCloseAllMenus = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    }
                }
            }
        end
        self.ges_events.Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = self.dimen,
            }
        }
        self.ges_events.Close = self.on_close_ges
    end

    if not Device:hasKeyboard() then
        -- remove menu item shortcut for K4
        self.is_enable_shortcut = false
    end

    if Device:hasKeys() then
        -- set up keyboard events
        self.key_events.Close = { {"Back"}, doc = "close menu" }
        self.key_events.NextPage = {
            {Input.group.PgFwd}, doc = "goto next page of the menu"
        }
        self.key_events.PrevPage = {
            {Input.group.PgBack}, doc = "goto previous page of the menu"
        }
        -- we won't catch presses to "Right", leave that to MenuItem.
        self.key_events.FocusRight = nil
        -- shortcut icon is not needed for touch device
        if self.is_enable_shortcut then
            self.key_events.SelectByShortCut = { {self.item_shortcuts} }
        end
        self.key_events.Select = {
            {"Press"}, doc = "select current menu item"
        }
    end


    if #self.item_table > 0 then
        -- if the table is not yet initialized, this call
        -- must be done manually:
        self.page = math.ceil((self.item_table.current or 1) / self.perpage)
    end
    if self.path_items then
        self:refreshPath()
    else
        self:updateItems()
    end
end

function Menu:onCloseWidget()
    -- FIXME:
    -- we cannot refresh regionally using the dimen field
    -- because some menus without menu title use VerticalGroup to include
    -- a text widget which is not calculated into the dimen.
    -- For example, it's a dirty hack to use two menus(one this menu and one
    -- touch menu) in the filemanager in order to capture tap gesture to popup
    -- the filemanager menu.
    UIManager:setDirty(nil, "partial")
end

function Menu:updateItems(select_number)
    local old_dimen = self.dimen and self.dimen:copy()
    -- self.layout must be updated for focusmanager
    self.layout = {}
    self.item_group:clear()
    self.page_info:resetLayout()
    self.return_button:resetLayout()
    self.vertical_span:clear()
    self.content_group:resetLayout()
    self:_recalculateDimen()

    -- default to select the first item
    if not select_number then
        select_number = 1
    end
    --font size between 12 and 18 for better matching
    local infont_size = math.floor(18 - (self.perpage - 6) / 3)
    --font size between 14 and 24 for better matching
    local font_size = math.floor(24 - ((self.perpage - 6)/ 18) * 10 )

    for c = 1, math.min(self.perpage, #self.item_table) do
        -- calculate index in item_table
        local i = (self.page - 1) * self.perpage + c
        if i <= #self.item_table then
            local item_shortcut = nil
            local shortcut_style = "square"
            if self.is_enable_shortcut then
                -- give different shortcut_style to keys in different
                -- lines of keyboard
                if c >= 11 and c <= 20 then
                    --shortcut_style = "rounded_corner"
                    shortcut_style = "grey_square"
                end
                item_shortcut = self.item_shortcuts[c]
                if item_shortcut == "Enter" then
                    item_shortcut = "Ent"
                end
            end
            local item_tmp = MenuItem:new{
                show_parent = self.show_parent,
                state = self.item_table[i].state,
                state_size = self.state_size or {},
                text = getMenuText(self.item_table[i]),
                mandatory = self.item_table[i].mandatory,
                bold = self.item_table.current == i or self.item_table[i].bold == true,
                dim = self.item_table[i].dim,
                font = "smallinfofont",
                font_size = font_size,
                infont = "infont",
                infont_size = infont_size,
                dimen = self.item_dimen:new(),
                shortcut = item_shortcut,
                shortcut_style = shortcut_style,
                table = self.item_table[i],
                menu = self,
                linesize = self.linesize,
                single_line = self.single_line,
                line_color = self.line_color,
            }
            table.insert(self.item_group, item_tmp)
            -- this is for focus manager
            table.insert(self.layout, {item_tmp})
        end -- if i <= self.items
    end -- for c=1, self.perpage
    if self.item_group[1] then
        if not Device:isTouchDevice() or Device:hasKeys() then
            -- only draw underline for nontouch device
            -- reset focus manager accordingly
            self.selected = { x = 1, y = select_number }
            -- set focus to requested menu item
            self.item_group[select_number]:onFocus()
        end
        -- update page information
        self.page_info_text:setText(util.template(_("page %1 of %2"), self.page, self.page_num))
        self.page_info_left_chev:showHide(self.page_num > 1)
        self.page_info_right_chev:showHide(self.page_num > 1)
        self.page_info_first_chev:showHide(self.page_num > 2)
        self.page_info_last_chev:showHide(self.page_num > 2)
        self.page_return_arrow:showHide(self.onReturn ~= nil)

        self.page_info_left_chev:enableDisable(self.page > 1)
        self.page_info_right_chev:enableDisable(self.page < self.page_num)
        self.page_info_first_chev:enableDisable(self.page > 1)
        self.page_info_last_chev:enableDisable(self.page < self.page_num)
        self.page_return_arrow:enableDisable(#self.paths > 0)
    else
        self.page_info_text:setText(_("No choices available"))
    end

    UIManager:setDirty("all", function()
        local refresh_dimen =
            old_dimen and old_dimen:combine(self.dimen)
            or self.dimen
        return "ui", refresh_dimen
    end)
end

--[[
    the itemnumber paramter determines menu page number after switching item table
    1. itemnumber >= 0
        the page number is calculated with items per page
    2. itemnumber == nil
        the page number is 1
    3. itemnumber is negative number
        the page number is not changed, used when item_table is appended with
        new entries

    alternatively, itemmatch may be provided as a {key = value} table,
    and the page number will be the page containing the first item for
    which item.key = value
--]]
function Menu:switchItemTable(new_title, new_item_table, itemnumber, itemmatch)
    if self.menu_title and new_title then
        self.menu_title.text = new_title
    end

    if itemnumber == nil then
        self.page = 1
    elseif itemnumber >= 0 then
        self.page = math.ceil(itemnumber / self.perpage)
    end

    if type(itemmatch) == "table" then
        local key, value = next(itemmatch)
        for num, item in ipairs(new_item_table) do
            if item[key] == value then
                self.page = math.floor((num-1) / self.perpage) + 1
                break
            end
        end
    end

    -- make sure current page is in right page range
    local max_pages = math.ceil(#new_item_table / self.perpage)
    if self.page > max_pages then
        self.page = max_pages
    end

    self.item_table = new_item_table
    self:updateItems()
end

function Menu:onSelectByShortCut(_, keyevent)
    for k,v in ipairs(self.item_shortcuts) do
        if k > self.perpage then
            break
        elseif v == keyevent.key then
            if self.item_table[(self.page-1)*self.perpage + k] then
                self:onMenuSelect(self.item_table[(self.page-1)*self.perpage + k])
            end
            break
        end
    end
    return true
end

function Menu:onWrapFirst()
    if self.page > 1 then
        self.page = self.page - 1
        local end_position = self.perpage
        if self.page == self.page_num then
            end_position = #self.item_table % self.perpage
        end
        self:updateItems(end_position)
    end
    return false
end

function Menu:onWrapLast()
    if self.page < self.page_num then
        self:onNextPage()
    end
    return false
end

--[[
override this function to process the item selected in a different manner
]]--
function Menu:onMenuSelect(item)
    if item.sub_item_table == nil then
        if self.close_callback then
            self.close_callback()
        end
        self:onMenuChoice(item)
    else
        -- save menu title for later resume
        self.item_table.title = self.title
        table.insert(self.item_table_stack, self.item_table)
        self:switchItemTable(item.text, item.sub_item_table)
    end
    return true
end

--[[
    default to call item callback
    override this function to handle the choice
--]]
function Menu:onMenuChoice(item)
    if item.callback then
        item.callback()
    end
    return true
end

--[[
override this function to process the item hold in a different manner
]]--
function Menu:onMenuHold(item)
    return true
end

function Menu:onNextPage()
    if self.onNext and self.page == self.page_num - 1 then
        self:onNext()
    end
    if self.page < self.page_num then
        self.page = self.page + 1
        self:updateItems()
    elseif self.page == self.page_num then
        -- on the last page, we check if we're on the last item
        local end_position = #self.item_table % self.perpage
        if end_position == 0 then
            end_position = self.perpage
        end
        if end_position ~= self.selected.y then
            self:updateItems(end_position)
        end
        self.page = 1
        self:updateItems()
    end
    return true
end

function Menu:onPrevPage()
    if self.page > 1 then
        self.page = self.page - 1
    elseif self.page == 1 then
        self.page = self.page_num
    end
    self:updateItems()
    return true
end

function Menu:onFirstPage()
    self.page = 1
    self:updateItems()
    return true
end

function Menu:onLastPage()
    self.page = self.page_num
    self:updateItems()
    return true
end

function Menu:onGotoPage(page)
    self.page = page
    self:updateItems()
    return true
end

function Menu:onSelect()
    local item = self.item_table[(self.page-1)*self.perpage+self.selected.y]
    if item then
        self:onMenuSelect(item)
    end
    return true
end

function Menu:onClose()
    local table_length = #self.item_table_stack
    if table_length == 0 then
        self:onCloseAllMenus()
    else
        -- back to parent menu
        local parent_item_table = table.remove(self.item_table_stack, table_length)
        self:switchItemTable(parent_item_table.title, parent_item_table)
    end
    return true
end

function Menu:onCloseAllMenus()
    UIManager:close(self)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

function Menu:onTapCloseAllMenus(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.dimen) then
        self:onCloseAllMenus()
        return true
    end
end

function Menu:onSwipe(arg, ges_ev)
    if ges_ev.direction == "west" then
        self:onNextPage()
    elseif ges_ev.direction == "east" then
        self:onPrevPage()
    end
end

function Menu.itemTableFromTouchMenu(t)
    local item_t = {}
    for k,v in pairs(t) do
        local item = { text = k }
        if v.callback then
            item.callback = v.callback
        else
            item.sub_item_table = v
        end
        table.insert(item_t, item)
    end
    return item_t
end

return Menu
