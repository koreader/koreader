local DataStorage = require("datastorage")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("ffi/util")
local _ = require("gettext")
local Screen = require("device").screen

local Terminal = WidgetContainer:new{
    name = "terminal",
    dump_file = util.realpath(DataStorage:getDataDir()) .. "/terminal_output.txt",
    command = "",
}

function Terminal:init()
    self.ui.menu:registerToMainMenu(self)
end

function Terminal:start()
    self.input = InputDialog:new{
        title =  _("Enter a command and press \"Execute\""),
        input = self.command,
        text_height = Screen:getHeight() * 0.4,
        input_type = "string",
        buttons = {{{
            text = _("Cancel"),
            callback = function()
                UIManager:close(self.input)
            end,
        }, {
            text = _("Execute"),
            is_enter_default = true,
            callback = function()
                UIManager:close(self.input)
                self:execute()
            end,
        }}},
    }
    self.input:onShowKeyboard()
    UIManager:show(self.input)
end

function Terminal:execute()
    self.command = self.input:getInputText()
    UIManager:show(InfoMessage:new{
        text = _("Executing…"),
        timeout = 0.1,
    })
    UIManager:forceRePaint()
    local std_out = io.popen(self.command)
    local entries = { self.command }
    if std_out then
        while true do
            local line = std_out:read()
            if line == nil then break end
            table.insert(entries, line)
        end
        std_out:close()
    else
        table.insert(entries, _("Failed to execute command."))
    end
    self:dump(entries)
    table.insert(entries, _("Output will also be written to"))
    table.insert(entries, self.dump_file)
    UIManager:show(InfoMessage:new{
        cface = Font:getFace("xx_smallinfofont"),
        text = _("Command output\n") .. table.concat(entries, "\n"),
        show_icon = false,
        width = Screen:getWidth() * 0.8,
        height = Screen:getHeight() * 0.8,
    })
end

function Terminal:dump(entries)
    local content = table.concat(entries, "\n")
    local file = io.open(self.dump_file, "w")
    if file then
        file:write(content)
        file:close()
    else
        logger.warn("Failed to dump terminal output " .. content .. " to " .. self.dump_file)
    end
end

function Terminal:addToMainMenu(menu_items)
    menu_items.terminal = {
        text = _("Terminal emulator"),
        callback = function()
            self:start()
        end,
    }
end

return Terminal
