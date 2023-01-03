--[[--
Plugin for managing user patches

@module koplugin.patchmanager
--]]--

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")

if lfs.attributes(DataStorage:getDataDir() .. "/patches", "mode") ~= "directory" then
    return { disabled = true }
end

local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local userPatch = require("userpatch")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

local PatchManager = WidgetContainer:extend{
    name = "patchmanager",
}

function PatchManager:init()
    self.patch_dir = DataStorage:getDataDir() .. "/patches"
    self.disable_ext = ".disabled"
    self.patches = {}
    self:getAvailablePatches()
    self.ui.menu:registerToMainMenu(self)
end

function PatchManager:getAvailablePatches()
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
        table.sort(self.patches[priority], userPatch.sorting)
    end
end


function PatchManager:getSubMenu(priority)
    if #self.patches == 0 then
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
                UIManager:askForRestart(T(
                    _("Patches changed. %1\n"),
                    _("Current set of patches will be applied on next restart.")))
            end,
            hold_callback = function()
                local patch_fullpath = self.patch_dir .. "/" .. patch
                if self.ui.texteditor then
                    self.ui.texteditor.whenDoneFunc = function()
                        UIManager:askForRestart(T(
                            _("Patches might have changed. %1\n"),
                            _("Current set of patches will be applied on next restart.")))
                    end
                    self.ui.texteditor:checkEditFile(patch_fullpath, true)
                else -- fallback to show only the first lines
                    local message = ""
                    for line in io.lines(patch_fullpath) do
                        local line_start = line:sub(1, 1)
                        if line_start == " " or line_start == "-" then
                            message = message .. line .. "\n"
                        else
                            break
                        end
                    end

                    UIManager:show(InfoMessage:new{
                            text = message,
                            show_icon = false,
                            width = math.floor(Screen:getWidth() * 0.9),
                        })
                end
            end,
        })
    end
    return sub_menu
end

local about_text = _([[Patch manager allows to enable, disable or edit certain found user provided patches.

There are several hooks during KOReader execution, when those patches might be executed. The execution time of a patch can not be changed by patch manager, this has to be done by the patch author.

Patches are an experimental feature, so be careful what you do :-)]])

function PatchManager:addToMainMenu(menu_items)
    local sub_menu_text = {}
    sub_menu_text[tonumber(userPatch.early_once)] = _("On startup, only after update")
    sub_menu_text[tonumber(userPatch.early)] = _("On startup")
    sub_menu_text[tonumber(userPatch.late)] = _("After setup")
    sub_menu_text[tonumber(userPatch.before_exit)] = _("Before exit")
    sub_menu_text[tonumber(userPatch.on_exit)] = _("On exit")

    menu_items.patchmanager  = {
        text = _("Patch manager"),
        enabled_func = function()
            if #self.patches == 0 then
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
                text = _("About patch manager"),
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

    for i = tonumber(userPatch.early_once), tonumber(userPatch.on_exit) do
        if sub_menu_text[i] then
            table.insert(menu_items.patchmanager.sub_item_table,
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

return PatchManager
