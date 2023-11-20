local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local BD = require("ui/bidi")
local DataStorage = require("datastorage")
local http = require("socket.http")
local json = require("json")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local util = require("ffi/util")
local T = util.template
local _ = require("gettext")

-- xmnote exporter
local XMNoteExporter = require("base"):new {
    name = "xmnote",
    is_remote = true,
    server_port = 8080
}

function XMNoteExporter:getMenuTable()
    return  {
        text = _("XMNote"),
        checked_func = function() return self:isEnabled() end,
        sub_item_table = {
            {
                text = _("Set XMNote IP"),
                keep_menu_open = true,
                callback = function()
                    local url_dialog
                    url_dialog = InputDialog:new {
                        title = _("Set XMNote IP"),
                        input = self.settings.ip,
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    callback = function()
                                        UIManager:close(url_dialog)
                                    end
                                },
                                {
                                    text = _("Set IP"),
                                    callback = function()
                                        local ip = url_dialog:getInputText()
                                        self.settings.ip = ip
                                        self:saveSettings()
                                        UIManager:close(url_dialog)
                                    end
                                }
                            }
                        }
                    }
                    UIManager:show(url_dialog)
                    url_dialog:onShowKeyboard()
                end
            } ,
            {
                text = _("Export to XMNote"),
                checked_func = function() return self:isEnabled() end,
                callback = function() self:toggleEnabled() end,
            },
            {
                text = _("Help"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new {
                        text = T(_([[Before starting the export process, please make sure that your mobile and KOReader are connected to the same local network. Open XMNote and go to "My" - "Import Highlights" - "Import via API". At the bottom of the interface, you will find the IP address of your mobile device. Enter this IP address into KOReader to complete the configuration.]])
                    , BD.dirpath(DataStorage:getDataDir()))
                    })
                end
            }
        }
    }
end

function XMNoteExporter:createRequestBody(booknotes)
    local book = {
        title = booknotes.title or "",
        author = booknotes.author or "",
        type = 1,
        locationUnit = 1,
    }
    local entries = {}
    for _, chapter in ipairs(booknotes) do
        for _, clipping in ipairs(chapter) do
            local entry = {
                text = clipping.text,
                note = clipping.note or "",
                chapter = clipping.chapter,
                time = clipping.time
            }
            local page = tonumber(clipping.page)
            if page ~= nil then
                entry.page = page
            end
            table.insert(entries, entry)
        end
    end
    book.entries = entries
    return book
end

function XMNoteExporter:makeRequest(endpoint, method, request_body)
    local sink = {}
    local request_body_json = json.encode(request_body)
    local source = ltn12.source.string(request_body_json)
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local url = "http://".. self.settings.ip .. ":" .. self.server_port .. endpoint
    local request = {
        url     = url,
        method  = method,
        sink    = ltn12.sink.table(sink),
        source  = source,
        headers = {
            ["Content-Length"] = #request_body_json,
            ["Content-Type"] = "application/json"
        },
    }
    local code, headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()

    if code ~= 200 then
        logger.warn("XMNoteClient: HTTP response code <> 200. Response status: ", status)
        logger.dbg("Response headers:", headers)
        return nil, status
    end

    local response = json.decode(sink[1])
    local api_code = response["code"]
    if api_code ~= nil and api_code ~= 200 then
        logger.warn("XMNoteClient: response code <> 200. message: ", response["message"])
        logger.dbg("Response headers:", headers)
        return nil, status
    end
    return response
end

function XMNoteExporter:createHighlights(booknotes)
    local body = self:createRequestBody(booknotes)
    local result, err = self:makeRequest("/send", "POST", body)
    if not result then
        logger.warn("error creating highlights", err)
        return false
    end

    logger.dbg("createHighlights result", result)
    return true
end


function XMNoteExporter:isReadyToExport()
    if self.settings.ip then return true end
    return false
end

function XMNoteExporter:export(t)
    if not self:isReadyToExport() then return false end

    for _, booknotes in ipairs(t) do
        local ok = self:createHighlights(booknotes)
        if not ok then return false end
    end
    return true
end

return XMNoteExporter

