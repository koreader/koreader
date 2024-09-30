local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

local FileManagerShortcuts = WidgetContainer:extend{
    title = _("Folder shortcuts"),
    folder_shortcuts = G_reader_settings:readSetting("folder_shortcuts", {}),
}

function FileManagerShortcuts:updateItemTable()
    local item_table = {}
    for folder, item in pairs(self.folder_shortcuts) do
        table.insert(item_table, {
            text = string.format("%s (%s)", item.text, folder),
            folder = folder,
            name = item.text,
        })
    end
    table.sort(item_table, function(l, r)
        return l.text < r.text
    end)
    self.shortcuts_menu:switchItemTable(nil, item_table, -1)
end

function FileManagerShortcuts:hasFolderShortcut(folder)
    return self.folder_shortcuts[folder] and true or false
end

function FileManagerShortcuts:onMenuChoice(item)
    local folder = item.folder
    if lfs.attributes(folder, "mode") ~= "directory" then return end
    if self.select_callback then
        self.select_callback(folder)
    else
        if self._manager.ui.file_chooser then
            self._manager.ui.file_chooser:changeToPath(folder)
        else -- called from Reader
            self._manager.ui:onClose()
            self._manager.ui:showFileManager(folder .. "/")
        end
    end
end

function FileManagerShortcuts:onMenuHold(item)
    local dialog
    local buttons = {
        {
            {
                text = _("Remove shortcut"),
                callback = function()
                    UIManager:close(dialog)
                    self._manager:removeShortcut(item.folder)
                end
            },
            {
                text = _("Rename shortcut"),
                callback = function()
                    UIManager:close(dialog)
                    self._manager:editShortcut(item.folder)
                end
            },
        },
        self._manager.ui.file_chooser and self._manager.ui.clipboard and {
            {
                text = _("Paste to folder"),
                callback = function()
                    UIManager:close(dialog)
                    self._manager.ui:pasteFileFromClipboard(item.folder)
                end
            },
        },
    }
    dialog = ButtonDialog:new{
        title = item.name .. "\n" .. BD.dirpath(item.folder),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(dialog)
    return true
end

function FileManagerShortcuts:removeShortcut(folder)
    self.folder_shortcuts[folder] = nil
    if self.shortcuts_menu then
        self.fm_updated = true
        self:updateItemTable()
    end
end

function FileManagerShortcuts:editShortcut(folder, post_callback)
    local item = self.folder_shortcuts[folder]
    local name = item and item.text -- rename
    local input_dialog
    input_dialog = InputDialog:new {
        title = _("Enter folder shortcut name"),
        input = name,
        description = BD.dirpath(folder),
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(input_dialog)
                end,
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    local new_name = input_dialog:getInputText()
                    if new_name == "" or new_name == name then return end
                    UIManager:close(input_dialog)
                    if item then
                        item.text = new_name
                    else
                        self.folder_shortcuts[folder] = { text = new_name, time = os.time() }
                        if post_callback then
                            post_callback()
                        end
                    end
                    if self.shortcuts_menu then
                        self.fm_updated = true
                        self:updateItemTable()
                    end
                end,
            },
        }},
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function FileManagerShortcuts:addShortcut()
    local PathChooser = require("ui/widget/pathchooser")
    local path_chooser = PathChooser:new{
        select_directory = true,
        select_file = false,
        path = self.ui.file_chooser and self.ui.file_chooser.path or self.ui:getLastDirFile(),
        onConfirm = function(path)
            if self:hasFolderShortcut(path) then
                UIManager:show(InfoMessage:new{
                    text = _("Shortcut already exists."),
                })
            else
                self:editShortcut(path)
            end
        end,
    }
    UIManager:show(path_chooser)
end

function FileManagerShortcuts:genShowFolderShortcutsButton(pre_callback)
    return {
        text = self.title,
        callback = function()
            pre_callback()
            self:onShowFolderShortcutsDialog()
        end,
    }
end

function FileManagerShortcuts:genAddRemoveShortcutButton(folder, pre_callback, post_callback)
    if self:hasFolderShortcut(folder) then
        return {
            text = _("Remove from folder shortcuts"),
            callback = function()
                pre_callback()
                self:removeShortcut(folder)
                post_callback()
            end,
        }
    else
        return {
            text = _("Add to folder shortcuts"),
            callback = function()
                pre_callback()
                self:editShortcut(folder, post_callback)
            end,
        }
    end
end

function FileManagerShortcuts:onSetDimensions(dimen)
    self.dimen = dimen
end

function FileManagerShortcuts:onShowFolderShortcutsDialog(select_callback)
    self.shortcuts_menu = Menu:new{
        title = self.title,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        select_callback = select_callback, -- called from PathChooser titlebar left button
        title_bar_left_icon = not select_callback and "plus" or nil,
        onLeftButtonTap = function() self:addShortcut() end,
        onMenuChoice = self.onMenuChoice,
        onMenuHold = not select_callback and self.onMenuHold or nil,
        _manager = self,
        _recreate_func = function() self:onShowFolderShortcutsDialog(select_callback) end,
    }
    self.shortcuts_menu.close_callback = function()
        UIManager:close(self.shortcuts_menu)
        if self.fm_updated then
            if self.ui.file_chooser then
                self.ui.file_chooser:refreshPath()
                self.ui:updateTitleBarPath()
            end
            self.fm_updated = nil
        end
        self.shortcuts_menu = nil
    end
    self:updateItemTable()
    UIManager:show(self.shortcuts_menu)
end

return FileManagerShortcuts
