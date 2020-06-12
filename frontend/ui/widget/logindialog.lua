--[[--
This widget displays a login dialog with a username and password.
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputDialog = require("ui/widget/inputdialog")
local InputText = require("ui/widget/inputtext")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local _ = require("gettext")
local Screen = require("device").screen

local LoginDialog = InputDialog:extend{
    username = "",
    username_hint = "username",
    password = "",
    password_hint = "password",
}

function LoginDialog:init()
    -- init title and buttons in base class
    InputDialog.init(self)
    self.input_username = InputText:new{
        text = self.username,
        hint = self.username_hint,
        face = self.input_face,
        width = math.floor(self.width * 0.9),
        focused = true,
        scroll = false,
        parent = self,
    }

    self.input_password = InputText:new{
        text = self.password,
        hint = self.password_hint,
        face = self.input_face,
        width = math.floor(self.width * 0.9),
        text_type = "password",
        focused = false,
        scroll = false,
        parent = self,
    }

    self.dialog_frame = FrameContainer:new{
        radius = Size.radius.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.title_widget,
            self.title_bar,
            -- username input
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.title_bar:getSize().w,
                    h = self.input_username:getSize().h,
                },
                self.input_username,
            },
            -- password input
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.title_bar:getSize().w,
                    h = self.input_password:getSize().h,
                },
                self.input_password,
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

    self._input_widget = self.input_username

    self[1] = CenterContainer:new{
        dimen = Geom:new{
            w = Screen:getWidth(),
            h = Screen:getHeight() - self._input_widget:getKeyboardDimen().h,
        },
        self.dialog_frame,
    }
end

function LoginDialog:getCredential()
    local username = self.input_username:getText()
    local password = self.input_password:getText()
    return username, password
end

function LoginDialog:onSwitchFocus(inputbox)
    -- unfocus current inputbox
    self._input_widget:unfocus()
    self._input_widget:onCloseKeyboard()
    -- focus new inputbox
    self._input_widget = inputbox
    self._input_widget:focus()
    self._input_widget:onShowKeyboard()
    UIManager:setDirty(self, "ui")
end

return LoginDialog

