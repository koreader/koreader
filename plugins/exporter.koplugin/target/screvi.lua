local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

-- Screvi exporter: https://screvi.com
-- API keys are created at app.screvi.com → Settings → API (write access).
-- Screvi skips highlights it already has, so exporting a book again is safe.

local API_URL = "https://api.screvi.com/api/extension/import"
local MAX_HIGHLIGHTS_PER_REQUEST = 500

local ScreviExporter = require("base"):new {
    name = "screvi",
    is_remote = true,
}

function ScreviExporter:isReadyToExport()
    return self.settings.token ~= nil and self.settings.token ~= ""
end

function ScreviExporter:getMenuTable()
    return {
        text = _("Screvi"),
        checked_func = function() return self:isEnabled() end,
        sub_item_table = {
            {
                text = _("Set API key"),
                keep_menu_open = true,
                callback = function()
                    local auth_dialog
                    auth_dialog = InputDialog:new {
                        title = _("Set API key for Screvi"),
                        description = _("Create a key with write access at app.screvi.com → Settings → API."),
                        input = self.settings.token,
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    id = "close",
                                    callback = function()
                                        UIManager:close(auth_dialog)
                                    end
                                },
                                {
                                    text = _("Set key"),
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
                text = _("Export to Screvi"),
                checked_func = function() return self:isEnabled() end,
                callback = function() self:toggleEnabled() end,
            },
        }
    }
end

local function trim(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s ~= "" and s or nil
end

--- One book in the shape Screvi's import API expects, or nil when it has no text highlights.
function ScreviExporter:createSource(booknotes)
    local author = trim(booknotes.author)
    local source = {
        name = trim(booknotes.title) or _("Unknown"),
        -- Multiple authors are newline-separated; Screvi needs an author to import a book.
        author = author and author:gsub("%s*\n%s*", ", ") or "Unknown Author",
        type = "book",
        highlights = {},
    }
    for _, chapter in ipairs(booknotes) do
        for _, clipping in ipairs(chapter) do
            local text = trim(clipping.text)
            -- Image clippings have no text to send.
            if text then
                local page = tonumber(clipping.page)
                local chapter_title = trim(clipping.chapter)
                table.insert(source.highlights, {
                    content = text,
                    note = trim(clipping.note),
                    date = clipping.time and os.date("!%Y-%m-%dT%H:%M:%SZ", clipping.time) or nil,
                    location = page and tostring(page) or nil,
                    metadata = (page or chapter_title) and { page = page, chapter = chapter_title } or nil,
                })
            end
        end
    end
    return #source.highlights > 0 and source or nil
end

function ScreviExporter:sendSources(sources)
    local result, err = self:makeJsonRequest(API_URL, "POST",
        { type = "koreader", data = sources },
        { ["X-API-Key"] = self.settings.token })
    if not result then
        logger.warn("Screvi: export failed", err)
        return false
    end
    return true
end

function ScreviExporter:export(t)
    if not self:isReadyToExport() then return false end

    -- Batch books so a large library stays well under the server's request limits.
    local batch, count = {}, 0
    for _, booknotes in ipairs(t) do
        local source = self:createSource(booknotes)
        if source then
            if count > 0 and count + #source.highlights > MAX_HIGHLIGHTS_PER_REQUEST then
                if not self:sendSources(batch) then return false end
                batch, count = {}, 0
            end
            table.insert(batch, source)
            count = count + #source.highlights
        end
    end
    if #batch > 0 then
        return self:sendSources(batch)
    end
    return true
end

return ScreviExporter
