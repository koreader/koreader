--[[--
This widget displays an open with dialog.
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckButton = require("ui/widget/checkbutton")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputDialog = require("ui/widget/inputdialog")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local RadioButtonTable = require("ui/widget/radiobuttontable")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = require("device").screen

local OpenWithDialog = InputDialog:extend{}

function OpenWithDialog:init()
    -- init title and buttons in base class
    InputDialog.init(self)
    self.face = Font:getFace("cfont", 22)

    self.radio_button_table = RadioButtonTable:new{
        radio_buttons = self.radio_buttons,
        width = self.width * 0.9,
        focused = true,
        scroll = false,
        parent = self,
        face = self.face,
    }

    self._check_file_button = self._check_file_button or CheckButton:new{
        text = _("Always use this engine for this file"),
        callback = function()
            if self._check_file_button.checked then
                self._check_file_button:unCheck()
            else
                self._check_file_button:check()
            end
        end,

        width = self.width * 0.9,
        max_width = self.width * 0.9 - 2*Size.border.window,
        height = self.height,
        face = self.face,

        parent = self,
    }
    self._always_file_toggle = LeftContainer:new{
        bordersize = 0,
        dimen = Geom:new{
            w = self.width * 0.9,
            h = self._check_file_button:getSize().h,
        },
        self._check_file_button,
    }

    self._check_global_button = self._check_global_button or CheckButton:new{
        text = _("Always use this engine for file type"),
        callback = function()
            if self._check_global_button.checked then
                self._check_global_button:unCheck()
            else
                self._check_global_button:check()
            end
        end,

        width = self.width * 0.9,
        max_width = self.width * 0.9 - 2*Size.border.window,
        height = self.height,
        face = self.face,

        parent = self,
    }
    self._always_global_toggle = LeftContainer:new{
        bordersize = 0,
        dimen = Geom:new{
            w = self.width * 0.9,
            h = self._check_global_button:getSize().h,
        },
        self._check_global_button,
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
                    background = Blitbuffer.COLOR_GREY,
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

function OpenWithDialog:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self[1][1].dimen
    end)
    return true
end

return OpenWithDialog
