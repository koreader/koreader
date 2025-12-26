local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FontList = require("fontlist")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local MovableContainer = require("ui/widget/container/movablecontainer")
local RadioButtonTable = require("ui/widget/radiobuttontable")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local Device = require("device")
local Screen = Device.screen

local FontChooser = FocusManager:extend{
    title = "",
    font_file = nil, -- current
    default_font_file = nil, -- is marked with a star
    keep_shown_on_apply = false,
    callback = nil, -- must be provided by the caller
    close_callback = nil, -- can be nil
}

function FontChooser:init()
    local s = Screen:getSize()
    local screen_w, screen_h = s.w, s.h

    self.ges_events.TapClose = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                w = screen_w,
                h = screen_h,
            },
        },
    }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    local width = math.floor(math.min(screen_w, screen_h) * 0.8)
    self.layout = {}

    local title_bar = TitleBar:new{
        width = width,
        title = self.title,
        align = "left",
        with_bottom_line = true,
        bottom_v_padding = 0,
        show_parent = self,
    }

    local radio_buttons = {} -- one column
    for font_file, font_info in pairs(FontList.fontinfo) do
        local name_text, name = self.getFontNameText(font_file)
        if self.default_font_file and self.default_font_file == font_file then
            name_text = name_text .. "  ★"
        end
        table.insert(radio_buttons, {{
            text = name_text,
            name = name,
            checked = font_file == self.font_file,
            provider = font_file,
            face = Font:getFace(font_file, 22),
            hold_callback = function()
                UIManager:show(InfoMessage:new{ text = font_file, show_icon = false })
            end,
        }})
    end
    if #radio_buttons > 1 then
        table.sort(radio_buttons, function(a, b)
            if a[1].name ~= b[1].name then
                return ffiUtil.strcoll(a[1].name, b[1].name)
            end
            return ffiUtil.strcoll(a[1].text, b[1].text)
        end)
    end

    local scroll_container_inner_width = width - ScrollableContainer:getScrollbarWidth()
    local radio_button_table = RadioButtonTable:new{
        radio_buttons = radio_buttons,
        width = scroll_container_inner_width - 2*Size.padding.large,
        button_single_line = true,
        no_sep = true,
        focused = true,
        parent = self,
        show_parent = self,
    }
    self:mergeLayoutInVertical(radio_button_table)

    local buttons = {{
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self)
            end,
        },
        {
            text = _("Set font"),
            is_enter_default = true,
            callback = function()
                if not self.keep_shown_on_apply then
                    UIManager:close(self)
                end
                self.callback(radio_button_table.checked_button.provider)
            end,
        },
    }}
    local button_table = ButtonTable:new{
        width = width - 2*Size.padding.default,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }
    self:mergeLayoutInVertical(button_table)

    self.radio_button_table_height = radio_button_table:getSize().h
    local max_radio_button_container_height = math.floor(screen_h*0.8
                    - title_bar:getHeight()
                    - Size.span.vertical_large*4 - button_table:getSize().h)
    if self.radio_button_table_height > max_radio_button_container_height then
        self.is_scrollable = true
        -- adjust scrollable container height to fit integer number of buttons
        local radio_button_height = radio_button_table.checked_button:getSize().h -- all buttons of the same height
        self.radio_buttons_per_page = math.floor(max_radio_button_container_height / radio_button_height)
        self.radio_button_container_height = self.radio_buttons_per_page * radio_button_height
    else
        self.radio_button_container_height = self.radio_button_table_height
    end

    self.cropping_widget = ScrollableContainer:new{
        dimen = Geom:new{
            w = width,
            h = self.radio_button_container_height,
        },
        show_parent = self,
        CenterContainer:new{
            dimen = Geom:new{
                w = scroll_container_inner_width,
                h = self.radio_button_table_height,
            },
            radio_button_table,
        },
    }
    self:scrollToCheckedButton()

    local dialog_frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            title_bar,
            VerticalSpan:new{
                width = Size.span.vertical_large*2,
            },
            self.cropping_widget,
            VerticalSpan:new{
                width = Size.span.vertical_large*2,
            },
            CenterContainer:new{
                dimen = Geom:new{
                    w = width,
                    h = button_table:getSize().h,
                },
                button_table,
            },
        },
    }

    self.movable = MovableContainer:new{
        dialog_frame,
    }
    self[1] = CenterContainer:new{
        dimen = Geom:new{
            w = screen_w,
            h = screen_h,
        },
        self.movable,
    }
end

function FontChooser:scrollToCheckedButton()
    if not self.is_scrollable then return end
    -- keep scrollable container "pagination"
    local radio_button_table = self.cropping_widget[1][1]
    local checked_button_previous_page_number =
        math.floor((radio_button_table.checked_button.row - 1) / self.radio_buttons_per_page)
    local checked_button_page_offset = checked_button_previous_page_number * self.radio_button_container_height
    local max_offset = self.radio_button_table_height - self.radio_button_container_height
    self.cropping_widget:setScrolledOffset({ x = 0, y = math.min(checked_button_page_offset, max_offset) })
end

function FontChooser.isFontRegistered(file)
    return file and FontList.fontinfo[file] and true or false
end

function FontChooser.getFontNameText(file)
    local font_info = FontList.fontinfo[file]
    local info = font_info and font_info[1]
    if info then
        local name = FontList:getLocalizedFontName(file, 0) or info.name
        local name_text = name
        if info.bold then
            name_text = name_text .. " " .. _("bold")
        end
        if info.italic then
            name_text = name_text .. " " .. _("italic")
        end
        return name_text, name
    end
end

function FontChooser:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.movable.dimen
    end)
    return true
end

function FontChooser:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.movable.dimen
    end)
end

function FontChooser:onTapClose(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.movable.dimen) then
        self:onClose()
    end
    return true
end

function FontChooser:onClose()
    UIManager:close(self)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

return FontChooser
