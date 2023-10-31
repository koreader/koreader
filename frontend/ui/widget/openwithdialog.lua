--[[--
This widget displays an open with dialog.
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckButton = require("ui/widget/checkbutton")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputDialog = require("ui/widget/inputdialog")
local LineWidget = require("ui/widget/linewidget")
local MovableContainer = require("ui/widget/container/movablecontainer")
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
    self.element_width = math.floor(self.width * 0.9)

    self.radio_button_table = RadioButtonTable:new{
        radio_buttons = self.radio_buttons,
        width = self.element_width,
        focused = true,
        scroll = false,
        parent = self,
        button_select_callback = function(btn)
            if btn.provider.disable_file then
                self._check_file_button:disable()
            else
                self._check_file_button:enable()
            end
            if btn.provider.disable_type then
                self._check_global_button:disable()
            else
                self._check_global_button:enable()
            end
        end
    }
    self.layout = {self.layout[#self.layout]} -- keep bottom buttons
    self:mergeLayoutInVertical(self.radio_button_table, #self.layout) -- before bottom buttons

    local vertical_span = VerticalSpan:new{
        width = Size.padding.large,
    }
    self.vgroup = VerticalGroup:new{
        align = "left",
        self.title_bar,
        vertical_span,
        CenterContainer:new{
            dimen = Geom:new{
                w = self.width,
                h = self.radio_button_table:getSize().h,
            },
            self.radio_button_table,
        },
        CenterContainer:new{
            dimen = Geom:new{
                w = self.width,
                h = Size.padding.large,
            },
            LineWidget:new{
                background = Blitbuffer.COLOR_DARK_GRAY,
                dimen = Geom:new{
                    w = self.element_width,
                    h = Size.line.medium,
                }
            },
        },
        vertical_span,
        CenterContainer:new{
            dimen = Geom:new{
                w = self.title_bar:getSize().w,
                h = self.button_table:getSize().h,
            },
            self.button_table,
        }
    }

    self._check_file_button = self._check_file_button or CheckButton:new{
        text = _("Always use this engine for this file"),
        enabled = not self.radio_button_table.checked_button.provider.disable_file,
        parent = self,
    }
    self:addWidget(self._check_file_button)
    self._check_global_button = self._check_global_button or CheckButton:new{
        text = _("Always use this engine for file type"),
        enabled = not self.radio_button_table.checked_button.provider.disable_type,
        parent = self,
    }
    self:addWidget(self._check_global_button)

    self.dialog_frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        self.vgroup,
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
    self:refocusWidget()
end

function OpenWithDialog:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.dialog_frame.dimen
    end)
end

return OpenWithDialog
