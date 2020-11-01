--[[

sample plugin that showcases how to use the log viewer,
with some extra buttons that do custom stuff

]]  

local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

-- a sample function that excludes lines that don't match a tag
local function filterByTag(text, tag)
    local output
    for line in text:gmatch("([^\n]*)\n?") do
        if line:match(tag) then
            output = string.format("%s\n%s", output or "", line)
        end
    end
    return output
end

local LogTest = WidgetContainer:new{
    name = 'hello',
    is_doc_only = false,
}

function LogTest:init()
    self.ui.menu:registerToMainMenu(self)
end

function LogTest:getButtonsTable()
    local t = {}
    local addFilterButton = function(name, tag)
        table.insert(t, #t + 1, {
            text = name,
            callback = function()
                self.viewer:update(nil, nil, function(text)
                    return filterByTag(text, tag)
                end)
            end,
        })
    end
    addFilterButton("BIOS", "BIOS-e820")
    addFilterButton("VBOX", "virbr0")
    addFilterButton("MMAP", "reserve")
    addFilterButton("BASE", "base")
    addFilterButton("ACPI", "ACPI")
    table.insert(t, #t + 1, {
        text = "full log",
        callback = function()
            self.viewer:update()
        end,
    })
    return t
end

function LogTest:addToMainMenu(menu_items)
    self.viewer = require("ui/elements/logviewer"):new {
        file = "plugins/logtest.koplugin/dmesg.txt",
        disable_arrows = true,
        user_buttons = self:getButtonsTable(),
    }

    menu_items.test_logviewer = {
        text = _("Custom logviewer"),
        callback = function()
            if self.viewer then
                self.viewer:show()
            end
        end,
    }
end

return LogTest
