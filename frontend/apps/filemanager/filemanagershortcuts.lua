local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local util = require("ffi/util")
local _ = require("gettext")
local T = require("ffi/util").template

local FileManagerShortcuts = Menu:extend{
    width = Screen:getWidth(),
    height = Screen:getHeight(),
    no_title = false,
    parent = nil,
    has_close_button = true,
    is_popout = false,
    is_borderless = true,
}

function FileManagerShortcuts:init()
    self.item_table = self:genItemTableFromRoot()
    Menu.init(self)
end

function FileManagerShortcuts:genItemTableFromRoot()
    local item_table = {}
    local folder_shortcuts = G_reader_settings:readSetting("folder_shortcuts") or {}
    table.insert(item_table, {
        text = _("Add new folder shortcut"),
        callback = function()
            self:addNewFolder()
        end,
    })
    for _, item in ipairs(folder_shortcuts) do
        table.insert(item_table, {
            text = string.format("%s (%s)", item.text, item.folder),
            folder = item.folder,
            friendly_name = item.text,
            deletable = true,
            editable = true,
            callback = function()
                UIManager:close(self)
                self.goFolder(item.folder)
            end,
        })
    end
    return item_table
end

function FileManagerShortcuts:addNewFolder()
    local PathChooser = require("ui/widget/pathchooser")
    local path_chooser = PathChooser:new{
        select_directory = true,
        select_file = false,
        path = self.curr_path,
        onConfirm = function(path)
            local add_folder_input
            local friendly_name = util.basename(path) or _("my folder")
            add_folder_input = InputDialog:new{
                title = self.title,
                input = friendly_name,
                input_type = "text",
                description = T(_("Title for selected folder:\n%1"), path),
                buttons = {
                    {
                        {
                            text = _("Cancel"),
                            callback = function()
                                UIManager:close(add_folder_input)
                            end,
                        },
                        {
                            text = _("Add"),
                            is_enter_default = true,
                            callback = function()
                                self:addFolderFromInput(friendly_name, path)
                                UIManager:close(add_folder_input)
                            end,
                        },
                    }
                },
            }
            UIManager:show(add_folder_input)
            add_folder_input:onShowKeyboard()
        end
    }
    UIManager:show(path_chooser)
end

function FileManagerShortcuts:addFolderFromInput(friendly_name, folder)
    for __, item in ipairs(G_reader_settings:readSetting("folder_shortcuts") or {}) do
        if item.text == friendly_name and item.folder == folder then
            UIManager:show(InfoMessage:new{
                text = _("A shortcut to this folder already exists."),
            })
            return
        end
    end
    local folder_shortcuts = G_reader_settings:readSetting("folder_shortcuts") or {}
    table.insert(folder_shortcuts, {
        text = friendly_name,
        folder = folder,
    })
    G_reader_settings:saveSetting("folder_shortcuts", folder_shortcuts)
    self:init()
end

function FileManagerShortcuts:onMenuHold(item)
    if item.deletable or item.editable then
        local folder_shortcuts_dialog
        folder_shortcuts_dialog = ButtonDialog:new{
            buttons = {
                {
                    {
                        text = _("Edit"),
                        enabled = item.editable,
                        callback = function()
                            UIManager:close(folder_shortcuts_dialog)
                            self:editFolderShortcut(item)
                        end
                    },
                    {
                        text = _("Delete"),
                        enabled = item.deletable,
                        callback = function()
                            UIManager:close(folder_shortcuts_dialog)
                            self:deleteFolderShortcut(item)
                        end
                    },
                },
            }
        }
        UIManager:show(folder_shortcuts_dialog)
        return true
    end
end

function FileManagerShortcuts:editFolderShortcut(item)
    local edit_folder_input
    edit_folder_input = InputDialog:new {
        title = _("Edit friendly name"),
        input = item.friendly_name,
        input_type = "text",
        description = T(_("Rename title for selected folder:\n%1"), item.folder),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(edit_folder_input)
                    end,
                },
                {
                    text = _("Apply"),
                    is_enter_default = true,
                    callback = function()
                        self:renameFolderShortcut(item, edit_folder_input:getInputText())
                        UIManager:close(edit_folder_input)
                    end,
                },
            }
        },
    }
    UIManager:show(edit_folder_input)
    edit_folder_input:onShowKeyboard()
end

function FileManagerShortcuts:renameFolderShortcut(item, new_name)
    local folder_shortcuts = {}
    for _, element in ipairs(G_reader_settings:readSetting("folder_shortcuts") or {}) do
        if element.text == item.friendly_name and element.folder == item.folder then
            element.text = new_name
        end
        table.insert(folder_shortcuts, element)
    end
    G_reader_settings:saveSetting("folder_shortcuts", folder_shortcuts)
    self:init()
end

function FileManagerShortcuts:deleteFolderShortcut(item)
    local folder_shortcuts = {}
    for _, element in ipairs(G_reader_settings:readSetting("folder_shortcuts") or {}) do
        if element.text ~= item.friendly_name or element.folder ~= item.folder then
            table.insert(folder_shortcuts, element)
        end
    end
    G_reader_settings:saveSetting("folder_shortcuts", folder_shortcuts)
    self:init()
end

return FileManagerShortcuts
