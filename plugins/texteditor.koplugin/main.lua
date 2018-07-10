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

local TextEditor = WidgetContainer:new{
    name = "TextEditor",
    file_path = util.realpath("basic-editor-test.txt"),
    context = "",
}

function TextEditor:init()
    self.ui.menu:registerToMainMenu(self)
    
end

function TextEditor:start()
    self.input = InputDialog:new{
        title =  _("Basic text editor"),
        input = self.context,
        text_height = Screen:getHeight() * 0.5,
        width = self.width or Screen:getWidth(),
        input_type = "string",
        buttons = {{{
            text = _("Save"),
            is_enter_default = true,
            callback = function()
                UIManager:close(self.input)
                self:saveFile(self.file_path)
            end,
        },{
            text = _("Cancel"),
            callback = function()
                UIManager:close(self.input)
            end,
        }, 
        {
            text = _("Open"),
            is_enter_default = true,
            callback = function()
                --TODO use filechoooser or filebrowser
                logger.dbg(self.file_path)
                self:readFile(self.file_path)
            end,
        },
        {
            text = _("Pg_up"),
            is_enter_default = true,
            callback = function()
                logger.dbg("not implemented. Help needed")
            end,
        },
        {
            text = _("Pg_dwn"),
            is_enter_default = true,
            callback = function()
                logger.dbg("not implemented. Help needed")
            end,
        }

    }},
    }
    UIManager:show(self.input)
    self.input:onShowKeyboard()
end


function TextEditor:saveFile(file_path)
    local file = io.open(file_path, "w")
    if file then
        file:write(self.context)
        file:close()
    else
        logger.warn("Failed to save to " .. file_path)
    end
end

function TextEditor:readFile(filepath)
    logger.dbg(filepath)
    local file = io.open(filepath, "r")
    local file = assert(io.open(filepath, "rb"))
    if file then
        self.file_path = filepath
        self.context = file:read("*all")
        self.input:setInputText(self.context)
        file:close()
    else
        logger.warn("Failed to read from" .. filepath)
    end

end

function TextEditor:addToMainMenu(menu_items)
    menu_items.TextEditor = {
        text = _("Basic Text editor"),
        callback = function()
            self:start()
        end,
    }
end

return TextEditor
