
local ButtonTable = require("ui/widget/buttontable")
local Font = require("ui/font")
local InputText = require("ui/widget/inputtext")
local Screen = require("device").screen
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local _ = require("gettext")

local Terminal = WidgetContainer:new{
    name = "terminal",
}

function Terminal:init()
    self.execute = function()
    end

    self.clear = function()
    end

    self.save = function()
    end

    self.exit = function()
        UIManager:close(self.window)
    end

    self.group = VerticalGroup:new()

    self.buttons = ButtonTable:new{
        buttons = {{
            { text = _("Execute"), enabled = true, callback = self.execute },
            { text = _("Clear"), enabled = true, callback = self.clear },
            { text = _("Save to file"), enabled = true, callback = self.save },
            { text = _("Exit"), enabled = true, callback = self.exit },
        }},
        width = Screen:getWidth() * 0.8,
    }

    self.input = InputText:new{
        width = Screen:getWidth(),
        height = Screen:scaleBySize(16),
        face = Font:getFace("infont", 20),
        parent = self.group,
    }

    self.output = TextBoxWidget:new{
        text = "",
        width = Screen:getWidth(),
        height = Screen:scaleBySize(200),
        face = Font:getFace("infont", 20),
    }

    table.insert(self.group, self.output)
    table.insert(self.group, self.input)
    table.insert(self.group, self.buttons)

    self.window = WidgetContainer:new{
        align = "center",
        dimen = Screen:getSize(),
        self.group,
    }

    self.menuItem = {
        text = _("Terminal emulator"),
        callback = function()
            UIManager:show(self.window)
        end,
    }

    self.ui.menu:registerToMainMenu(self)
end

function Terminal:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, self.menuItem)
end

return Terminal
