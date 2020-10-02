-- overview of available modules: http://koreader.rocks/doc/index.html
local ButtonDialog = require("ui/widget/buttondialog")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local DeveloperTools = WidgetContainer:new{
    name = "developertools",
}

function DeveloperTools:init()
    self.ui.menu:registerToMainMenu(self)
end

function DeveloperTools:onShowDeveloperTools()
    local tools_dialog
    local buttons = {
        {
            {
                text = _("Terminal"),
                callback = function()
                    --UIManager:close(tools_dialog)
                    self.ui:handleEvent(Event:new("TerminalStart"))
                end
            },
            {
                text = "Crash.log",
                callback = function()
                    --UIManager:close(tools_dialog)
                    -- points to crash.log viewer:
                    self.ui:handleEvent(Event:new("ShowCrashlog"))
                end
            },
        },
    }
    tools_dialog = ButtonDialog:new {
        buttons = buttons
    }
    UIManager:show(tools_dialog)
end

function DeveloperTools:addToMainMenu(menu_items)
    menu_items.developertools = {
        text = _("Developer tools"),
        callback = function()
            self:onShowDeveloperTools()
        end
    }
end

return DeveloperTools
