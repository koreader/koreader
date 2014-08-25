local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local ConfirmBox = require("ui/widget/confirmbox")
local CenterContainer = require("ui/widget/container/centercontainer")
local Screen = require("ui/screen")
local Menu = require("ui/widget/menu")
local Font = require("ui/font")
local Util = require("ffi/util")

local SetDefaults = InputContainer:new{
    defaults_name = {},
    defaults_value = {},
    results = {},
    defaults_menu = {},
    already_read = false,
    changed = {}
}

local function settype(b,t)
    if t == "boolean" then
        if b == "false" then return false else return true end
    else
        return b
    end
end

local function getTableValues(t,dtap)
    local dummy = "{"
    for n,v in pairs(t) do
        if dtap:sub(1,4) == "DTAP" or dtap:sub(1,11) == "DDOUBLE_TAP" then
            dummy = dummy .. tostring(n) .. " = " .. tostring(v) .. ", "
        elseif tonumber(v) then
            dummy = dummy .. tostring(v) .. ", "
        else
            dummy = dummy .. "\"" .. tostring(v) .. "\", "
        end
    end
    dummy = dummy:sub(1,string.len(dummy) - 2) .. "}"
    return dummy
end

function SetDefaults:ConfirmEdit()
    if not SetDefaults.EditConfirmed then
        UIManager:show(ConfirmBox:new{
            text = _("Some changes will just work on the next restart. Wrong settings might crash Koreader! Continue?"),
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

    if not self.already_read then
        local i = 0
        for n,v in Util.orderedPairs(_G) do
            if (not string.find(tostring(v), "<")) and (not string.find(tostring(v), ": ")) and string.sub(n,1,1) ~= "_" and string.upper(n) == n and n ~= "LIBRARY_PATH" then
                i = i + 1
                self.defaults_name[i] = n
                self.defaults_value[i] = v
            end
            if string.find(tostring(v), "table: ") and string.upper(n) == n and n ~= "ARGV" and n ~= "_G" then
                i = i + 1
                self.defaults_name[i] = n
                self.defaults_value[i] = getTableValues(v,n)
            end
        end
        self.already_read = true
    end

    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
    }

    self.defaults_menu = Menu:new{
        width = Screen:getWidth()-15,
        height = Screen:getHeight()-15,
        cface = Font:getFace("cfont", 22),
        show_parent = menu_container,
        _manager = self,
    }
    table.insert(menu_container, self.defaults_menu)
    self.defaults_menu.close_callback = function()
        UIManager:close(menu_container)
    end

    for i=1,#self.defaults_name do
        self.changed[i] = false
        local settings_type = type(_G[self.defaults_name[i]])
        if settings_type == "boolean" then
            table.insert(self.results, {
                text = self:build_setting(i),
                callback = function()
                    self.set_dialog = InputDialog:new{
                        title = self.defaults_name[i] .. ":",
                        input = tostring(self.defaults_value[i]),
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    enabled = true,
                                    callback = function()
                                        self:close()
                                        UIManager:show(menu_container)
                                    end 
                                },
                                {
                                    text = "true",
                                    enabled = true,
                                    callback = function()
                                        self.defaults_value[i] = true
                                        _G[self.defaults_name[i]] = true
                                        settings_changed = true
                                        self.changed[i] = true
                                        self.results[i].text = self:build_setting(i)
                                        self:close()
                                        self.defaults_menu:swithItemTable("Defaults", self.results, i)
                                        UIManager:show(menu_container)
                                    end
                                },
                                {
                                    text = "false",
                                    enabled = true,
                                    callback = function()
                                        self.defaults_value[i] = false
                                        _G[self.defaults_name[i]] = false
                                        settings_changed = true
                                        self.changed[i] = true
                                        self.results[i].text = self:build_setting(i)
                                        self.defaults_menu:swithItemTable("Defaults", self.results, i)
                                        self:close()
                                        UIManager:show(menu_container)
                                    end
                                },
                            },
                        },
                        input_type = settings_type,
                        width = Screen:getWidth() * 0.95,
                        height = Screen:getHeight() * 0.2,
                    }
                    self.set_dialog:onShowKeyboard()
                    UIManager:show(self.set_dialog)
                end
            })
        else
            if type(_G[self.defaults_name[i]]) == "table" then
                table.insert(self.results, {
                    text = self:build_setting(i),
                    callback = function()
                        self.set_dialog = MultiInputDialog:new{
                            title = self.defaults_name[i] .. ":",
                            field = _G[self.defaults_name[i]],
                            buttons = {
                                {
                                    {
                                        text = _("Cancel"),
                                        enabled = true,
                                        callback = function()
                                            self:close()
                                            UIManager:show(menu_container)
                                        end,
                                    },
                                    {
                                        text = _("OK"),
                                        enabled = true,
                                        callback = function()

                                            _G[self.defaults_name[i]] = MultiInputDialog:getCredential()

                                            self.defaults_value[i] = "{"
                                            for k,v in Util.orderedPairs(_G[self.defaults_name[i]]) do
                                                if tonumber(k) then
                                                    self.defaults_value[i] = self.defaults_value[i] .. v .. ", "
                                                else
                                                    self.defaults_value[i] = self.defaults_value[i] .. k .. " = " .. v .. ", "
                                                end
                                            end
                                            self.defaults_value[i] = self.defaults_value[i]:sub(1,self.defaults_value[i]:len()-2) .. "}"

                                            settings_changed = true
                                            self.changed[i] = true
                                            
                                            self.results[i].text = self:build_setting(i)

                                            self:close()
                                            self.defaults_menu:swithItemTable("Defaults", self.results, i)
                                            UIManager:show(menu_container)
                                        end,
                                    },
                                },
                            },
                            input_type = "number",
                            width = Screen:getWidth() * 0.95,
                            height = Screen:getHeight() * 0.2,
                        }
                        self.set_dialog:onShowKeyboard()
                        UIManager:show(self.set_dialog)
                    end
                })

            else
                table.insert(self.results, {
                    text = self:build_setting(i),
                    callback = function()
                        self.set_dialog = InputDialog:new{
                            title = self.defaults_name[i] .. ":",
                            input = tostring(self.defaults_value[i]),
                            buttons = {
                                {
                                    {
                                        text = _("Cancel"),
                                        enabled = true,
                                        callback = function()
                                            self:close()
                                            UIManager:show(menu_container)
                                        end,
                                    },
                                    {
                                        text = _("OK"),
                                        enabled = true,
                                        callback = function()
                                            if type(_G[self.defaults_name[i]]) == "table" then
                                                self.defaults_value[i] = self.set_dialog:getInputText()
                                            elseif _G[self.defaults_name[i]] ~= settype(self.set_dialog:getInputText(),settings_type) then
                                                _G[self.defaults_name[i]] = settype(self.set_dialog:getInputText(),settings_type)
                                                self.defaults_value[i] = _G[self.defaults_name[i]]
                                            end
                                            settings_changed = true
                                            self.changed[i] = true
                                            self.results[i].text = self:build_setting(i)
                                            self:close()
                                            self.defaults_menu:swithItemTable("Defaults", self.results, i)
                                            UIManager:show(menu_container)
                                        end,
                                    },
                                },
                            },
                            input_type = settings_type,
                            width = Screen:getWidth() * 0.95,
                            height = Screen:getHeight() * 0.2,
                        }
                        self.set_dialog:onShowKeyboard()
                        UIManager:show(self.set_dialog)
                    end
                })
            end            
        end
    end
    self.defaults_menu:swithItemTable("Defaults", self.results)
    UIManager:show(menu_container)
end

function SetDefaults:close()
    self.set_dialog:onClose()
    UIManager:close(self.set_dialog)
end

function SetDefaults:ConfirmSave()
    UIManager:show(ConfirmBox:new{
        text = _("Are you sure to save the settings to \"defaults.persistent.lua\"?"),
        ok_callback = function()
            self:SaveSettings()
        end,
    })
end

function SetDefaults:build_setting(j)
    local ret = self.defaults_name[j] .. " = "
    if type(_G[self.defaults_name[j]]) == "boolean" or type(_G[self.defaults_name[j]]) == "table" then
        ret = ret .. tostring(self.defaults_value[j])
    elseif tonumber(self.defaults_value[j]) then
        ret = ret .. tostring(tonumber(self.defaults_value[j]))
    else
        ret = ret .. "\"" .. tostring(self.defaults_value[j]) .. "\""
    end
    return ret
end

function SetDefaults:SaveSettings()

    local function fileread(filename,array)
        local file = io.open(filename)
        local line = file:read()
        local counter = 0
        while line do
            counter = counter + 1
            local i = string.find(line,"[-][-]") -- remove comments from file
            if (i or 0)>1 then line = string.sub(line,1,i-1) end
            array[counter] = line:gsub("^%s*(.-)%s*$", "%1") -- trim
            line = file:read()
        end
        file:close()
    end

    local filename = "defaults.persistent.lua"
    local file
    if io.open(filename,"r") == nil then
        file = io.open(filename, "w")
        file:write("-- For configuration changes that persists between (nightly) releases\n")
        file:close()
    end

    local dpl = {}
    fileread("defaults.persistent.lua",dpl)
    local dl = {}
    fileread("defaults.lua",dl)
    self.results = {}
    local done = {}

    for j=1,#SetDefaults.defaults_name do
        if not self.changed[j] then done[j] = true end
    end

    -- handle case "found in persistent", replace it
    for i = 1,#dpl do
        for j=1,#SetDefaults.defaults_name do
            if not done[j] and string.find(dpl[i],SetDefaults.defaults_name[j] .. " ") == 1 then
                dpl[i] = self:build_setting(j)
                done[j] = true
            end
        end
    end

    -- handle case "not in persistent and different in non-persistent", add to persistent
    for j=1,#SetDefaults.defaults_name do
        if not done[j] then
            dpl[#dpl+1] = self:build_setting(j)
        end
    end

    file = io.open("defaults.persistent.lua", "w")
    for i = 1,#dpl do
        file:write(dpl[i] .. "\n")
    end
    file:close()
    UIManager:show(InfoMessage:new{text = _("Default settings successfully saved!")})
    settings_changed = false
end
return SetDefaults
