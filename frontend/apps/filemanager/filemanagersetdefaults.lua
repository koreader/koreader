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
local ffiUtil = require("ffi/util")
local util = require("util")
local _ = require("gettext")
local Screen = require("device").screen

local SetDefaults = InputContainer:new{
    state = nil,
    menu_entries = nil,
    defaults_menu = nil,
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
    for k, v in pairs(rw_defaults) do
        self.state[k].value = v
        self.state[k].custom = true
    end

    -- For Menu
    self.menu_entries = {}

    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
        -- Don't refresh the FM behind us. May leave stray bits of overflowed InputDialog behind in the popout border space.
        covers_fullscreen = true,
    }
    -- NOTE: This is a faux widget, we never properly instantiate it,
    --       instead, we use the class object/module itself as a singleton.
    --       As such, we need to cleanup behind us to avoid leaving clutter in said object...
    menu_container.onCloseWidget = function(this)
        local super = getmetatable(this)
        if super.onCloseWidget then
            -- Call our super's method, if any
            super.onCloseWidget(this)
        end
        -- And then do our own cleanup
        self:dtor()
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
                                    self:update_menu_entry(k, self.state[k].default_value, value_type)
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
                                    self:update_menu_entry(k, self.state[k].default_value, value_type)
                                end
                            },
                            {
                                text = _("OK"),
                                enabled = true,
                                is_enter_default = true,
                                callback = function()
                                    UIManager:close(set_dialog)
                                    local new_table = {}
                                    for _, field in ipairs(MultiInputDialog:getFields()) do
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
                                    self:update_menu_entry(k, self.state[k].default_value, value_type)
                                end
                            },
                            {
                                text = _("OK"),
                                is_enter_default = true,
                                enabled = true,
                                callback = function()
                                    UIManager:close(set_dialog)
                                    local new_value = set_dialog:getInputValue()
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
    self.defaults_menu:switchItemTable("Defaults", self.menu_entries)
    UIManager:show(menu_container)
end

function SetDefaults:gen_menu_entry(k, v, v_type)
    local ret = k .. " = "
    if v_type == "boolean" then
        return ret .. tostring(v)
    elseif v_type == "table" then
        return ret .. "{...}"
    elseif tonumber(v) then
        return ret .. tostring(tonumber(v))
    else
        return ret .. "\"" .. tostring(v) .. "\""
    end
end

function SetDefaults:update_menu_entry(k, v, v_type)
    local idx = self.state[k].idx
    self.state[k].value = v
    self.state[k].dirty = true
    self.settings_changed = true
    self.menu_entries[idx].text = self:gen_menu_entry(k, v, v_type)
    if util.tableEquals(v, self.state[k].default_value) then
        self.menu_entries[idx].bold = false
    else
        self.menu_entries[idx].bold = true
    end
    self.defaults_menu:switchItemTable("Defaults", self.menu_entries, idx)
end

function SetDefaults:saveSettings()
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

function SetDefaults:dtor()
    self.state = nil
    self.menu_entries = nil
    self.defaults_menu = nil
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

return SetDefaults
