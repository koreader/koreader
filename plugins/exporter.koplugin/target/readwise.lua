local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local http = require("socket.http")
local json = require("json")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local _ = require("gettext")

-- readwise exporter
local ReadwiseExporter = require("base"):new {
    name = "readwise",
    is_remote = true,
}

local function makeRequest(endpoint, method, request_body, token)
    local sink = {}
    local request_body_json = json.encode(request_body)
    local source = ltn12.source.string(request_body_json)
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local request = {
        url     = "https://readwise.io/api/v2/" .. endpoint,
        method  = method,
        sink    = ltn12.sink.table(sink),
        source  = source,
        headers = {
            ["Content-Length"] = #request_body_json,
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Token " .. token
        },
    }
    local code, headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()

    if code ~= 200 then
        logger.warn("Readwise: HTTP response code <> 200. Response status:", status or code or "network unreachable")
        logger.dbg("Response headers:", headers)
        return nil, status
    end

    local response = json.decode(sink[1])
    return response
end

function ReadwiseExporter:isReadyToExport()
    if self.settings.token then return true end
    return false
end

function ReadwiseExporter:getMenuTable()
    return {
        text = _("Readwise"),
        checked_func = function() return self:isEnabled() end,
        sub_item_table = {
            {
                text = _("Set authorization token"),
                keep_menu_open = true,
                callback = function()
                    local auth_dialog
                    auth_dialog = InputDialog:new {
                        title = _("Set authorization token for Readwise"),
                        input = self.settings.token,
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    callback = function()
                                        UIManager:close(auth_dialog)
                                    end
                                },
                                {
                                    text = _("Set token"),
                                    callback = function()
                                        self.settings.token = auth_dialog:getInputText()
                                        self:saveSettings()
                                        UIManager:close(auth_dialog)
                                    end
                                }
                            }
                        }
                    }
                    UIManager:show(auth_dialog)
                    auth_dialog:onShowKeyboard()
                end
            },
            {
                text = _("Export to Readwise"),
                checked_func = function() return self:isEnabled() end,
                callback = function() self:toggleEnabled() end,
            },

        }
    }
end

function ReadwiseExporter:createHighlights(booknotes)
    local highlights = {}
    for _, chapter in ipairs(booknotes) do
        for _, clipping in ipairs(chapter) do
            local highlight = {
                text = clipping.text,
                title = booknotes.title,
                author = booknotes.author ~= "" and booknotes.author:gsub("\n", ", ") or nil, -- optional author
                source_type = "koreader",
                category = "books",
                note = clipping.note,
                location = clipping.page,
                location_type = "order",
                highlighted_at = os.date("!%Y-%m-%dT%TZ", clipping.time),
            }
            table.insert(highlights, highlight)
        end
    end

    local result, err = makeRequest("highlights", "POST", { highlights = highlights }, self.settings.token)
    if not result then
        logger.warn("error creating highlights", err)
        return false
    end

    logger.dbg("createHighlights result", result)
    return true
end

function ReadwiseExporter:export(t)
    if not self:isReadyToExport() then return false end

    for _, booknotes in ipairs(t) do
        local ok = self:createHighlights(booknotes)
        if not ok then return false end
    end
    return true
end

return ReadwiseExporter
