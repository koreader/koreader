local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local ffiUtil = require("ffi/util")
local util = require("util")
local _ = require("gettext")
local Screen = require("device").screen

local SetDefaultsWidget = CenterContainer:extend{
    state = nil,
    menu_entries = nil,
    defaults_menu = nil,
    settings_changed = false,
}

function SetDefaultsWidget:init()
    -- This would usually be passed to the constructor, as CenterContainer's paintTo does *NOT* set/update self.dimen...
    self.dimen = Screen:getSize()
    -- Don't refresh the FM behind us. May leave stray bits of overflowed InputDialog behind in the popout border space.
    self.covers_fullscreen = true

    -- Then deal with our child widgets and our internal variables
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    self.dialog_width = math.floor(math.min(self.screen_width, self.screen_height) * 0.95)

    -- Keep track of what's an actual default, and what's been customized without actually touching the real data yet...
    self.state = {}
    local ro_defaults, rw_defaults = G_defaults:getDataTables()
    for k, v in pairs(ro_defaults) do
        self.state[k] = {
            idx = 1,
            value = v,
            custom = false,
            dirty = false,
            default_value = v,
        }
    end

    -- Slight bit of nastiness, because we have a couple of (string) defaults whose value is `nil` (#11679)...
    local nil_defaults = { "NETWORK_PROXY", "STARDICT_DATA_DIR" }
    for i, v in ipairs(nil_defaults) do
        self.state[v] = {
            idx = 1,
            value = nil,
            custom = false,
            dirty = false,
            default_value = nil,
        }
    end

    for k, v in pairs(rw_defaults) do
        -- Warn if we encounter a deprecated (or unknown) customized key
        if not self.state[k] then
            logger.warn("G_defaults: Found an unknown key in custom settings:", k)
            -- Should we just delete it?
            --G_defaults:delSetting(k)
        else
            self.state[k].value = v
            self.state[k].custom = true
        end
    end

    -- Prepare our menu entries
    self.menu_entries = {}

    local set_dialog
    local cancel_button = {
        text = _("Cancel"),
        id = "close",
        enabled = true,
        callback = function()
            UIManager:close(set_dialog)
        end,
    }

    local i = 0
    for k, t in ffiUtil.orderedPairs(self.state) do
        local v = t.value
        i = i + 1
        self.state[k].idx = i
        local value_type = type(v)
        if value_type == "boolean" then
            local editBoolean = function()
                set_dialog = InputDialog:new{
                    title = k,
                    input = tostring(self.state[k].value),
                    buttons = {
                        {
                            cancel_button,
                            {
                                text = _("Default"),
                                enabled = self.state[k].value ~= self.state[k].default_value,
                                callback = function()
                                    UIManager:close(set_dialog)
                                    self:update_menu_entry(k, self.state[k].default_value, type(self.state[k].default_value))
                                end
                            },
                            {
                                text = "true",
                                enabled = true,
                                callback = function()
                                    UIManager:close(set_dialog)
                                    self:update_menu_entry(k, true, value_type)
                                end
                            },
                            {
                                text = "false",
                                enabled = true,
                                callback = function()
                                    UIManager:close(set_dialog)
                                    self:update_menu_entry(k, false, value_type)
                                end
                            },
                        },
                    },
                    input_type = value_type,
                    width = self.dialog_width,
                }
                UIManager:show(set_dialog)
                set_dialog:onShowKeyboard()
            end

            table.insert(self.menu_entries, {
                text = self:gen_menu_entry(k, self.state[k].value, value_type),
                bold = self.state[k].custom,
                callback = editBoolean
            })
        elseif value_type == "table" then
            local editTable = function()
                local fields = {}
                for key, value in ffiUtil.orderedPairs(self.state[k].value) do
                    table.insert(fields, {
                        text = tostring(key) .. " = " .. tostring(value),
                        input_type = type(value),
                        hint = "",
                        padding = Screen:scaleBySize(2),
                        margin = Screen:scaleBySize(2),
                    })
                end
                set_dialog = MultiInputDialog:new{
                    title = k,
                    fields = fields,
                    buttons = {
                        {
                            cancel_button,
                            {
                                text = _("Default"),
                                enabled = not util.tableEquals(self.state[k].value, self.state[k].default_value),
                                callback = function()
                                    UIManager:close(set_dialog)
                                    self:update_menu_entry(k, self.state[k].default_value, type(self.state[k].default_value))
                                end
                            },
                            {
                                text = _("OK"),
                                enabled = true,
                                is_enter_default = true,
                                callback = function()
                                    UIManager:close(set_dialog)
                                    local new_table = {}
                                    for _, field in ipairs(set_dialog:getFields()) do
                                        local key, value = field:match("^[^= ]+"), field:match("[^= ]+$")
                                        new_table[tonumber(key) or key] = tonumber(value) or value
                                    end
                                    self:update_menu_entry(k, new_table, value_type)
                                end,
                            },
                        },
                    },
                    width = self.dialog_width,
                }
                UIManager:show(set_dialog)
                set_dialog:onShowKeyboard()
            end

            table.insert(self.menu_entries, {
                text = self:gen_menu_entry(k, self.state[k].value, value_type),
                bold = self.state[k].custom,
                callback = editTable
            })
        else
            local editNumStr = function()
                set_dialog = InputDialog:new{
                    title = k,
                    input = tostring(self.state[k].value),
                    buttons = {
                        {
                            cancel_button,
                            {
                                text = _("Default"),
                                enabled = self.state[k].value ~= self.state[k].default_value,
                                callback = function()
                                    UIManager:close(set_dialog)
                                    self:update_menu_entry(k, self.state[k].default_value, type(self.state[k].default_value))
                                end
                            },
                            {
                                text = _("OK"),
                                is_enter_default = true,
                                enabled = true,
                                callback = function()
                                    UIManager:close(set_dialog)
                                    local new_value = set_dialog:getInputValue()
                                    -- We have a few strings whose default value is nil, make sure they can properly swap between types
                                    if type(self.state[k].default_value) == "nil" then
                                        if new_value == "nil" then
                                            new_value = nil
                                            value_type = "nil"
                                        else
                                            value_type = "string"
                                        end
                                    end
                                    self:update_menu_entry(k, new_value, value_type)
                                end,
                            },
                        },
                    },
                    input_type = value_type,
                    width = self.dialog_width,
                }
                UIManager:show(set_dialog)
                set_dialog:onShowKeyboard()
            end

            table.insert(self.menu_entries, {
                text = self:gen_menu_entry(k, self.state[k].value, value_type),
                bold = self.state[k].custom,
                callback = editNumStr
            })
        end
    end

    -- Now that we have stuff to display, instantiate our Menu
    self.defaults_menu = Menu:new{
        width = self.screen_width - (Size.margin.fullscreen_popout * 2),
        height = self.screen_height - (Size.margin.fullscreen_popout * 2),
        show_parent = self,
        item_table = self.menu_entries,
        title = _("Defaults"),
    }
    -- Prevent menu from closing when editing a value
    function self.defaults_menu:onMenuSelect(item)
        item.callback()
    end
    self.defaults_menu.close_callback = function()
        logger.dbg("Closing defaults menu")
        self:saveBeforeExit()
        UIManager:close(self)
    end

    table.insert(self, self.defaults_menu)
end

function SetDefaultsWidget:gen_menu_entry(k, v, v_type)
    local ret = k .. " = "
    if v_type == "boolean" then
        return ret .. tostring(v)
    elseif v_type == "table" then
        return ret .. "{...}"
    elseif v_type == "nil" then
        return ret .. "nil"
    elseif tonumber(v) then
        return ret .. tostring(tonumber(v))
    else
        return ret .. "\"" .. tostring(v) .. "\""
    end
end

function SetDefaultsWidget:update_menu_entry(k, v, v_type)
    local idx = self.state[k].idx
    self.state[k].value = v
    self.state[k].dirty = true
    self.settings_changed = true
    self.menu_entries[idx].text = self:gen_menu_entry(k, v, v_type)
    if v_type == "nil" then
        self.menu_entries[idx].bold = v ~= self.state[k].default_value
    else
        if util.tableEquals(v, self.state[k].default_value) then
            self.menu_entries[idx].bold = false
        else
            self.menu_entries[idx].bold = true
        end
    end
    self.defaults_menu:switchItemTable(nil, self.menu_entries, idx)
end

function SetDefaultsWidget:saveSettings()
    -- Update dirty keys for real
    for k, t in pairs(self.state) do
        if t.dirty then
            G_defaults:saveSetting(k, t.value)
        end
    end

    -- And flush to disk
    G_defaults:flush()
    UIManager:show(InfoMessage:new{
        text = _("Default settings saved."),
    })
end

function SetDefaultsWidget:saveBeforeExit(callback)
    local save_text = _("Save and quit")
    if Device:canRestart() then
        save_text = _("Save and restart")
    end
    if self.settings_changed then
        UIManager:show(ConfirmBox:new{
            dismissable = false,
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
            end,
        })
    end
end

local SetDefaults = {}

function SetDefaults:ConfirmEdit()
    if not SetDefaults.EditConfirmed then
        UIManager:show(ConfirmBox:new{
            text = _("Some changes will not work until the next restart. Be careful; the wrong settings might crash KOReader!\nAre you sure you want to continue?"),
            ok_callback = function()
                SetDefaults.EditConfirmed = true
                UIManager:show(SetDefaultsWidget:new{})
            end,
        })
    else
        UIManager:show(SetDefaultsWidget:new{})
    end
end

return SetDefaults
