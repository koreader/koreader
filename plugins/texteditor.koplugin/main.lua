local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("ffi/util")
local _ = require("gettext")
local Screen = require("device").screen

local TextEditor = WidgetContainer:new{
    name = "TextEditor",
}

function TextEditor:init(file_path)
    if not file_path then
        self.context = ""
        self.file_path = ""
    else
        self.file_path = file_path
        self:readFile(file_path)
    end

    self.ui.menu:registerToMainMenu(self)
end

function TextEditor:start()
    local FileManager = require("apps/filemanager/filemanager")
    FileManager:onClose()
    self.input = InputDialog:new{
        title =  _("Basic text editor"),
        input = self.context,
        text_height = Screen:getHeight() * 0.5,
        width = self.width or Screen:getWidth(),
        input_type = "string",
        buttons = {{
        {
            text = _("Open"),
            callback = function()
                self:chooseFile()
            end,
        },
        {
            text = _("Save"),
            callback = function()
                self:saveFile(self.file_path)
            end,
        },{
            text = _("Cancel"),
            callback = function()
                self.context = ""
                self.file_path = ""
                UIManager:close(self.input)
            end,
        }, 
        {
            text = _("Pg_up"),
            is_enter_default = true,
            callback = function()
                UIManager:show(InfoMessage:new{
                    text = _("Not implemented. Please help if you know how.")
                })
                UIManager:forceRePaint()
            end,
        },
        {
            text = _("Pg_dwn"),
            is_enter_default = true,
            callback = function()
                UIManager:show(InfoMessage:new{
                    text = _("Not implemented. Please help if you know how.")
                })
                UIManager:forceRePaint()
            end,
        }

    }},
    }
    UIManager:show(self.input)
    self.input:onShowKeyboard()
end


function TextEditor:chooseFile()
    self.input:onClose()
    local path_chooser = PathChooser:new{
        title = _("Choose file. Hold to confirm"),
        height = Screen:getHeight(),
        path = util.realpath(DataStorage:getDataDir()),
        show_hidden = G_reader_settings:readSetting("show_hidden"),
        file_filter = function() return true end,
        onConfirm = function(file_path)
            logger.dbg("TextEditor: selected file_file_path " .. file_path )
            self.file_path = file_path
            self:readFile(self.file_path)
            self.input:onShowKeyboard()
        end
    }
    UIManager:show(path_chooser)     
end

function TextEditor:readFile(file_path)
    logger.dbg("TextEditor: reading file: " .. file_path)
    local file = assert(io.open(file_path, "rb"))
    if file then
        self.file_path = file_path
        self.context = file:read("*all")
        self.input:setInputText(self.context)
        file:close()
    else
        UIManager:show(InfoMessage:new{
            text = _("Failed to read file: " .. file_path)
        })
    end
    UIManager:forceRePaint()
end

function TextEditor:saveFile(file_path)
    logger.dbg("TextEditor: saving file: " .. file_path)
    local file = io.open(file_path, "w")
    if file then
        file:write(self.input:getInputText())
        file:close()
        UIManager:show(InfoMessage:new{
            text = _("Saved file: " .. file_path)
        })
    else
        UIManager:show(InfoMessage:new{
            text = _("Failed to save file: " .. file_path)
        })
    end
    UIManager:forceRePaint()
    UIManager:close(self.input)
    self.context = ""
    self.file_path = ""
end

function TextEditor:addToMainMenu(menu_items)
    menu_items.TextEditor = {
        text = _("Basic text editor"),
        callback = function()
            self:start()
        end,
    }
end

return TextEditor
