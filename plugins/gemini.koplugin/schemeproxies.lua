local InputDialog = require("ui/widget/inputdialog")
local Persist = require("persist")
local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local KeyValuePage = require("ui/widget/keyvaluepage")
local _ = require("gettext")
local T = require("ffi/util").template

local gemini_dir = DataStorage:getDataDir() .. "/gemini"
local scheme_proxies_persist = Persist:new{ path = gemini_dir .. "/scheme_proxies.lua" }

local SchemeProxies = {
    scheme_proxies = scheme_proxies_persist:load() or { gopher = {}, ["http(s)"] = {} },
}

function SchemeProxies:get(scheme)
    local proxy = self.scheme_proxies[scheme]
    if proxy and proxy.host then
        return proxy
    end
    if scheme == "http" or scheme == "https" then
        return self:get("http(s)")
    end
end

function SchemeProxies:supportedSchemes()
    local schemes = { "gemini", "about", "titan" }
    for scheme,proxy in pairs(self.scheme_proxies) do
        if proxy and proxy.host then
            if scheme == "http(s)" then
                table.insert(schemes, "http")
                table.insert(schemes, "https")
            else
                table.insert(schemes, scheme)
            end
        end
    end
    return schemes
end

local function basicInputDialog(title, cb, input, is_secret)
    local input_dialog
    input_dialog = InputDialog:new{
        title = title,
        input = input or "",
        text_type = is_secret and "password",
        enter_callback = cb,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Enter"),
                    callback = cb,
                },
            },
        },
    }
    return input_dialog
end

function SchemeProxies:edit()
    local menu
    local kv_pairs = {}
    for scheme,proxy in pairs(self.scheme_proxies) do
        table.insert(kv_pairs, { scheme, proxy.host or "", callback = function()
            local input_dialog
            input_dialog = basicInputDialog(
                T(_("Set proxy server for %1 URLs"), scheme),
                function()
                    local host = input_dialog:getInputText()
                    if host == "" then
                        host = nil
                    end
                    self.scheme_proxies[scheme].host = host
                    scheme_proxies_persist:save(self.scheme_proxies)
                    UIManager:close(input_dialog)
                    UIManager:close(menu)
                    self:edit()
                end,
                proxy.host or "")
            UIManager:show(input_dialog)
            input_dialog:onShowKeyboard()
        end })
    end
    table.insert(kv_pairs, { _("[New]"), _("Select to add new scheme"), callback = function()
        local input_dialog
        input_dialog = basicInputDialog(_("Add new scheme to proxy"), function()
            local scheme = input_dialog:getInputText()
            UIManager:close(input_dialog)
            if scheme then
                self.scheme_proxies[scheme] = {}
                UIManager:close(menu)
                self:edit()
            end
        end)
        UIManager:show(input_dialog)
        input_dialog:onShowKeyboard()
    end })
    menu = KeyValuePage:new{
        title = _("Scheme proxies"),
        kv_pairs = kv_pairs,
    }
    UIManager:show(menu)
end

return SchemeProxies
