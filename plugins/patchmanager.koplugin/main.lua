--[[--
Plugin for automatic dimming of the frontlight after an idle period.

@module koplugin.PatchManager
--]]--

local DataStorage = require("datastorage")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local UserPatch = require("userpatch")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")

local Screen = Device.screen

local PatchManager = WidgetContainer:extend{
    name = "patchmanager",
    is_doc_only = false,
    patches = {}
}

function PatchManager:init()
    self.patch_dir = DataStorage:getDataDir() .. "/patches"
    self.disable_ext = ".disabled"
    self:getAvailablePatches()
    self.ui.menu:registerToMainMenu(self)
end

function PatchManager:getAvailablePatches()
    if lfs.attributes(self.patch_dir, "mode") ~= "directory" then
        self.patches = {}
        return
    end

    for priority = tonumber(UserPatch.early_once), tonumber(UserPatch.on_exit) do
        self.patches[priority] = {}
        for entry in lfs.dir(self.patch_dir) do
            local mode = lfs.attributes(self.patch_dir .. "/" .. entry, "mode")
            if entry and mode == "file" and entry:match("^" .. priority .. "%d*%-") then
                if entry:find(".lua", 1, true) then
                    -- exclude any non lua files
                    table.insert(self.patches[priority], entry)
                end
            end
        end
    end
end

function PatchManager:getSubMenu(priority)
    if priority < tonumber(UserPatch.early_once) or priority > tonumber(UserPatch.on_exit) then
        logger.err("PatchManager: BUG, wrong patch_level:", priority)
    end
    local sub_menu = {}
    if #self.patches == 0 then
        return {}
    end
    for i = 1, #self.patches[priority] do
        local patch_name = self.patches[priority][i]:sub(1, self.patches[priority][i]:find(".lua", 1, true) + 3)
        table.insert(sub_menu, {
            text = patch_name,
            checked_func = function()
                return self.patches[priority][i]:find("%.lua$") ~= nil
            end,
            callback = function()
                local is_patch_enabled = self.patches[priority][i]:find("%.lua$") ~= nil
                if is_patch_enabled then
                    local disabled_name = self.patches[priority][i] .. self.disable_ext
                    os.remove(self.patch_dir .. "/" .. disabled_name) -- remove a possible leftover (caused by user)
                    os.rename(self.patch_dir .. "/" .. self.patches[priority][i],
                              self.patch_dir .. "/" .. disabled_name)
                    self.patches[priority][i] = disabled_name
                else
                    local pos = self.patches[priority][i]:find(".lua", 1, true)
                    if pos then
                        local enabled_name = self.patches[priority][i]:sub(1, pos + (".lua"):len() - 1)
                        os.rename(self.patch_dir .. "/" .. self.patches[priority][i],
                                  self.patch_dir .. "/" .. enabled_name)
                        self.patches[priority][i] = enabled_name
                    end
                end
                UIManager:askForRestart(_("Patches changed. Current patch set will be applied on next restart."))
            end,
            hold_callback = function()
                local message = ""
                for line in io.lines(self.patch_dir .. "/" .. self.patches[priority][i]) do
                    print("xxx", line)
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
            end,
        })
    end
    return sub_menu
end

local about_text = _([[Patch manager allows to enable or disable certain found user provided patches.

There are several hooks during KOReader execution, when those patches might be executed. The execution time of a patch can not be changed by patch manager, this has to be done by the patch author.

Patches are an experimental feature, so be careful what you do :-)
]])

function PatchManager:addToMainMenu(menu_items)
    local sub_menu_text = {}
    sub_menu_text[tonumber(UserPatch.early_once)] = _("On startup, only after update")
    sub_menu_text[tonumber(UserPatch.early)] = _("On startup")
    sub_menu_text[tonumber(UserPatch.late)] = _("After setup")
    sub_menu_text[tonumber(UserPatch.before_exit)] = _("Before exit")
    sub_menu_text[tonumber(UserPatch.on_exit)] = _("On exit")

    menu_items.patchmanager  = {
        sorting_hint = "more_tools",
        text = _("Patch manager"),
        enabled_func = function()
            if #self.patches == 0 then
                return false
            end
            for i = tonumber(UserPatch.early_once), tonumber(UserPatch.on_exit) do
                if #self.patches[i] > 1 then
                    return true
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
            },
            {
                text = _("Patches executed"),
                enabled_func = function() return false end,
            },
        }
    }

    for i = tonumber(UserPatch.early_once), tonumber(UserPatch.on_exit) do
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
