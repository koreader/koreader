local DataStorage = require("datastorage")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local TextViewer = require("ui/widget/textviewer")
local Trapper = require("ui/trapper")
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

function Terminal:onTerminalStart()
    self.input = InputDialog:new{
        title =  _("Enter a command and press \"Execute\""),
        input = self.command,
        para_direction_rtl = false, -- force LTR
        text_height = math.floor(Screen:getHeight() * 0.4),
        input_type = "string",
        -- allow multiple lines with commands:
        allow_newline = true,
        cursor_at_end = true,
        buttons = {{{
            text = _("Cancel"),
            callback = function()
                UIManager:close(self.input)
            end,
        }, {
            text = _("Execute"),
            callback = function()
                UIManager:close(self.input)
                Trapper:wrap(function()
                    self:execute()
                end)
            end,
        }}},
    }
    UIManager:show(self.input)
    self.input:onShowKeyboard()
end

function Terminal:execute()
    self.command = self.input:getInputText()
    local wait_msg = InfoMessage:new{
        text = _("Executing…"),
    }
    UIManager:show(wait_msg)
    local entries = { self.command }
    local command = self.command .. " 2>&1 ; echo" -- ensure we get stderr and output something
    local completed, result_str = Trapper:dismissablePopen(command, wait_msg)
    if completed then
        table.insert(entries, result_str)
        self:dump(entries)
        table.insert(entries, _("Output was also written to"))
        table.insert(entries, self.dump_file)
    else
        table.insert(entries, _("Execution canceled."))
    end
    UIManager:close(wait_msg)
    local viewer
    viewer = TextViewer:new {
        title = _("Command output"),
        text = table.concat(entries, "\n"),
        justified = false,
        text_face = Font:getFace("smallinfont"),
        -- support re-invoking the terminal with a button:
        buttons_table = {
            {
                {
                    text = _("Back"),
                    callback = function()
                        UIManager:close(viewer)
                        self:onTerminalStart()
                    end,
                },
                {
                    text = _("Close"),
                    callback = function()
                        UIManager:close(viewer)
                    end,
                },
            },
        },
    }
    UIManager:show(viewer)
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
        keep_menu_open = true,
        callback = function()
            self:onTerminalStart()
        end,
    }
end

return Terminal
