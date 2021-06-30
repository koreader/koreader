--[[--
This widget displays a keyboard layout dialog.
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local FFIUtil = require("ffi/util")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Language = require("ui/language")
local LineWidget = require("ui/widget/linewidget")
local MovableContainer = require("ui/widget/container/movablecontainer")
local RadioButtonTable = require("ui/widget/radiobuttontable")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = require("device").screen

local KeyboardLayoutDialog = InputContainer:new{
    is_always_active = true,
    title = _("Keyboard layout"),
    modal = true,
    stop_events_propagation = true,
    width = math.floor(Screen:getWidth() * 0.8),
    face = Font:getFace("cfont", 22),
    title_face = Font:getFace("x_smalltfont"),
    title_padding = Size.padding.default,
    title_margin = Size.margin.title,
    button_padding = Size.padding.default,
    border_size = Size.border.window,
}


function KeyboardLayoutDialog:init()
    -- Title & description
    self.title_widget = FrameContainer:new{
        padding = self.title_padding,
        margin = self.title_margin,
        bordersize = 0,
        TextWidget:new{
            text = self.title,
            face = self.title_face,
            max_width = self.width,
        }
    }
    self.title_bar = LineWidget:new{
        dimen = Geom:new{
            w = self.width,
            h = Size.line.thick,
        }
    }

    local buttons = {}
    local radio_buttons = {}
    for k, _ in FFIUtil.orderedPairs(self.parent.keyboard.lang_to_keyboard_layout) do
        table.insert(radio_buttons, {
            {
            text = Language:getLanguageName(k),
            checked = self.parent.keyboard:getKeyboardLayout() == k,
            provider = k,
            },
        })
    end

    table.insert(buttons, {
        {
            text = _("Cancel"),
            callback = function()
                UIManager:close(self.parent.keyboard_layout_dialog)
            end,
        },
        {
            text = _("Switch to layout"),
            is_enter_default = true,
            callback = function()
                local provider = self.parent.keyboard_layout_dialog.radio_button_table.checked_button.provider
                self.parent.keyboard:setKeyboardLayout(provider)
                UIManager:close(self.parent.keyboard_layout_dialog)
            end,
        },
    })

    self.radio_button_table = RadioButtonTable:new{
        radio_buttons = radio_buttons,
        width = math.floor(self.width * 0.9),
        focused = true,
        scroll = false,
        parent = self,
        face = self.face,
    }

    -- Buttons Table
    self.button_table = ButtonTable:new{
        width = self.width - 2*self.button_padding,
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }

    self.dialog_frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            self.title_widget,
            self.title_bar,
            VerticalSpan:new{
                width = Size.span.vertical_large*2,
            },
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.title_bar:getSize().w,
                    h = self.radio_button_table:getSize().h,
                },
                self.radio_button_table,
            },
            VerticalSpan:new{
                width = Size.span.vertical_large*2,
            },
            -- buttons
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.title_bar:getSize().w,
                    h = self.button_table:getSize().h,
                },
                self.button_table,
            }
        }
    }

    self.movable = MovableContainer:new{
        self.dialog_frame,
    }
    self[1] = CenterContainer:new{
        dimen = Geom:new{
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        },
        self.movable,
    }
end


function KeyboardLayoutDialog:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.dialog_frame.dimen
    end)
end

function KeyboardLayoutDialog:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self[1][1].dimen
    end)
end

return KeyboardLayoutDialog
