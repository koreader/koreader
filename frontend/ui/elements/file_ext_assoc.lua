local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local _ = require("gettext")

local ExtAssoc = {
    assoc = G_reader_settings:readSetting("file_ext_assoc") or {},
}

function ExtAssoc:commit()
    G_reader_settings:saveSetting("file_ext_assoc", self.assoc):flush()
    -- Translate the boolean map back to map of providers the OS backend can inquire further
    local t = {}
    for k, v in pairs(DocumentRegistry:getExtensions()) do
        if self.assoc[k] then t[k] = v end
    end
    Device:associateFileExtensions(t)
end

function ExtAssoc:setAll(state)
    for k, dummy in pairs(DocumentRegistry:getExtensions()) do
        self:setOne(k, state)
    end
    self:commit()
end

function ExtAssoc:setOne(ext, state)
    self.assoc[ext] = state and true or nil
end

function ExtAssoc:getSettingsMenuTable()
    local ret = {
        {
            keep_menu_open = true,
            text = _("Enable all"),
            callback = function(menu)
                self:setAll(true)
                menu:updateItems()
            end,
        },
        {
            keep_menu_open = true,
            text = _("Disable all"),
            callback = function(menu)
                self:setAll(false)
                menu:updateItems()
            end,
            separator = true,
        },
    }
    local exts = DocumentRegistry:getExtensions()
    local keys = {}
    for k, dummy in pairs(exts) do
        table.insert(keys, k)
    end
    table.sort(keys)
    for dummy, k in ipairs(keys) do
        table.insert(ret, {
            keep_menu_open = true,
            text = k,
            checked_func = function() return self.assoc[k] end,
            callback = function()
                self:setOne(k, not self.assoc[k])
                self:commit()
            end
        })
    end
    return ret
end

return ExtAssoc

