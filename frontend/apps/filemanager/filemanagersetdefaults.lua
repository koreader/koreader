local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util = require("ffi/util")
local _ = require("gettext")
local Screen = require("device").screen

local SetDefaults = InputContainer:new{
    defaults = {},
    state = {},
    results = {},
    defaults_menu = {},
    settings_changed = false,
}

function SetDefaults:ConfirmEdit()
    if not SetDefaults.EditConfirmed then
        UIManager:show(ConfirmBox:new{
            text = _("Some changes will not work until the next restart. Be careful; the wrong settings might crash KOReader!\nAre you sure you want to continue?"),
            ok_callback = function()
                SetDefaults.EditConfirmed = true
                self:init()
            end,
        })
    else
        self:init()
    end
end

function SetDefaults:init()
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    self.dialog_width = math.floor(math.min(self.screen_width, self.screen_height) * 0.95)

    -- Keep track of what's an actual default, and what's been customized without actually touching the real data yet...
    local ro_defaults = G_defaults:getROData()
    local rw_defaults = G_defaults:getRWData()
    for k, v in pairs(ro_defaults) do
        self.defaults[k] = v
        self.state[k] = { custom = false, dirty = false }
    end
    for k, v in pairs(rw_defaults) do
        self.defaults[k] = v
        self.state[k].custom = true
    end

    -- For Menu
    self.results = {}

    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
    }
    --- @fixme
    -- in this use case (an input dialog is closed and the menu container is
    -- opened immediately) we need to set the full screen dirty because
    -- otherwise only the input dialog part of the screen is refreshed.
    menu_container.onShow = function()
        UIManager:setDirty(nil, "ui")
    end

    self.defaults_menu = Menu:new{
        width = self.screen_width - (Size.margin.fullscreen_popout * 2),
        height = self.screen_height - (Size.margin.fullscreen_popout * 2),
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
        id = "close",
        enabled = true,
        callback = function()
            self:close()
        end,
    }

    local i = 0
    for k, v in util.orderedPairs(self.defaults) do
        i = i + 1
        self.state[k].idx = i
        local setting_type = type(v)
        if setting_type == "boolean" then
            local editBoolean = function()
                self.set_dialog = InputDialog:new{
                    title = k,
                    input = tostring(v),
                    buttons = {
                        {
                            cancel_button,
                            {
                                text = "true",
                                enabled = true,
                                callback = function()
                                    local idx = self.state[k].idx
                                    if v ~= true then
                                        self.defaults[k] = true
                                        self.state[k].dirty = true
                                        self.settings_changed = true
                                        self.results[idx].text = self:gen_menu_entry(k, self.defaults[k], setting_type)
                                        self.results[idx].bold = true
                                    end
                                    self:close()
                                    self.defaults_menu:switchItemTable("Defaults", self.results, idx)
                                end
                            },
                            {
                                text = "false",
                                enabled = true,
                                callback = function()
                                    local idx = self.state[k].idx
                                    if v ~= false then
                                        self.defaults[k] = false
                                        self.state[k].dirty = true
                                        self.settings_changed = true
                                        self.results[idx].text = self:gen_menu_entry(k, self.defaults[k], setting_type)
                                        self.results[idx].bold = true
                                    end
                                    self:close()
                                    self.defaults_menu:switchItemTable("Defaults", self.results, idx)
                                end
                            },
                        },
                    },
                    input_type = setting_type,
                    width = self.dialog_width,
                }
                UIManager:show(self.set_dialog)
                self.set_dialog:onShowKeyboard()
            end

            table.insert(self.results, {
                text = self:gen_menu_entry(k, self.defaults[k], setting_type),
                bold = self.state[k].custom,
                callback = editBoolean
            })
        elseif setting_type == "table" then
            local editTable = function()
                local fields = {}
                for key, value in util.orderedPairs(v) do
                    table.insert(fields, {
                        text = tostring(key) .. " = " .. tostring(value),
                        hint = "",
                        padding = Screen:scaleBySize(2),
                        margin = Screen:scaleBySize(2),
                    })
                end
                self.set_dialog = MultiInputDialog:new{
                    title = k,
                    fields = fields,
                    buttons = {
                        {
                            cancel_button,
                            {
                                text = _("OK"),
                                enabled = true,
                                is_enter_default = true,
                                callback = function()
                                    local idx = self.state[k].idx
                                    local new_table = {}
                                    for _, field in ipairs(MultiInputDialog:getFields()) do
                                        local key, value = field:match("^[^= ]+"), field:match("[^= ]+$")
                                        new_table[tonumber(key) or key] = tonumber(value) or value
                                    end
                                    -- Diffing tables would be annoying, so assume it was actually modified.
                                    self.defaults[k] = new_table
                                    self.state[k].dirty = true
                                    self.settings_changed = true
                                    self.results[idx].text = self:gen_menu_entry(k, self.defaults[k], setting_type)
                                    self.results[idx].bold = true
                                    self:close()
                                    self.defaults_menu:switchItemTable("Defaults", self.results, idx)
                                end,
                            },
                        },
                    },
                    width = self.dialog_width,
                }
                UIManager:show(self.set_dialog)
                self.set_dialog:onShowKeyboard()
            end

            table.insert(self.results, {
                text = self:gen_menu_entry(k, self.defaults[k], setting_type),
                bold = self.state[k].custom,
                callback = editTable
            })
        else
            local editNumStr = function()
                self.set_dialog = InputDialog:new{
                    title = k,
                    input = tostring(v),
                    buttons = {
                        {
                            cancel_button,
                            {
                                text = _("OK"),
                                is_enter_default = true,
                                enabled = true,
                                callback = function()
                                    local idx = self.state[k].idx
                                    local new_value = self.set_dialog:getInputValue()
                                    if v ~= new_value then
                                        self.defaults[k] = new_value
                                        self.state[k].dirty = true
                                        self.settings_changed = true
                                        self.results[idx].text = self:gen_menu_entry(k, self.defaults[k], setting_type)
                                        self.results[idx].bold = true
                                    end
                                    self:close()
                                    self.defaults_menu:switchItemTable("Defaults", self.results, idx)
                                end,
                            },
                        },
                    },
                    input_type = setting_type,
                    width = self.dialog_width,
                }
                UIManager:show(self.set_dialog)
                self.set_dialog:onShowKeyboard()
            end

            table.insert(self.results, {
                text = self:gen_menu_entry(k, self.defaults[k], setting_type),
                bold = self.state[k].custom,
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

function SetDefaults:gen_menu_entry(k, v, t)
    local ret = k .. " = "
    if t == "boolean" then
        return ret .. tostring(v)
    elseif t == "table" then
        return ret .. "{...}"
    elseif tonumber(v) then
        return ret .. tostring(tonumber(v))
    else
        return ret .. "\"" .. tostring(v) .. "\""
    end
end

function SetDefaults:saveSettings()
    self.results = {}

    -- Update dirty keys for real
    for k, v in pairs(self.defaults) do
        if self.state[k].dirty then
            G_defaults:saveSetting(k, v)
        end
    end

    -- And flush to disk
    G_defaults:flush()
    UIManager:show(InfoMessage:new{
        text = _("Default settings saved."),
    })
    self.settings_changed = false
    self.defaults = {}
    self.state = {}
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
                self.settings_changed = false
                self.defaults = {}
                self.state = {}
            end,
        })
    end
end

return SetDefaults
