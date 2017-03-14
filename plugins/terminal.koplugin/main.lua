
local DataStorage = require("datastorage")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local ListView = require("ui/widget/listview")
local KeyValuePage = require("ui/widget/keyvaluepage")
local Screen = require("device").screen
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local logger = require("logger")
local util = require("ffi/util")
local _ = require("gettext")

local Terminal = WidgetContainer:new{
    name = "terminal",
    dump_file = util.realpath(DataStorage:getDataDir()) .. "/terminal_output.txt",
}

function Terminal:init()
    self.ui.menu:registerToMainMenu(self)
end

function Terminal:start()
    local input = InputDialog:new{
        title =  _("Enter a command and press \"Execute\""),
        text_height = Screen:getHeight() * 0.6,
        input_type = "string",
        buttons = {{{
            text = _("Cancel"),
            enabled = true,
            callback = function()
                UIManager:close(input)
            end,
        }, {
            text = _("Execute"),
            enabled = true,
            callback = function()
                UIManager:close(input)
                self:execute(input:getInputText())
            end,
        },},},
    }
    input:onShowKeyboard()
    UIManager:show(input)
end

function Terminal:execute(command)
    UIManager:show(InfoMessage:new{
        text = _("Executing ..."),
        timeout = 0.1,
    })
    UIManager:forceRePaint()
    local std_out = io.popen(command)
    local entries = { command }
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
    table.insert(entries, _("Output will also be dumped to %1."))
    table.insert(entries, self.dump_file)
    UIManager:show(KeyValuePage:new{
        title = _("Command output"),
        cface = Font:getFace("ffont", 18),
        kv_pairs = entries,
    })
end

function Terminal:dump(entries)
    local content = table.concat(entries, "\n")
    local file = io.open(self.dump_file, "w")
    if file then
        file:write(content)
        file:close()
    else
        logger.warn(content)
    end
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
