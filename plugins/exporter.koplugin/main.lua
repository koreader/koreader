--[[
    This plugin exports highlights to specific formats and services

        - for the current document
        - for all documents in history
--]]

local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local MyClipping = require("clip")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util = require("ffi/util")
local _ = require("gettext")


local function migrateSettings()
    local formats = { "html", "joplin", "json", "readwise", "text" }

    local settings = G_reader_settings:readSetting("exporter")
    if not settings then
        settings = G_reader_settings:readSetting("evernote")
    end

    if type(settings) == "table" then
        for _, fmt in ipairs(formats) do
            if type(settings[fmt]) == "table" then return end
        end
        local new_settings = {}
        for _, fmt in ipairs(formats) do
            new_settings[fmt] = { enabled = false }
        end
        new_settings["joplin"].ip = settings.joplin_IP
        new_settings["joplin"].port = settings.joplin_port
        new_settings["joplin"].token = settings.joplin_token
        new_settings["readwise"].token = settings.readwise_token
        G_reader_settings:saveSetting("exporter", new_settings)
    end
end

local Exporter = InputContainer:new {
    name = "exporter",
    clipping_dir = DataStorage:getDataDir() .. "/clipboard",
    targets = {
        html = require("formats/html"),
        joplin = require("formats/joplin"),
        json = require("formats/json"),
        readwise = require("formats/readwise"),
        text = require("formats/text"),
    },
}

function Exporter:init()
    migrateSettings()
    self.parser = MyClipping:new {
        my_clippings = "/mnt/us/documents/My Clippings.txt",
        history_dir = "./history",
    }
    for k, _ in pairs(self.targets) do
        self.targets[k].path = self.path
    end
    self.config = DocSettings:open(util.joinPath(self.clipping_dir, "exporter.sdr"))
    self.ui.menu:registerToMainMenu(self)

end

function Exporter:updateHistoryClippings(clippings, new_clippings)
    -- update clippings from history clippings
    for title, booknotes in pairs(new_clippings) do
        for chapter_index, chapternotes in ipairs(booknotes) do
            for note_index, note in ipairs(chapternotes) do
                if clippings[title] == nil or clippings[title][chapter_index] == nil
                    or clippings[title][chapter_index][note_index] == nil
                    or clippings[title][chapter_index][note_index].page ~= note.page
                    or clippings[title][chapter_index][note_index].time ~= note.time
                    or clippings[title][chapter_index][note_index].text ~= note.text
                    or clippings[title][chapter_index][note_index].note ~= note.note then
                    logger.dbg("found new notes in history", booknotes.title)
                    clippings[title] = booknotes
                end
            end
        end
    end
    return clippings
end

function Exporter:updateMyClippings(clippings, new_clippings)
    -- only new titles or new notes in My clippings are updated to clippings
    -- since appending is the only way to modify notes in My Clippings
    for title, booknotes in pairs(new_clippings) do
        if clippings[title] == nil or #clippings[title] < #booknotes then
            logger.dbg("found new notes in MyClipping", booknotes.title)
            clippings[title] = booknotes
        end
    end
    return clippings
end

function Exporter:isReady()
    for k, v in pairs(self.targets) do
        if v:isEnabled() then
            return true
        end
    end
    return false
end

function Exporter:isDocReady()
    local docless = self.ui == nil or self.ui.document == nil or self.view == nil
    return not docless and self:isReady()
end

function Exporter:requiresNetwork()
    for k, v in pairs(self.targets) do
        if v:isEnabled() then
            if v.is_remote then
                return true
            end
        end
    end
end

function Exporter:normalizeBookNotes(booknotes)
    local normalized = {
        title = booknotes.title,
        author = booknotes.author,
        entries = {},
        exported = booknotes.exported,
        file = booknotes.file
    }
    for _, entry in ipairs(booknotes) do
        table.insert(normalized.entries, entry[1])
    end
    return normalized
end

function Exporter:exportCurrentNotes()
    local clippings = self.parser:parseCurrentDoc(self.view)
    self:exportClippings(clippings)
end

function Exporter:exportAllNotes()
    local clippings = self.config:readSetting("clippings") or {}
    clippings = self:updateHistoryClippings(clippings, self.parser:parseHistory())
    clippings = self:updateMyClippings(clippings, self.parser:parseMyClippings())
    self.config:saveSetting("clippings", clippings)
    self.config:flush()
    self:exportClippings(clippings)
end

function Exporter:exportClippings(clippings)
    if type(clippings) ~= "table" then return end
    local export_callback = function()
        UIManager:nextTick(function()
            local timestamp = os.time()
            local normalized = {}
            for _, content in pairs(clippings) do
                if content then
                    table.insert(normalized, self:normalizeBookNotes(content))
                end
            end
            for k, v in pairs(self.targets) do
                if v:isEnabled() then
                    v.timestamp = timestamp
                    v:export(normalized)
                    v.timestamp = nil
                end
            end
        end)

        UIManager:show(InfoMessage:new {
            text = _("Exporting may take several seconds…"),
            timeout = 1,
        })
    end
    if self:requiresNetwork() then
        NetworkMgr:runWhenOnline(export_callback)
    else
        export_callback()
    end
end

function Exporter:getAllNotes()
    local clippings = self.config:readSetting("clippings") or {}
    clippings = self:updateHistoryClippings(clippings, self.parser:parseHistory())
    clippings = self:updateMyClippings(clippings, self.parser:parseMyClippings())
    self.config:saveSetting("clippings", clippings)
    self.config:flush()
    return clippings
end

function Exporter:addToMainMenu(menu_items)
    local submenu = {}
    for k, v in pairs(self.targets) do
        submenu[#submenu + 1] = v:getMenuTable()
    end
    table.sort(submenu, function(v1, v2)
        return v1.text < v2.text
    end)

    menu_items.exporter = {
        text = _("Export highlights"),
        sub_item_table = {
            {
                text = _("Export all notes in this book"),
                enabled_func = function()
                    return self:isDocReady()
                end,
                callback = function()
                    self:exportCurrentNotes()
                end,
            },
            {
                text = _("Export all notes in your library"),
                enabled_func = function()
                    return self:isReady()
                end,
                callback = function()
                    self:exportAllNotes()
                end,
                separator = true,
            },
            {
                text = _("Choose formats and services"),
                sub_item_table = submenu,
                separator = true,
            },
            {
                text = _("Purge history records"),
                callback = function()
                end,
            },
        }
    }
end

return Exporter
