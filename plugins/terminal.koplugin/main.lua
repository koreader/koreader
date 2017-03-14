
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputtext")
local ListView = require("ui/widget/listview")
local Screen = require("device").screen
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
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

function Terminal:start()
    local input = InputDialog:new{
        title =  _("Enter a command and press Execute"),
        text_height = Screen:getHeight() * 0.6,
        input_type = "string",
        buttons = {{{
            text = _("Cancel"),
            callback = function()
                UIManager:close(input)
            end
        }, {
            text = _("Execute"),
            callback = function()
                UIManager:close(input)
                UIManager:show(InfoMessage:new{
                    text = _("Executing ..."),
                    timeout = 0.1,
                })
                UIManager:forceRePaint()
                local std_out = io.popen(input:getInputText())

            end
        }}},
    }
    UIManager:show(input)
end

function Terminal:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, {
        text = _("Terminal emulator"),
        callback = function()
            self:start()
        end,
    })
end

return Terminal
