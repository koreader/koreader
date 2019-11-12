--[[--
This widget displays an keyboard layout dialog.
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckButton = require("ui/widget/checkbutton")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputDialog = require("ui/widget/inputdialog")
local Language = require("ui/language")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local RadioButtonTable = require("ui/widget/radiobuttontable")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = require("device").screen
local orderedPairs = require("ffi/util").orderedPairs

local KeyboardLayoutDialog = InputDialog:extend{}

function KeyboardLayoutDialog:init()
    -- init title in base class
    InputDialog.init(self)
    self.face = Font:getFace("cfont", 22)

    local buttons = {}
    local radio_buttons = {}

    for k, _ in orderedPairs(self.lang_to_keyboard_layout) do
        table.insert(radio_buttons, {
            {
            text = Language:getLanguageName(k),
            checked_func = function()
                return self.keyboard:getKeyboardLayout() == k
            end,
            layout = k,
            },
        })
    end

    table.insert(buttons, {
        {
            text = _("Cancel"),
            callback = function()
                UIManager:close(self.keyboard_layout_dialog)
            end,
        },
        {
            text = _("Chose language"),
            is_enter_default = true,
            callback = function()
                local layout = self.keyboard_layout_dialog.radio_button_table.checked_button.layout
                self.keyboard:setKeyboardLayout(layout)
                UIManager:close(self.keyboard_layout_dialog)
            end,
        },
    })
    
    radio_button_table = RadioButtonTable:new{
        radio_buttons = radio_buttons,
        focused = true,
        scroll = false,
        parent = self,
        face = self.face,
    }

    self.radio_button_table = RadioButtonTable:new{
        radio_buttons = self.radio_buttons,
        width = self.width * 0.9,
        focused = true,
        scroll = false,
        parent = self,
        face = self.face,
    }

    self.dialog_frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
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
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.title_bar:getSize().w,
                    h = Size.span.vertical_large*2,
                },
                LineWidget:new{
                    background = Blitbuffer.COLOR_DARK_GRAY,
                    dimen = Geom:new{
                        w = self.width * 0.9,
                        h = Size.line.medium,
                    }
                },
            },
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.title_bar:getSize().w,
                    h = self._always_file_toggle:getSize().h,
                },
                self._always_file_toggle,
            },
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.title_bar:getSize().w,
                    h = self._always_global_toggle:getSize().h,
                },
                self._always_global_toggle,
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

    self._input_widget = self.radio_button_table

    self[1] = CenterContainer:new{
        dimen = Geom:new{
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        },
        self.dialog_frame,
    }
end

function KeyboardLayoutDialog:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self[1][1].dimen
    end)
    return true
end

return KeyboardLayoutDialog
