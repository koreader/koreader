--[[--
Base for highlight exporters.

Each target should inherit from this class and implement *at least* an `export` function.

@module baseexporter
]]

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local http = require("socket.http")
local ltn12 = require("ltn12")
local rapidjson = require("rapidjson")
local socket = require("socket")
local socketutil = require("socketutil")
local _ = require("gettext")
local T = require("ffi/util").template

local BaseExporter = {
    settings_key = "exporter", -- same as in main.lua
}

function BaseExporter:new(o)
    o = o or {}
    assert(type(o.name) == "string", "name is mandatory")
    setmetatable(o, self)
    self.__index = self
    return o:_init()
end

function BaseExporter:_init()
    self.extension = self.extension or self.name
    self.is_remote = self.is_remote or false
    self.version = self.version or "1.0.0"
    self.shareable = self.is_remote and nil or Device:canShareText()
    self:loadSettings()
    return self
end

function BaseExporter:loadSettings()
    local plugin_settings = G_reader_settings:readSetting(self.settings_key, {})
    plugin_settings[self.name] = plugin_settings[self.name] or self.default_settings or {}
    self.settings = plugin_settings[self.name]
end

function BaseExporter:getMarkdownSettings()
    return G_reader_settings:readSetting(self.settings_key).markdown
end

function BaseExporter:saveSettings() end -- for backward compatibility

--[[--
Export timestamp

@treturn string timestamp
]]
function BaseExporter:getTimeStamp()
    local ts = self.timestamp or os.time()
    return os.date("%Y-%m-%d-%H-%M-%S", ts)
end

--[[--
Exporter version

@treturn string version
]]
function BaseExporter:getVersion()
    return self.name .. "/" .. self.version
end

--[[--
Exports a table of booknotes to local format or remote service

@param t table of booknotes
@treturn bool success
]]
function BaseExporter:export(t) end

--[[--
File path where the exporter writes its output

@treturn string absolute path or nil
]]
function BaseExporter:getFilePath()
    return self.filepath and self.filepath .. "." .. self.extension
end

--[[--
Configuration menu for the exporter

@treturn table menu with exporter settings
]]
function BaseExporter:getMenuTable()
    return {
        text = self.name:gsub("^%l", string.upper),
        checked_func = function()
            return self:isEnabled()
        end,
        callback = function()
            self:toggleEnabled()
        end,
    }
end

--[[--
Checks if the exporter is ready to export

@treturn bool ready
]]
function BaseExporter:isReadyToExport()
    return true
end

--[[--
Checks if the exporter was enabled by the user and it is ready to export

@treturn bool enabled
]]
function BaseExporter:isEnabled()
    return self.settings.enabled and self:isReadyToExport()
end

--[[--
Toggles exporter enabled state if it's ready to export
]]
function BaseExporter:toggleEnabled()
    if self:isReadyToExport() then
        self.settings.enabled = not self.settings.enabled
    end
end

function BaseExporter:genTargetMenu()
    return {
        text = self.title,
        checked_func = function()
            return self:isEnabled()
        end,
        hold_callback = function(touchmenu_instance)
            self:toggleEnabled()
            touchmenu_instance:updateItems()
        end,
        sub_item_table = self:genTargetSubMenu(), -- provided by targets
    }
end

function BaseExporter:genToggleMenuItem(item_text, item_setting, separator)
    return {
        text = item_text,
        checked_func = function()
            return self.settings[item_setting]
        end,
        callback = function()
            self.settings[item_setting] = not self.settings[item_setting] or nil
        end,
        separator = separator,
    }
end

function BaseExporter:genExportToMenuItem()
    return {
        text = T(_("Export to %1"), self.title),
        checked_func = function()
            return self:isEnabled()
        end,
        enabled_func = function()
            return self:isReadyToExport() and true or false
        end,
        callback = function()
            self:toggleEnabled()
        end,
        separator = self.help_text == nil,
    }
end

function BaseExporter:genHelpMenuItem()
    return {
        text = _("Help"),
        keep_menu_open = true,
        callback = function()
            UIManager:show(InfoMessage:new{ text = self.help_text or self.title })
        end,
        separator = true,
    }
end

function BaseExporter:genCloudStorageMenuItem()
    return {
        text_func = function()
            return T("Upload to cloud storage: %1",
                self.settings.upload_server and self.settings.upload_server.name or _("not set"))
        end,
        enabled_func = function()
            return self.plugin.ui.cloudstorage ~= nil
        end,
        checked_func = function()
            return self.plugin.ui.cloudstorage and self.settings.upload
        end,
        check_callback_updates_menu = true,
        callback = function(touchmenu_instance)
            self:setUploadServer(touchmenu_instance)
        end,
    }
end

function BaseExporter:genDeleteFileMenuItem()
    return {
        text = _("Delete local export file after uploading"),
        enabled_func = function()
            return self.plugin.ui.cloudstorage ~= nil and self.settings.upload ~= nil
        end,
        checked_func = function()
            return self.plugin.ui.cloudstorage and self.settings.upload and self.settings.upload_delete_local
        end,
        callback = function()
            self.settings.upload_delete_local = not self.settings.upload_delete_local or nil
        end,
        separator = true,
    }
end

function BaseExporter:setUploadServer(touchmenu_instance)
    local cs = self.plugin.ui.cloudstorage
    local server = self.settings.upload_server
    local server_dialogue
    local text = cs:getServerNameType(server) or _("not set")
    if server then
        text = text .. "\n\n" .. T(_("Folder path:\n%1"), cs.getReadablePath(server)) .. "\n"
    end
    server_dialogue = ButtonDialog:new{
        title = T(_("Cloud storage: %1"), text),
        buttons = {
            {
                {
                    text = _("Delete"),
                    enabled = server ~= nil,
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = _("Delete server info?"),
                            ok_text = _("Delete"),
                            ok_callback = function()
                                UIManager:close(server_dialogue)
                                self.settings.upload_server = nil
                                self.settings.upload = nil
                                touchmenu_instance:updateItems()
                            end,
                        })
                    end,
                },
                {
                    text = _("Edit"),
                    callback = function()
                        UIManager:close(server_dialogue)
                        cs:onShowCloudStorageList(function(sv)
                            self.settings.upload_server = sv
                            touchmenu_instance:updateItems()
                            self:setUploadServer(touchmenu_instance) -- keep the dialog open
                        end)
                    end,
                },
            },
            {
                {
                    text = _("Close"),
                    callback = function()
                        UIManager:close(server_dialogue)
                    end,
                },
                {
                    text = self.settings.upload and _("Disable") or _("Enable"),
                    enabled = server ~= nil,
                    callback = function()
                        UIManager:close(server_dialogue)
                        self.settings.upload = not self.settings.upload or nil
                        touchmenu_instance:updateItems()
                    end,
                },
            },
        },
    }
    UIManager:show(server_dialogue)
end

function BaseExporter:uploadFile(file_path)
    if self.settings.upload and self.plugin.ui.cloudstorage then
        local function success_callback()
            if self.settings.upload_delete_local then
                os.remove(file_path)
            end
            UIManager:show(Notification:new{
                text = _("Successfully uploaded export file"),
                timeout = 3,
            })
        end
        local function failure_callback()
            UIManager:show(Notification:new{
                text = _("Could not upload export file"),
                timeout = 3,
            })
        end
        self.plugin.ui.cloudstorage:uploadFile(self.settings.upload_server, file_path, success_callback, failure_callback)
    end
end

--[[--
Shares text with other apps
]]
function BaseExporter:shareText(text, title)
    local reason = _("Share") .. " " .. self.name
    Device:doShareText(text, reason, title, self.mimetype)
end

--[[--
Makes a json request against a remote endpoint

@param endpoint string url
@param method string method
@param body string json string to encode
@param headers table of additional headers

@treturn response or nil, err
]]

function BaseExporter:makeJsonRequest(endpoint, method, body, headers)
    local msg_failed = "json request failed: %s"
    local sink = {}
    local extra_headers = headers or {}
    local body_json, response, err

    body_json, err = rapidjson.encode(body)
    if not body_json then
        return nil, string.format(msg_failed,
            "cannot encode body" .. err)
    end
    local source = ltn12.source.string(body_json)
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)

    local request = {
        url = endpoint,
        method = method,
        sink = ltn12.sink.table(sink),
        source = source,
        headers = {
            ["Content-Length"] = #body_json,
            ["Content-Type"] = "application/json",
        },
    }

    -- fill in extra headers
    for k, v in pairs(extra_headers) do
        request.headers[k] = v
    end

    local code, __, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()

    if code ~= 200 then
        return nil, string.format(msg_failed,
            status or code or "network unreachable")
    end

    if not sink[1] then
        return nil, string.format(msg_failed,
            "no response from server")
    end

    response, err = rapidjson.decode(table.concat(sink))
    if not response then
        return nil, string.format(msg_failed,
            "unable to decode server response" .. err)
    end

    return response
end

return BaseExporter
