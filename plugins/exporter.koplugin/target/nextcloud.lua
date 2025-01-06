local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local mime = require("mime")
local md = require("template/md")
local json = require("json")
local http = require("socket.http")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local logger = require("logger")
local T = require("ffi/util").template
local _ = require("gettext")

-- nextcloud notes exporter
local NextcloudExporter = require("base"):new {
    name = "nextcloud_notes",
    category = _("KOReader"),
    is_remote = true,
}

-- fetching all notes from Nextcloud is costly, so we keep a copy here
-- while we determine wether to update existing or create a new note
local notes_cache

local function makeRequest(url, auth, method, request_body)
    local sink = {}
    local request_body_json = json.encode(request_body)
    local source = ltn12.source.string(request_body_json)

    local request = {
        url     = url,
        method  = method,
        sink    = ltn12.sink.table(sink),
        source  = source,
        headers = {
            ["Content-Length"] = #request_body_json,
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. auth,
            ["OCS-APIRequest"] = "true",
        },
    }
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local code, headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()

    if code ~= 200 then
        logger.warn("Nextcloud: HTTP response code <> 200. Response status:", status or code or "network unreachable")
        logger.dbg("Response headers:", headers)
        return nil, status
    end

    if not sink[1] then
        return nil, "No response from Nextcloud"
    end

    local response = json.decode(sink[1])
    return response
end

function NextcloudExporter:isReadyToExport()
    return self.settings.host and self.settings.username and self.settings.password
end

function NextcloudExporter:getMenuTable()
    local dialog_title = _("Setup Nextcloud Notes plugin")
    return {
        text = _("Nextcloud Notes"),
        checked_func = function() return self:isEnabled() end,
        sub_item_table = {
            {
                text = dialog_title,
                keep_menu_open = true,
                callback = function()
                    local url_dialog
                    url_dialog = MultiInputDialog:new {
                        title = dialog_title,
                        fields = {
                            {
                                description = _("Nextcloud URL"),
                                hint = "https://yournextcloud.com",
                                text = self.settings.host,
                                input_type = "string"
                            },
                            {
                                description = _("Username"),
                                hint = _("Username"),
                                text = self.settings.username,
                                input_type = "string"
                            },
                            {
                                description = _("App password"),
                                hint = _("Security → Devices & sessions"),
                                text = self.settings.password,
                                input_type = "string"
                            }
                        },
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    callback = function()
                                        UIManager:close(url_dialog)
                                    end
                                },
                                {
                                    text = _("OK"),
                                    callback = function()
                                        local fields = url_dialog:getFields()
                                        local host = fields[1]
                                        local username = fields[2]
                                        local password = fields[3]
                                        if host ~= "" then
                                            self.settings.host = host
                                            self:saveSettings()
                                        end
                                        if username ~= "" then
                                            self.settings.username = username
                                            self:saveSettings()
                                        end
                                        if password ~= "" then
                                            self.settings.password = password
                                            self:saveSettings()
                                        end
                                        UIManager:close(url_dialog)
                                    end
                                }
                            }
                        }
                    }
                    UIManager:show(url_dialog)
                    url_dialog:onShowKeyboard()
                end
            },
            {
                text = _("Export to Nextcloud Notes"),
                checked_func = function() return self:isEnabled() end,
                callback = function() self:toggleEnabled() end,
            },
            {
                text = _("Help"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new {
                        text = T(_([[For Nextcloud Notes setup instructions, see %1

Markdown formatting can be configured in:
Export highlights > Choose formats and services > Markdown.]]), "https://github.com/koreader/koreader/wiki/Nextcloud-notes")
                    })
                end
            }
        }
    }
end

function NextcloudExporter:export(t)
    if not self:isReadyToExport() then
        return false
    end

    -- determine if markdown export is set
    local plugin_settings = G_reader_settings:readSetting("exporter") or {}
    local markdown_settings = plugin_settings.markdown

    -- setup Nextcloud variables
    local url_base = string.format("%s/index.php/apps/notes/api/v1/", self.settings.host)
    local auth = mime.b64(self.settings.username .. ":" .. self.settings.password)
    local note_id
    local verb
    local request_body
    local response
    local err

    -- fetch existing notes from Nextcloud
    local url = url_base .. "notes?category=" .. self.category
    notes_cache, err = makeRequest(url, auth, "GET")
    if not notes_cache then
        logger.warn("Error fetching existing notes from Nextcloud", err)
        return false
    end

    -- export each note
    for _, booknotes in pairs(t) do
        local note = md.prepareBookContent(booknotes, markdown_settings.formatting_options, markdown_settings.highlight_formatting)
        local note_title = string.format("%s - %s", string.gsub(booknotes.author, "\n", ", "), booknotes.title)

        -- search for existing note, and in that case use its ID for update
        note_id = nil
        if notes_cache then
            for i, note_cached in ipairs(notes_cache) do
                if note_cached.title == note_title then
                    note_id = note_cached.id
                    break
                end
            end
        end

        -- note body is the same for create and update
        request_body = {
            title = note_title,
            content = table.concat(note, "\n"),
            category = self.category,
        }

        -- set up create or update specific parameters
        if note_id then
            verb = "PUT"
            url = string.format("%snotes/%s", url_base, note_id)
        else
            verb = "POST"
            url = url_base.."notes"
        end

        -- save note in Nextcloud
        response, err = makeRequest(url, auth, verb, request_body)
        if not response then
            logger.warn("Error saving note in Nextcloud", err)
            return false
        end
    end

    return true
end

return NextcloudExporter
