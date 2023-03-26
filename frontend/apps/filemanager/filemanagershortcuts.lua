local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local util = require("ffi/util")
local _ = require("gettext")
local T = util.template

local FileManagerShortcuts = WidgetContainer:extend{
    folder_shortcuts = G_reader_settings:readSetting("folder_shortcuts", {}),
}

function FileManagerShortcuts:updateItemTable(select_callback)
    local item_table = {}
    for _, item in ipairs(self.folder_shortcuts) do
        table.insert(item_table, {
            text = string.format("%s (%s)", item.text, item.folder),
            folder = item.folder,
            friendly_name = item.text,
            deletable = true,
            editable = true,
            callback = function()
                UIManager:close(self.fm_bookmark)

                local folder = item.folder
                if folder ~= nil and lfs.attributes(folder, "mode") == "directory" then
                    if select_callback then
                        select_callback(folder)
                    else
                        if self.ui.file_chooser then
                            self.ui.file_chooser:changeToPath(folder)
                        else -- called from Reader
                            self.ui:onClose()
                            self.ui:showFileManager(folder .. "/")
                        end
                    end
                end
            end,
        })
    end

    table.sort(item_table, function(l, r)
        return l.text < r.text
    end)

    -- try to stay on current page
    local select_number

    if self.fm_bookmark.page and self.fm_bookmark.perpage and self.fm_bookmark.page > 0 then
        select_number = (self.fm_bookmark.page - 1) * self.fm_bookmark.perpage + 1
    end

    self.fm_bookmark:switchItemTable(nil,
                                     item_table, select_number)
end

function FileManagerShortcuts:addNewFolder()
    local PathChooser = require("ui/widget/pathchooser")
    local path_chooser = PathChooser:new{
        select_directory = true,
        select_file = false,
        path = self.fm_bookmark.curr_path,
        onConfirm = function(path)
            local add_folder_input
            local friendly_name = util.basename(path) or _("my folder")
            add_folder_input = InputDialog:new{
                title = _("Enter friendly name"),
                input = friendly_name,
                description = T(_("Title for selected folder:\n%1"), BD.dirpath(path)),
                buttons = {
                    {
                        {
                            text = _("Cancel"),
                            id = "close",
                            callback = function()
                                UIManager:close(add_folder_input)
                            end,
                        },
                        {
                            text = _("Add"),
                            is_enter_default = true,
                            callback = function()
                                self:addFolderFromInput(add_folder_input:getInputValue(), path)
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
    for __, item in ipairs(self.folder_shortcuts) do
        if item.text == friendly_name and item.folder == folder then
            UIManager:show(InfoMessage:new{
                text = _("A shortcut to this folder already exists."),
            })
            return
        end
    end
    table.insert(self.folder_shortcuts, {
        text = friendly_name,
        folder = folder,
    })
    self:updateItemTable()
end

function FileManagerShortcuts:onMenuHold(item)
    if item.deletable or item.editable then
        local folder_shortcuts_dialog
        folder_shortcuts_dialog = ButtonDialog:new{
            buttons = {
                {
                    {
                        text = _("Paste file"),
                        enabled = (self._manager.ui.file_chooser and self._manager.ui.clipboard) and true or false,
                        callback = function()
                            UIManager:close(folder_shortcuts_dialog)
                            self._manager.ui:pasteHere(item.folder)
                        end
                    },
                    {
                        text = _("Edit"),
                        enabled = item.editable,
                        callback = function()
                            UIManager:close(folder_shortcuts_dialog)
                            self._manager:editFolderShortcut(item)
                        end
                    },
                    {
                        text = _("Delete"),
                        enabled = item.deletable,
                        callback = function()
                            UIManager:close(folder_shortcuts_dialog)
                            self._manager:deleteFolderShortcut(item)
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
        description = T(_("Rename title for selected folder:\n%1"), BD.dirpath(item.folder)),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
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
    for _, element in ipairs(self.folder_shortcuts) do
        if element.text == item.friendly_name and element.folder == item.folder then
            element.text = new_name
        end
    end
    self:updateItemTable()
end

function FileManagerShortcuts:deleteFolderShortcut(item)
    for i = #self.folder_shortcuts, 1, -1 do
        local element = self.folder_shortcuts[i]
        if element.text == item.friendly_name and element.folder == item.folder then
            table.remove(self.folder_shortcuts, i)
        end
    end
    self:updateItemTable()
end

function FileManagerShortcuts:onSetDimensions(dimen)
    self.dimen = dimen
end

function FileManagerShortcuts:MenuSetRotationModeHandler(rotation)
    if rotation ~= nil and rotation ~= Screen:getRotationMode() then
        UIManager:close(self._manager.fm_bookmark)
        if self._manager.ui.view and self._manager.ui.view.onSetRotationMode then
            self._manager.ui.view:onSetRotationMode(rotation)
        elseif self._manager.ui.onSetRotationMode then
            self._manager.ui:onSetRotationMode(rotation)
        else
            Screen:setRotationMode(rotation)
        end
        self._manager:onShowFolderShortcutsDialog()
    end
    return true
end

function FileManagerShortcuts:onShowFolderShortcutsDialog(select_callback)
    self.fm_bookmark = Menu:new{
        title = _("Folder shortcuts"),
        show_parent = self.ui,
        no_title = false,
        parent = nil,
        is_popout = false,
        is_borderless = true,
        curr_path = self.ui.file_chooser and self.ui.file_chooser.path or self.ui:getLastDirFile(),
        onMenuHold = not select_callback and self.onMenuHold or nil,
        onSetRotationMode = self.MenuSetRotationModeHandler,
        title_bar_left_icon = not select_callback and "plus" or nil,
        onLeftButtonTap = function() self:addNewFolder() end,
        _manager = self,
    }

    self:updateItemTable(select_callback)
    UIManager:show(self.fm_bookmark)
end

return FileManagerShortcuts
