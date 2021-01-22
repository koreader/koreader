local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local dump = require("dump")
local isAndroid, android = pcall(require, "android")
local logger = require("logger")
local util = require("ffi/util")
local _ = require("gettext")
local Screen = require("device").screen

local is_appimage = os.getenv("APPIMAGE")

local function getDefaultsPath()
    local defaults_path = DataStorage:getDataDir() .. "/defaults.lua"
    if isAndroid then
        defaults_path = android.dir .. "/defaults.lua"
    elseif is_appimage then
        defaults_path = "defaults.lua"
    end
    return defaults_path
end

local defaults_path = getDefaultsPath()
local persistent_defaults_path = DataStorage:getDataDir() .. "/defaults.persistent.lua"

local SetDefaults = InputContainer:new{
    defaults_name = {},
    defaults_value = {},
    results = {},
    defaults_menu = {},
    changed = {},
    settings_changed = false,
}

function SetDefaults:ConfirmEdit()
    if not SetDefaults.EditConfirmed then
        UIManager:show(ConfirmBox:new{
            text = _("Some changes will not work until the next restart. Be careful; the wrong settings might crash KOReader!\nAre you sure you want to continue?"),
            ok_callback = function()
                self.EditConfirmed = true
                self:init()
            end,
        })
    else
        self:init()
    end
end

function SetDefaults:init()
    self.results = {}

    local defaults = {}
    local load_defaults = loadfile(defaults_path)
    setfenv(load_defaults, defaults)
    load_defaults()

    local file = io.open(persistent_defaults_path, "r")
    if file ~= nil then
        file:close()
        load_defaults = loadfile(persistent_defaults_path)
        setfenv(load_defaults, defaults)
        load_defaults()
    end

    local idx = 1
    for n, v in util.orderedPairs(defaults) do
        self.defaults_name[idx] = n
        self.defaults_value[idx] = v
        idx = idx + 1
    end

    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
    }
    --- @fixme
    -- in this use case (an input dialog is closed and the menu container is
    -- opened immediately) we need to set the full screen dirty because
    -- otherwise only the input dialog part of the screen is refreshed.
    menu_container.onShow = function()
        UIManager:setDirty(nil, "partial")
    end

    self.defaults_menu = Menu:new{
        width = Screen:getWidth()-15,
        height = Screen:getHeight()-15,
        cface = Font:getFace("smallinfofont"),
        perpage = G_reader_settings:readSetting("items_per_page") or 14,
        show_parent = menu_container,
        _manager = self,
    }
    -- Prevent menu from closing when editing a value
    function self.defaults_menu:onMenuSelect(item)
        item.callback()
    end

    table.insert(menu_container, self.defaults_menu)
    self.defaults_menu.close_callback = function()
        logger.dbg("Closing defaults menu")
        self:saveBeforeExit()
        UIManager:close(menu_container)
    end

    local cancel_button = {
        text = _("Cancel"),
        enabled = true,
        callback = function()
            self:close()
        end,
    }

    for i=1, #self.defaults_name do
        self.changed[i] = false
        local setting_name = self.defaults_name[i]
        local setting_type = type(_G[setting_name])
        if setting_type == "boolean" then
            local editBoolean = function()
                self.set_dialog = InputDialog:new{
                    title = setting_name,
                    input = tostring(self.defaults_value[i]),
                    buttons = {
                        {
                            cancel_button,
                            {
                                text = "true",
                                enabled = true,
                                callback = function()
                                    self.defaults_value[i] = true
                                    _G[setting_name] = true
                                    self.settings_changed = true
                                    self.changed[i] = true
                                    self.results[i].text = self:build_setting(i)
                                    self:close()
                                    self.defaults_menu:switchItemTable("Defaults", self.results, i)
                                end
                            },
                            {
                                text = "false",
                                enabled = true,
                                callback = function()
                                    self.defaults_value[i] = false
                                    _G[setting_name] = false
                                    self.settings_changed = true
                                    self.changed[i] = true
                                    self.results[i].text = self:build_setting(i)
                                    self.defaults_menu:switchItemTable("Defaults", self.results, i)
                                    self:close()
                                end
                            },
                        },
                    },
                    input_type = setting_type,
                    width = math.floor(Screen:getWidth() * 0.95),
                }
                UIManager:show(self.set_dialog)
                self.set_dialog:onShowKeyboard()
            end

            table.insert(self.results, {
                text = self:build_setting(i),
                callback = editBoolean
            })
        elseif setting_type == "table" then
            local editTable = function()
                local fields = {}
                for k, v in util.orderedPairs(_G[setting_name]) do
                    table.insert(fields, {
                        text = tostring(k) .. " = " .. tostring(v),
                        hint = "",
                        padding = Screen:scaleBySize(2),
                        margin = Screen:scaleBySize(2),
                    })
                end
                self.set_dialog = MultiInputDialog:new{
                    title = setting_name,
                    fields = fields,
                    buttons = {
                        {
                            cancel_button,
                            {
                                text = _("OK"),
                                enabled = true,
                                is_enter_default = true,
                                callback = function()
                                    local new_table = {}
                                    for _, field in ipairs(MultiInputDialog:getFields()) do
                                        local key, value = field:match("^[^= ]+"), field:match("[^= ]+$")
                                        new_table[tonumber(key) or key] = tonumber(value) or value
                                    end
                                    _G[setting_name] = new_table

                                    self.defaults_value[i] = _G[setting_name]
                                    self.settings_changed = true
                                    self.changed[i] = true

                                    self.results[i].text = self:build_setting(i)

                                    self:close()
                                    self.defaults_menu:switchItemTable("Defaults", self.results, i)
                                end,
                            },
                        },
                    },
                    width = math.floor(Screen:getWidth() * 0.95),
                    height = math.floor(Screen:getHeight() * 0.2),
                }
                UIManager:show(self.set_dialog)
                self.set_dialog:onShowKeyboard()
            end

            table.insert(self.results, {
                text = self:build_setting(i),
                callback = editTable
            })
        else
            local editNumStr = function()
                self.set_dialog = InputDialog:new{
                    title = setting_name,
                    input = tostring(self.defaults_value[i]),
                    buttons = {
                        {
                            cancel_button,
                            {
                                text = _("OK"),
                                is_enter_default = true,
                                enabled = true,
                                callback = function()
                                    local new_value = self.set_dialog:getInputValue()
                                    if _G[setting_name] ~= new_value then
                                        _G[setting_name] = new_value
                                        self.defaults_value[i] = new_value
                                        self.settings_changed = true
                                        self.changed[i] = true
                                        self.results[i].text = self:build_setting(i)
                                    end
                                    self:close()
                                    self.defaults_menu:switchItemTable("Defaults", self.results, i)
                                end,
                            },
                        },
                    },
                    input_type = setting_type,
                    width = math.floor(Screen:getWidth() * 0.95),
                }
                UIManager:show(self.set_dialog)
                self.set_dialog:onShowKeyboard()
            end

            table.insert(self.results, {
                text = self:build_setting(i),
                callback = editNumStr
            })
        end
    end
    self.defaults_menu:switchItemTable("Defaults", self.results)
    UIManager:show(menu_container)
end

function SetDefaults:close()
    UIManager:close(self.set_dialog)
end

function SetDefaults:ConfirmSave()
    UIManager:show(ConfirmBox:new{
        text = _('Are you sure you want to save the settings to "defaults.persistent.lua"?'),
        ok_callback = function()
            self:saveSettings()
        end,
    })
end

function SetDefaults:build_setting(j)
    local setting_name = self.defaults_name[j]
    local ret = setting_name .. " = "
    if type(_G[setting_name]) == "boolean" then
        return ret .. tostring(self.defaults_value[j])
    elseif type(_G[setting_name]) == "table" then
        return ret .. "{...}"
    elseif tonumber(self.defaults_value[j]) then
        return ret .. tostring(tonumber(self.defaults_value[j]))
    else
        return ret .. "\"" .. tostring(self.defaults_value[j]) .. "\""
    end
end

function SetDefaults:saveSettings()
    self.results = {}
    local persisted_defaults = {}
    local file = io.open(persistent_defaults_path, "r")
    if file ~= nil then
        file:close()
        local load_defaults = loadfile(persistent_defaults_path)
        setfenv(load_defaults, persisted_defaults)
        load_defaults()
    end

    local checked = {}
    for j=1, #self.defaults_name do
        if not self.changed[j] then checked[j] = true end
    end

    -- load default value for defaults
    local defaults = {}
    local load_defaults = loadfile(defaults_path)
    setfenv(load_defaults, defaults)
    load_defaults()
    -- handle case "found in persistent" and changed, replace/delete it
    for k, v in pairs(persisted_defaults) do
        for j=1, #self.defaults_name do
            if not checked[j]
            and k == self.defaults_name[j] then
                -- remove from persist if value got reverted back to the
                -- default one
                if defaults[k] == self.defaults_value[j] then
                    persisted_defaults[k] = nil
                else
                    persisted_defaults[k] = self.defaults_value[j]
                end
                checked[j] = true
            end
        end
    end

    -- handle case "not in persistent and different in non-persistent", add to
    -- persistent
    for j=1, #self.defaults_name do
        if not checked[j] then
            persisted_defaults[self.defaults_name[j]] = self.defaults_value[j]
        end
    end

    file = io.open(persistent_defaults_path, "w")
    if file then
        file:write("-- For configuration changes that persists between updates\n")
        for k, v in pairs(persisted_defaults) do
            local line = {}
            table.insert(line, k)
            table.insert(line, " = ")
            table.insert(line, dump(v))
            table.insert(line, "\n")
            file:write(table.concat(line))
        end
        file:close()
        UIManager:show(InfoMessage:new{
            text = _("Default settings saved."),
        })
    end
    self.settings_changed = false
end

function SetDefaults:saveBeforeExit(callback)
    local save_text = _("Save and quit")
    if Device:canRestart() then
        save_text = _("Save and restart")
    end
    if self.settings_changed then
        UIManager:show(ConfirmBox:new{
            text = _("KOReader needs to be restarted to apply the new default settings."),
            ok_text = save_text,
            ok_callback = function()
                self.settings_changed = false
                self:saveSettings()
                if Device:canRestart() then
                    UIManager:restartKOReader()
                else
                    UIManager:quit()
                end
            end,
            cancel_text = _("Discard changes"),
            cancel_callback = function()
                logger.info("discard defaults")
                pcall(dofile, defaults_path)
                pcall(dofile, persistent_defaults_path)
                self.settings_changed = false
            end,
        })
    end
end

return SetDefaults
