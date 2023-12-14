--[[--
Plugin for managing user patches

@module koplugin.patchmanagement
--]]--

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")

if lfs.attributes(DataStorage:getDataDir() .. "/patches", "mode") ~= "directory" then
    return { disabled = true }
end

local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local sort = require("sort")
local userPatch = require("userpatch")
local _ = require("gettext")
local Screen = Device.screen

local PatchManagement = WidgetContainer:extend{
    name = "patch_management",
}

function PatchManagement:init()
    self.patch_dir = DataStorage:getDataDir() .. "/patches"
    self.disable_ext = ".disabled"
    self.patches = nil
    self:getAvailablePatches()
    self.ui.menu:registerToMainMenu(self)
end

function PatchManagement:getAvailablePatches()
    self.patches = {}
    for priority = tonumber(userPatch.early_once), tonumber(userPatch.on_exit) do
        self.patches[priority] = {}
    end

    for entry in lfs.dir(self.patch_dir) do
        local mode = lfs.attributes(self.patch_dir .. "/" .. entry, "mode")
        if mode == "file" then
            for priority = tonumber(userPatch.early_once), tonumber(userPatch.on_exit) do
                if entry:match("^" .. priority .. "%d*%-") and entry:find(".lua", 1, true) then
                    -- only lua files, starting with "%d+%-"
                    table.insert(self.patches[priority], entry)
                    break
                end
            end
        end
    end

    for priority = tonumber(userPatch.early_once), tonumber(userPatch.on_exit) do
        table.sort(self.patches[priority], sort.natsort_cmp())
    end
end

function PatchManagement:getSubMenu(priority)
    if self.patches == nil then
        return {}
    end
    local function getExecutionStatus(patch_name)
        return userPatch.execution_status[patch_name] == false and " ⚠" or ""
    end
    local sub_menu = {}
    for i, patch in ipairs(self.patches[priority]) do
        local ext = ".lua"
        -- strip anything after ".lua" in patch_name
        local patch_name = patch
        patch_name = patch_name:sub(1, patch_name:find(ext, 1, true) + ext:len() - 1)
        table.insert(sub_menu, {
                text = patch_name .. getExecutionStatus(patch_name),
                checked_func = function()
                    return patch:find("%.lua$") ~= nil
                end,
                callback = function()
                    local extension_pos = patch:find(ext, 1, true)
                    if extension_pos then
                        local is_patch_enabled = extension_pos == patch:len() - (ext:len() - 1)
                        if is_patch_enabled then -- patch name ends with ".lua"
                            local disabled_name = patch .. self.disable_ext
                            os.rename(self.patch_dir .. "/" .. patch,
                                self.patch_dir .. "/" .. disabled_name)
                            patch = disabled_name
                        else -- patch name name contains ".lua"
                            local enabled_name = patch:sub(1, extension_pos + ext:len() - 1)
                            os.rename(self.patch_dir .. "/" .. patch,
                                self.patch_dir .. "/" .. enabled_name)
                            patch = enabled_name
                        end
                    end
                    UIManager:askForRestart(
                        _("Patches changed. Current set of patches will be applied on next restart."))
                end,
                hold_callback = function()
                    local patch_fullpath = self.patch_dir .. "/" .. patch
                    if self.ui.texteditor then
                        local function done_callback()
                            UIManager:askForRestart(
                                _("Patches might have changed. Current set of patches will be applied on next restart."))
                        end
                        self.ui.texteditor:quickEditFile(patch_fullpath, done_callback, false)
                    else
                        local file = io.open(patch_fullpath, "rb")
                        if not file then
                            return ""
                        end
                        local patch_content = file:read("*all")
                        file:close()

                        local textviewer
                        textviewer = TextViewer:new{
                            title = patch,
                            text = patch_content,
                            text_type = "code",
                        }
                        UIManager:show(textviewer)
                    end
                end,
            })
    end
    return sub_menu
end

local about_text = _([[Patch management allows enabling, disabling or editing user provided patches.

The runlevel and priority of a patch can not be modified here. This has to be done manually by renaming the patch prefix.

For more information about user patches, see
https://github.com/koreader/koreader/wiki/User-patches

Patches are an advanced feature, so be careful what you do!]])

function PatchManagement:addToMainMenu(menu_items)
    menu_items.patch_management  = {
        text = _("Patch management"),
        enabled_func = function()
            if self.patches == nil then
                return false
            end
            for i = tonumber(userPatch.early_once), tonumber(userPatch.on_exit) do
                if #self.patches[i] > 0 then
                    return true -- we have at least one patch in the patches folder
                end
            end
            return false
        end,
        sub_item_table = {
            {
                text = _("About patch management"),
                callback = function()
                    UIManager:show(InfoMessage:new{
                            text = about_text,
                            width = math.floor(Screen:getWidth() * 0.9),
                        })
                end,
                separator = true,
                keep_menu_open = true,
            },
            {
                text = _("Patches executed:"),
                enabled = false,
            },
        }
    }

    local sub_menu_text = {}
    sub_menu_text[tonumber(userPatch.early_once)] = _("On startup, only after update")
    sub_menu_text[tonumber(userPatch.early)] = _("On startup")
    sub_menu_text[tonumber(userPatch.late)] = _("After setup")
    sub_menu_text[tonumber(userPatch.before_exit)] = _("Before exit")
    sub_menu_text[tonumber(userPatch.on_exit)] = _("On exit")

    for i = tonumber(userPatch.early_once), tonumber(userPatch.on_exit) do
        if sub_menu_text[i] then
            table.insert(menu_items.patch_management.sub_item_table,
                {
                    text = sub_menu_text[i],
                    enabled_func = function()
                        return #self.patches[i] > 0
                    end,
                    sub_item_table = self:getSubMenu(i)
                })
        end
    end
end

return PatchManagement
