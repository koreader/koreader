--[[--
Plugin for managing user patches

@module koplugin.patchmanagement
--]]--

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")

local patch_dir = DataStorage:getDataDir() .. "/patches"
if lfs.attributes(patch_dir, "mode") ~= "directory" then
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
local T = require("ffi/util").template

local PatchManagement = WidgetContainer:extend{
    name = "patch_management",
    disable_ext = ".disabled",
    patches = nil,
}

local priority_first = tonumber(userPatch.early_once)
local priority_last  = tonumber(userPatch.on_exit)
local priorities = {
    [priority_first]                  = _("On startup, only after update"),
    [tonumber(userPatch.early)]       = _("On startup"),
    [tonumber(userPatch.late)]        = _("After setup"),
    [tonumber(userPatch.before_exit)] = _("Before exit"),
    [priority_last]                   = _("On exit"),
}

function PatchManagement:init()
    self.ui.menu:registerToMainMenu(self)
end

function PatchManagement:getAvailablePatches()
    self.patches = {}
    for priority = priority_first, priority_last do
        if priorities[priority] then
            self.patches[priority] = {}
        end
    end

    for entry in lfs.dir(patch_dir) do
        local mode = lfs.attributes(patch_dir .. "/" .. entry, "mode")
        if mode == "file" and entry:find(".lua", 1, true) then
            for priority = priority_first, priority_last do
                if priorities[priority] and entry:match("^" .. priority .. "%d*%-") then
                    -- only lua files, starting with "%d+%-"
                    table.insert(self.patches[priority], entry)
                    break
                end
            end
        end
    end

    for priority = priority_first, priority_last do
        if priorities[priority] and #self.patches[priority] > 1 then
            table.sort(self.patches[priority], sort.natsort_cmp())
        end
    end
end

function PatchManagement:getSubMenu(priority)
    local sub_menu = {}
    for i, patch in ipairs(self.patches[priority]) do
        local ext = ".lua"
        -- strip anything after ".lua" in patch_name
        local patch_name = patch:sub(1, patch:find(ext, 1, true) + ext:len() - 1)
        table.insert(sub_menu, {
            text = patch_name:sub(1,-5) .. (userPatch.execution_status[patch_name] == false and " ⚠" or ""),
            checked_func = function()
                return patch:find("%.lua$") ~= nil
            end,
            callback = function()
                local extension_pos = patch:find(ext, 1, true)
                if extension_pos then
                    local is_patch_enabled = extension_pos == patch:len() - (ext:len() - 1)
                    if is_patch_enabled then -- patch name ends with ".lua"
                        local disabled_name = patch .. self.disable_ext
                        os.rename(patch_dir .. "/" .. patch, patch_dir .. "/" .. disabled_name)
                        patch = disabled_name
                    else -- patch contains ".lua"
                        local enabled_name = patch:sub(1, extension_pos + ext:len() - 1)
                        os.rename(patch_dir .. "/" .. patch, patch_dir .. "/" .. enabled_name)
                        patch = enabled_name
                    end
                end
                UIManager:askForRestart(
                    _("Patches changed. Current set of patches will be applied on next restart."))
            end,
            hold_callback = function()
                local patch_fullpath = patch_dir .. "/" .. patch
                if self.ui.texteditor then
                    local function done_callback()
                        UIManager:askForRestart(
                            _("Patches might have changed. Current set of patches will be applied on next restart."))
                    end
                    self.ui.texteditor:quickEditFile(patch_fullpath, done_callback, false)
                else
                    TextViewer.openFile(patch_fullpath)
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
        sub_item_table_func = function()
            local sub_item_table = {
                {
                    text = _("About patch management"),
                    keep_menu_open = true,
                    callback = function()
                        UIManager:show(InfoMessage:new{
                            text = about_text,
                            width = math.floor(Screen:getWidth() * 0.9),
                        })
                    end,
                    separator = true,
                },
                {
                    text_func = function()
                        local count = 0
                        for _, status in pairs(userPatch.execution_status) do
                            if status then
                                count = count + 1
                            end
                        end
                        return T(_("Patches executed: %1"), count)
                    end,
                    keep_menu_open = true,
                    callback = function()
                        local txt = {}
                        for patch, status in pairs(userPatch.execution_status) do
                            if status then
                                table.insert(txt, patch:sub(1,-5))
                            end
                        end
                        if #txt > 0 then
                            table.sort(txt, sort.natsort_cmp())
                            UIManager:show(InfoMessage:new{
                                text = table.concat(txt, "\n"),
                                monospace_font = true,
                            })
                        end
                    end,
                    separator = true,
                },
            }

            self:getAvailablePatches()
            for priority = priority_first, priority_last do
                if priorities[priority] then
                    table.insert(sub_item_table, {
                        text = priorities[priority],
                        enabled_func = function()
                            return #self.patches[priority] > 0
                        end,
                        sub_item_table = self:getSubMenu(priority),
                    })
                end
            end

            return sub_item_table
        end,
    }
end

return PatchManagement
