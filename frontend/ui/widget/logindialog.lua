local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local InputDialog = require("ui/widget/inputdialog")
local InputText = require("ui/widget/inputtext")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
local DEBUG = require("dbg")
local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")

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
        width = self.width * 0.9,
        focused = true,
        scroll = false,
        parent = self,
    }

    self.input_password = InputText:new{
        text = self.password,
        hint = self.password_hint,
        face = self.input_face,
        width = self.width * 0.9,
        text_type = "password",
        focused = false,
        scroll = false,
        parent = self,
    }

    self.dialog_frame = FrameContainer:new{
        radius = 8,
        bordersize = 3,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.title,
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

    self.input = self.input_username

    self[1] = CenterContainer:new{
        dimen = Geom:new{
            w = Screen:getWidth(),
            h = Screen:getHeight() - self.input:getKeyboardDimen().h,
        },
        self.dialog_frame,
    }
    UIManager.repaint_all = true
    UIManager.full_refresh = true
end

function LoginDialog:getCredential()
    local username = self.input_username:getText()
    local password = self.input_password:getText()
    return username, password
end

function LoginDialog:onSwitchFocus(inputbox)
    -- unfocus current inputbox
    self.input:unfocus()
    self.input:onCloseKeyboard()

    -- focus new inputbox
    self.input = inputbox
    self.input:focus()
    self.input:onShowKeyboard()

    UIManager:show(self)
end

return LoginDialog

