--[[
    This plugin implements KOReader integration with *some* calibre features:

        - metadata search
        - wireless transfers

    This module handles the UI part of the plugin.
--]]

local BD = require("ui/bidi")
local CalibreSearch = require("search")
local CalibreWireless = require("wireless")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local T = require("ffi/util").template

local Calibre = WidgetContainer:new{
    name = "calibre",
    is_doc_only = false,
}

function Calibre:onCalibreSearch()
    CalibreSearch:ShowSearch()
    return true
end

function Calibre:onCalibreBrowseTags()
    CalibreSearch.search_value = ""
    CalibreSearch:find("tags", 1)
    return true
end

function Calibre:onCalibreBrowseSeries()
    CalibreSearch.search_value = ""
    CalibreSearch:find("series", 1)
    return true
end

function Calibre:onNetworkDisconnected()
    self:closeWirelessConnection()
end

function Calibre:onSuspend()
    self:closeWirelessConnection()
end

function Calibre:onClose()
    self:closeWirelessConnection()
end

function Calibre:closeWirelessConnection()
    if CalibreWireless.calibre_socket then
        CalibreWireless:disconnect()
    end
end

function Calibre:onDispatcherRegisterActions()
    Dispatcher:registerAction("calibre_search", { category="none", event="CalibreSearch", title=_("Search in calibre metadata"), device=true,})
    Dispatcher:registerAction("calibre_browse_tags", { category="none", event="CalibreBrowseTags", title=_("Browse all calibre tags"), device=true,})
    Dispatcher:registerAction("calibre_browse_series", { category="none", event="CalibreBrowseSeries", title=_("Browse all calibre series"), device=true, separator=true,})
end

function Calibre:init()
    CalibreWireless:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function Calibre:addToMainMenu(menu_items)
    menu_items.calibre = {
        -- its name is "calibre", but all our top menu items are uppercase.
        text = _("Calibre"),
        sub_item_table = {
            {
                text_func = function()
                    if CalibreWireless.calibre_socket then
                        return _("Disconnect")
                    else
                        return _("Connect")
                    end
                end,
                separator = true,
                enabled_func = function()
                    return G_reader_settings:nilOrTrue("calibre_wireless")
                end,
                callback = function()
                    if not CalibreWireless.calibre_socket then
                        CalibreWireless:connect()
                    else
                        CalibreWireless:disconnect()
                    end
                end,
            },
            {   text = _("Search settings"),
                keep_menu_open = true,
                sub_item_table = self:getSearchMenuTable(),
            },
            {
                text = _("Wireless settings"),
                keep_menu_open = true,
                sub_item_table = self:getWirelessMenuTable(),
            },
        }
    }
    -- insert the metadata search
    if G_reader_settings:isTrue("calibre_search_from_reader") or not self.ui.view then
        menu_items.find_book_in_calibre_catalog = {
            text = _("Find a book via calibre metadata"),
            callback = function()
                CalibreSearch:ShowSearch()
            end
        }
    end
end

-- search options available from UI
function Calibre:getSearchMenuTable()
    return {
        {
            text = _("Manage libraries"),
            separator = true,
            keep_menu_open = true,
            sub_item_table_func = function()
                local result = {}
                -- append previous scanned dirs to the list.
                local cache = LuaSettings:open(CalibreSearch.user_libraries)
                for path, _ in pairs(cache.data) do
                    table.insert(result, {
                        text = path,
                        keep_menu_open = true,
                        checked_func = function()
                            return cache:readSetting(path)
                        end,
                        callback = function()
                            cache:saveSetting(path, not cache:readSetting(path))
                            cache:flush()
                            CalibreSearch:invalidateCache()
                        end,
                    })
                end
                -- if there's no result then no libraries are stored
                if #result == 0 then
                    table.insert(result, {
                        text = _("No calibre libraries"),
                        enabled = false
                    })
                end
                table.insert(result, 1, {
                    text = _("Rescan disk for calibre libraries"),
                    separator = true,
                    callback = function()
                        CalibreSearch:prompt()
                    end,
                })
                return result
            end,
        },
        {
            text = _("Enable searches in the reader"),
            checked_func = function()
                return G_reader_settings:isTrue("calibre_search_from_reader")
            end,
            callback = function()
                local current = G_reader_settings:isTrue("calibre_search_from_reader")
                G_reader_settings:saveSetting("calibre_search_from_reader", not current)
                UIManager:show(InfoMessage:new{
                    text = _("This will take effect on next restart."),
                })
            end,
        },
        {
            text = _("Store metadata in cache"),
            checked_func = function()
                return G_reader_settings:nilOrTrue("calibre_search_cache_metadata")
            end,
            callback = function()
                G_reader_settings:flipNilOrTrue("calibre_search_cache_metadata")
            end,
        },
        {
            text = _("Case sensitive search"),
            checked_func = function()
                return not G_reader_settings:nilOrTrue("calibre_search_case_insensitive")
            end,
            callback = function()
                G_reader_settings:flipNilOrTrue("calibre_search_case_insensitive")
            end,
        },
        {
            text = _("Search by title"),
            checked_func = function()
                return G_reader_settings:nilOrTrue("calibre_search_find_by_title")
            end,
            callback = function()
                G_reader_settings:flipNilOrTrue("calibre_search_find_by_title")
            end,
        },
        {
            text = _("Search by authors"),
            checked_func = function()
                return G_reader_settings:nilOrTrue("calibre_search_find_by_authors")
            end,
            callback = function()
                G_reader_settings:flipNilOrTrue("calibre_search_find_by_authors")
            end,
        },
        {
            text = _("Search by path"),
            checked_func = function()
                return G_reader_settings:nilOrTrue("calibre_search_find_by_path")
            end,
            callback = function()
                G_reader_settings:flipNilOrTrue("calibre_search_find_by_path")
            end,
        },
    }
end

-- wireless options available from UI
function Calibre:getWirelessMenuTable()
    local function isEnabled()
        local enabled = G_reader_settings:nilOrTrue("calibre_wireless")
        return enabled and not CalibreWireless.calibre_socket
    end
    return {
        {
            text = _("Enable wireless client"),
            separator = true,
            enabled_func = function()
                return not CalibreWireless.calibre_socket
            end,
            checked_func = function()
                return G_reader_settings:nilOrTrue("calibre_wireless")
            end,
            callback = function()
                G_reader_settings:flipNilOrTrue("calibre_wireless")
            end,
        },
        {
            text = _("Set password"),
            enabled_func = isEnabled,
            callback = function()
                CalibreWireless:setPassword()
            end,
        },
        {
            text = _("Set inbox directory"),
            enabled_func = isEnabled,
            callback = function()
                CalibreWireless:setInboxDir()
            end,
        },
        {
            text_func = function()
                local address = _("automatic")
                if G_reader_settings:has("calibre_wireless_url") then
                    address = G_reader_settings:readSetting("calibre_wireless_url")
                    address = string.format("%s:%s", address["address"], address["port"])
                end
                return T(_("Server address (%1)"), BD.ltr(address))
            end,
            enabled_func = isEnabled,
            sub_item_table = {
                {
                    text = _("Automatic"),
                    checked_func = function()
                        return G_reader_settings:hasNot("calibre_wireless_url")
                    end,
                    callback = function()
                        G_reader_settings:delSetting("calibre_wireless_url")
                    end,
                },
                {
                    text = _("Manual"),
                    checked_func = function()
                        return G_reader_settings:has("calibre_wireless_url")
                    end,
                    callback = function(touchmenu_instance)
                        local MultiInputDialog = require("ui/widget/multiinputdialog")
                        local url_dialog
                        local calibre_url = G_reader_settings:readSetting("calibre_wireless_url")
                        local calibre_url_address, calibre_url_port
                        if calibre_url then
                            calibre_url_address = calibre_url["address"]
                            calibre_url_port = calibre_url["port"]
                        end
                        url_dialog = MultiInputDialog:new{
                            title = _("Set custom calibre address"),
                            fields = {
                                {
                                    text = calibre_url_address,
                                    input_type = "string",
                                    hint = _("IP Address"),
                                },
                                {
                                    text = calibre_url_port,
                                    input_type = "number",
                                    hint = _("Port"),
                                },
                            },
                            buttons =  {
                                {
                                    {
                                        text = _("Cancel"),
                                        callback = function()
                                            UIManager:close(url_dialog)
                                        end,
                                    },
                                    {
                                        text = _("OK"),
                                        callback = function()
                                            local fields = url_dialog:getFields()
                                            if fields[1] ~= "" then
                                                local port = tonumber(fields[2])
                                                if not port or port < 1 or port > 65355 then
                                                    --default port
                                                     port = 9090
                                                end
                                                G_reader_settings:saveSetting("calibre_wireless_url", {address = fields[1], port = port })
                                            end
                                            UIManager:close(url_dialog)
                                            if touchmenu_instance then touchmenu_instance:updateItems() end
                                        end,
                                    },
                                },
                            },
                        }
                        UIManager:show(url_dialog)
                        url_dialog:onShowKeyboard()
                    end,
                },
            },
        },
    }
end

return Calibre
