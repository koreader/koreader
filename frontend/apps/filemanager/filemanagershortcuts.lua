local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local PathChooser = require("ui/widget/pathchooser")
local Screenshoter = require("ui/widget/screenshoter")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")

local FileManagerShortcuts = WidgetContainer:extend{
    title = _("Folder shortcuts"),
    folder_shortcuts = G_reader_settings:readSetting("folder_shortcuts", {}),
    settings = G_reader_settings:readSetting("folder_shortcuts_settings", {}),

    -- system shortcuts
    providers_nb = 4, -- without plugins
    providers = {
        "home_dir",
        "download_dir",
        "screenshot_dir",
        "wikipedia_save_dir",
        -- plugin shortcuts
    },
    provider_props = {
        home_dir = {
            name = _("Home"),
            get = function()
                return G_reader_settings:readSetting("home_dir") or Device.home_dir
            end,
            set = function(path)
                G_reader_settings:saveSetting("home_dir", path)
            end,
        },
        download_dir = {
            name = _("Download folder"),
            get = function()
                return G_reader_settings:readSetting("download_dir") or G_reader_settings:readSetting("lastdir")
            end,
            set = function(path)
                G_reader_settings:saveSetting("download_dir", path)
            end,
        },
        screenshot_dir = {
            name = _("Screenshot folder"),
            get = function()
                return G_reader_settings:readSetting("screenshot_dir") or Screenshoter.default_dir
            end,
            set = function(path)
                G_reader_settings:saveSetting("screenshot_dir", path)
            end,
        },
        wikipedia_save_dir = {
            name = _("Wikipedia 'Save as EPUB' folder"),
            get = function()
                return G_reader_settings:readSetting("wikipedia_save_dir") or DictQuickLookup.getWikiSaveEpubDefaultDir()
            end,
            set = function(path)
                G_reader_settings:saveSetting("wikipedia_save_dir", path)
                if not util.pathExists(path) then
                    lfs.mkdir(path)
                end
            end,
        },
    },
}

function FileManagerShortcuts:refreshFileManager()
    local path_refreshed
    if self.ui.file_chooser then
        if self.settings.show_marker ~= false then
            self.ui.file_chooser:refreshPath()
            path_refreshed = true
        end
        if self.settings.show_name ~= false then
            self.ui:updateTitleBarPath()
        end
    end
    return path_refreshed
end

function FileManagerShortcuts.registerShortcut(shortcut) -- for plugins
    if not FileManagerShortcuts.provider_props[shortcut.provider] then
        shortcut.is_plugin = true
        table.insert(FileManagerShortcuts.providers, shortcut.provider)
        FileManagerShortcuts.provider_props[shortcut.provider] = shortcut
    end
end

function FileManagerShortcuts:updateShortcut(provider, new_folder) -- for all providers
    local old_folder = FileManagerShortcuts.provider_props[provider].get()
    if old_folder then
        self:_delShortcut(old_folder, provider)
        if new_folder then
            self:_addShortcut(new_folder, provider)
            return self:refreshFileManager()
        end
    end
end

function FileManagerShortcuts:_addShortcut(folder, provider, name)
    folder = folder:gsub("/$", "")
    local shortcut = self.folder_shortcuts[folder]
    if shortcut then
        if name then -- user shortcut
            shortcut.text = name
        else -- system shortcuts have no 'text' field
            shortcut.providers = shortcut.providers or {}
            shortcut.providers[provider] = true
        end
    else -- new
        self.folder_shortcuts[folder] = { time = os.time() }
        if name then
            self.folder_shortcuts[folder].text = name
        else
            self.folder_shortcuts[folder].providers = { [provider] = true }
        end
    end
end

function FileManagerShortcuts:_delShortcut(folder, provider)
    folder = folder:gsub("/$", "")
    local shortcut = self.folder_shortcuts[folder]
    if shortcut then
        if provider then
            if shortcut.providers then
                shortcut.providers[provider] = nil
                if not next(shortcut.providers) then
                    shortcut.providers = nil
                end
            end
        else -- user shortcut
            shortcut.text = nil
        end
        if shortcut.text == nil and shortcut.providers == nil then
            self.folder_shortcuts[folder] = nil
        end
    end
end

function FileManagerShortcuts:getShortcutFullName(folder)
    if self.settings.show_name == false then return end
    -- a folder may be linked to one user shortcut and several system shortcuts
    local shortcut = self.folder_shortcuts[folder]
    if shortcut then
        local text = shortcut.text
        if shortcut.providers then
            local t = { text }
            for _, provider in ipairs(FileManagerShortcuts.providers) do -- keep order
                if shortcut.providers[provider] then
                    table.insert(t, FileManagerShortcuts.provider_props[provider].name)
                end
            end
            text = table.concat(t, " | ")
        end
        return text and "☆ " .. text
    end
end

function FileManagerShortcuts:hasFolderShortcut(folder, for_marker)
    if for_marker and self.settings.show_marker == false then
        return false
    end
    local shortcut = self.folder_shortcuts[folder]
    return shortcut and shortcut.text and true or false -- user shortcuts only
end

function FileManagerShortcuts:updateItemsByPath(old_path, new_path)
    -- used on renaming/moving/deleting folders in the file browser
    -- if old_path == nil then remove the shortcut and system folder in settings
    -- update shortcuts
    local seen = {}
    for old_folder, shortcut in pairs(self.folder_shortcuts) do
        if not seen[old_folder] then
            local new_folder, count = old_folder:gsub(old_path or new_path, new_path)
            if count > 0 then
                self.folder_shortcuts[old_folder] = nil
                if old_path then
                    self.folder_shortcuts[new_folder] = shortcut
                    seen[new_folder] = true
                end
            end
        end
    end
    -- also update system folders in settings
    for _, prop in pairs(FileManagerShortcuts.provider_props) do
        if prop.set then
            local old_folder = prop.get()
            if old_folder then
                local new_folder, count = old_folder:gsub(old_path or new_path, new_path)
                if count > 0 then
                    prop.set(old_path and new_folder)
                end
            end
        end
    end
end

-- shortcut list

function FileManagerShortcuts:onShowFolderShortcutsDialog(select_callback)
    self.shortcuts_menu = Menu:new{
        title = self.title,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        select_callback = select_callback, -- called from PathChooser titlebar left button
        title_bar_fm_style = true,
        title_bar_left_icon = not select_callback and "plus" or nil,
        onLeftButtonTap = function() self:addShortcut() end,
        onLeftButtonHold = function() self:showMenu() end,
        onMenuChoice = self.onMenuChoice,
        onMenuHold = not select_callback and self.onMenuHold or nil,
        _manager = self,
        _recreate_func = function() self:onShowFolderShortcutsDialog(select_callback) end,
    }
    self.shortcuts_menu.close_callback = function()
        UIManager:close(self.shortcuts_menu)
        if self.fm_updated then
            self:refreshFileManager()
            self.fm_updated = nil
        end
        self.shortcuts_menu = nil
    end
    self:updateItemTable()
    UIManager:show(self.shortcuts_menu)
end

function FileManagerShortcuts:updateItemTable()
    local item_table = {}
    for folder, shortcut in pairs(self.folder_shortcuts) do
        if shortcut.text then -- user shortcut
            local name = shortcut.text
            table.insert(item_table, {
                text = self.settings.show_path == false and name or string.format("%s (%s)", name, BD.dirpath(folder)),
                folder = folder,
                name = name,
            })
        end
        if shortcut.providers then
            for provider in pairs(shortcut.providers) do
                local provider_props = FileManagerShortcuts.provider_props[provider]
                if provider_props then
                    table.insert(item_table, {
                        text = provider_props.name,
                        folder = folder,
                        name = provider_props.name,
                        provider = provider,
                        mandatory = self.settings.show_type ~= false and (provider == "home_dir" and "\u{f015}" -- 'home'
                            or (provider_props.is_plugin and "\u{E20F}" or "\u{F013}")), -- 'tools' or 'cog'
                    })
                end
            end
        end
    end
    if #item_table > 1 then
        table.sort(item_table, function(a, b)
            if (not a.provider) ~= (not b.provider) then
                return a.provider -- system shortcuts first
            end
            return ffiUtil.strcoll(a.text, b.text)
        end)
    end
    self.shortcuts_menu:switchItemTable(nil, item_table, -1)
end

function FileManagerShortcuts:onMenuChoice(item)
    local folder = item.folder
    if lfs.attributes(folder, "mode") ~= "directory" then return end
    if self.select_callback then
        self.select_callback(folder)
    else
        self._manager.fm_updated = nil
        if self._manager.ui.file_chooser then
            self._manager.ui.file_chooser:changeToPath(folder)
        else -- called from Reader
            self._manager.ui:onClose()
            folder = folder:sub(-1) == "/" and folder or folder .. "/"
            self._manager.ui:showFileManager(folder)
        end
    end
end

function FileManagerShortcuts:onMenuHold(item)
    local folder, provider = item.folder, item.provider
    local dialog
    local buttons = {
        {
            {
                text = _("Remove shortcut"),
                callback = function()
                    UIManager:close(dialog)
                    self._manager:removeShortcut(folder, item)
                end,
            },
            {
                text = provider and _("Set folder") or _("Rename shortcut"),
                enabled = not provider or FileManagerShortcuts.provider_props[provider].set ~= nil,
                callback = function()
                    UIManager:close(dialog)
                    if provider then
                        self._manager:setProviderFolder(item)
                    else
                        self._manager:editShortcut(folder)
                    end
                end,
            },
        },
    }
    local ui = self._manager.ui
    if ui.file_chooser then
        if ui.clipboard then
            table.insert(buttons, {}) -- separator
            table.insert(buttons, {
                {
                    text = _("Paste to folder"),
                    callback = function()
                        UIManager:close(dialog)
                        ui:pasteFileFromClipboard(folder)
                    end,
                },
            })
        end
        if ui.selected_files then
            table.insert(buttons, {}) -- separator
            table.insert(buttons, {
                {
                    text = _("Copy selected files to folder"),
                    callback = function()
                        ui:showCopyMoveSelectedFilesDialog(function() UIManager:close(dialog) end, folder)
                    end,
                },
            })
            table.insert(buttons, {
                {
                    text = _("Move selected files to folder"),
                    callback = function()
                        ui.cutfile = true
                        ui:showCopyMoveSelectedFilesDialog(function() UIManager:close(dialog) end, folder)
                    end,
                },
            })
        end
    end
    dialog = ButtonDialog:new{
        title = item.name .. "\n" .. BD.dirpath(folder),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(dialog)
    return true
end

function FileManagerShortcuts:removeShortcut(folder, item)
    self:_delShortcut(folder, item and item.provider)
    if item then -- called from the shortcut list
        self.fm_updated = true
        table.remove(self.shortcuts_menu.item_table, item.idx)
        self.shortcuts_menu:updateItems(1, true)
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
                    if name then
                        item.text = new_name
                    else -- new
                        self:_addShortcut(folder, nil, new_name)
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
    local add_dialog
    local buttons = {
        {
            {
                text = _("Folder"),
                callback = function()
                    UIManager:close(add_dialog)
                    UIManager:show(PathChooser:new{
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
                    })
                end,
            },
        },
        {}, -- separator
    }
    for _, provider in ipairs(FileManagerShortcuts.providers) do
        if #buttons == FileManagerShortcuts.providers_nb + 2 then
            table.insert(buttons, {}) -- separator before plugin shortcuts
        end
        local folder = FileManagerShortcuts.provider_props[provider].get()
        table.insert(buttons, {
            {
                text = FileManagerShortcuts.provider_props[provider].name,
                enabled = folder ~= nil,
                callback = function()
                    UIManager:close(add_dialog)
                    local shortcut = self.folder_shortcuts[folder]
                    if not (shortcut and shortcut.providers and shortcut.providers[provider]) then
                        self:_addShortcut(folder, provider)
                        self.fm_updated = true
                        self:updateItemTable()
                    end
                end,
            },
        })
    end
    add_dialog = ButtonDialog:new{
        buttons = buttons,
    }
    UIManager:show(add_dialog)
end

function FileManagerShortcuts:setProviderFolder(item)
    local old_folder, provider = item.folder, item.provider
    UIManager:show(PathChooser:new{
        select_directory = true,
        select_file = false,
        path = old_folder,
        onConfirm = function(new_folder)
            if new_folder ~= old_folder then
                FileManagerShortcuts.provider_props[provider].set(new_folder)
                self:_delShortcut(old_folder, provider)
                self:_addShortcut(new_folder, provider)
                item.folder = new_folder
                self.fm_updated = true
            end
        end,
    })
end

function FileManagerShortcuts:showMenu()
    local function flip(a)
        if a ~= false then return false end
    end
    local menu_dialog
    local buttons = {
        {{
            text = _("Show marker in file list"),
            align = "left",
            checked_func = function()
                return self.settings.show_marker ~= false
            end,
            callback = function()
                self.settings.show_marker = flip(self.settings.show_marker)
                self.fm_updated = true
            end,
        }},
        {{
            text = _("Show shortcut name in subtitle"),
            align = "left",
            checked_func = function()
                return self.settings.show_name ~= false
            end,
            callback = function()
                self.settings.show_name = flip(self.settings.show_name)
                self.fm_updated = true
            end,
        }},
        {}, -- separator
        {{
            text = _("Show path in shortcut list"),
            align = "left",
            checked_func = function()
                return self.settings.show_path ~= false
            end,
            callback = function()
                self.settings.show_path = flip(self.settings.show_path)
                self:updateItemTable()
            end,
        }},
        {{
            text = _("Show type in shortcut list"),
            align = "left",
            checked_func = function()
                return self.settings.show_type ~= false
            end,
            callback = function()
                self.settings.show_type = flip(self.settings.show_type)
                self:updateItemTable()
            end,
        }},
    }
    menu_dialog = ButtonDialog:new{
        shrink_unneeded_width = true,
        buttons = buttons,
        anchor = function()
            return self.shortcuts_menu.title_bar.left_button.image.dimen
        end,
    }
    UIManager:show(menu_dialog)
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

return FileManagerShortcuts
