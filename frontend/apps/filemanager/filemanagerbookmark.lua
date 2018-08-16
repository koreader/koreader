local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local util = require("ffi/util")
local _ = require("gettext")
local T = require("ffi/util").template

local FileManagerBookmark = Menu:extend{
    width = Screen:getWidth(),
    height = Screen:getHeight(),
    no_title = false,
    parent = nil,
    has_close_button = true,
    is_popout = false,
    is_borderless = true,
}

function FileManagerBookmark:init()
    self.item_table = self:genItemTableFromRoot()
    Menu.init(self)
end

function FileManagerBookmark:genItemTableFromRoot()
    local item_table = {}
    local favorites_folder = G_reader_settings:readSetting("fm_bookmark") or {}
    table.insert(item_table, {
        text = _("Add new fauvrite folder"),
        callback = function()
            self:addNewFolder()
        end,
    })
    for _, item in ipairs(favorites_folder) do
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

function FileManagerBookmark:addNewFolder()
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
                description = T(_("Please enter friendly name for your selected folder:\n%1"), path),
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

function FileManagerBookmark:addFolderFromInput(friendly_name, folder)
    for __, item in ipairs(G_reader_settings:readSetting("fm_bookmark") or {}) do
        if item.text == friendly_name and item.folder == folder then
            UIManager:show(InfoMessage:new{
                text = _("This folder already exist in favorites."),
            })
            return
        end
    end
    local favorites_folder = G_reader_settings:readSetting("fm_bookmark") or {}
    table.insert(favorites_folder, {
        text = friendly_name,
        folder = folder,
    })
    G_reader_settings:saveSetting("fm_bookmark", favorites_folder)
    self:init()
end

function FileManagerBookmark:onMenuHold(item)
    if item.deletable or item.editable then
        local favorites_folder_dialog
        favorites_folder_dialog = ButtonDialog:new{
            buttons = {
                {
                    {
                        text = _("Edit"),
                        enabled = item.editable,
                        callback = function()
                            UIManager:close(favorites_folder_dialog)
                            self:editFavoritesFolder(item)
                        end
                    },
                    {
                        text = _("Delete"),
                        enabled = item.deletable,
                        callback = function()
                            UIManager:close(favorites_folder_dialog)
                            self:deleteFavoritesFolder(item)
                        end
                    },
                },
            }
        }
        UIManager:show(favorites_folder_dialog)
        return true
    end
end

function FileManagerBookmark:editFavoritesFolder(item)
    local edit_folder_input
    edit_folder_input = InputDialog:new {
        title = _("Edit friendly name"),
        input = item.friendly_name,
        input_type = "text",
        description = T(_("Rename friendly name for your selected folder:\n%1"), item.folder),
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
                        self:renameFavoritesFolder(item, edit_folder_input:getInputText())
                        UIManager:close(edit_folder_input)
                    end,
                },
            }
        },
    }
    UIManager:show(edit_folder_input)
    edit_folder_input:onShowKeyboard()
end

function FileManagerBookmark:renameFavoritesFolder(item, new_name)
    local favorites_folder = {}
    for _, element in ipairs(G_reader_settings:readSetting("fm_bookmark") or {}) do
        if element.text == item.friendly_name and element.folder == item.folder then
            element.text = new_name
        end
        table.insert(favorites_folder, element)
    end
    G_reader_settings:saveSetting("fm_bookmark", favorites_folder)
    self:init()
end

function FileManagerBookmark:deleteFavoritesFolder(item)
    local favorites_folder = {}
    for _, element in ipairs(G_reader_settings:readSetting("fm_bookmark") or {}) do
        if element.text ~= item.friendly_name or element.folder ~= item.folder then
            table.insert(favorites_folder, element)
        end
    end
    G_reader_settings:saveSetting("fm_bookmark", favorites_folder)
    self:init()
end

return FileManagerBookmark
