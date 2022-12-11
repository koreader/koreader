local Geom = require("ui/geometry")
local IconWidget = require("ui/widget/iconwidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen

local ReaderFlipping = WidgetContainer:extend{
    orig_reflow_mode = 0,
}

function ReaderFlipping:init()
    local icon_size = Screen:scaleBySize(32)
    self.flipping_widget = IconWidget:new{
        icon = "book.opened",
        width = icon_size,
        height = icon_size,
    }
    -- Re-use this widget to show an indicator when we are in select mode
    icon_size = Screen:scaleBySize(36)
    self.select_mode_widget = IconWidget:new{
        icon = "texture-box",
        width = icon_size,
        height = icon_size,
        alpha = true,
    }
    self[1] = LeftContainer:new{
        dimen = Geom:new{w = Screen:getWidth(), h = self.flipping_widget:getSize().h},
        self.flipping_widget,
    }
    self:resetLayout()
end

function ReaderFlipping:resetLayout()
    local new_screen_width = Screen:getWidth()
    if new_screen_width == self._last_screen_width then return end
    self._last_screen_width = new_screen_width

    self[1].dimen.w = new_screen_width
end

function ReaderFlipping:paintTo(bb, x, y)
    if self.ui.highlight.select_mode then
        if self[1][1] ~= self.select_mode_widget then
            self[1][1] = self.select_mode_widget
        end
    else
        if self[1][1] ~= self.flipping_widget then
            self[1][1] = self.flipping_widget
        end
    end
    WidgetContainer.paintTo(self, bb, x, y)
end

return ReaderFlipping
