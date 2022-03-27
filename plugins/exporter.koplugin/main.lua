local BD = require("ui/bidi")
local InputContainer = require("ui/widget/container/inputcontainer")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util = require("ffi/util")
local Device = require("device")
local JoplinClient = require("JoplinClient")
local ReadwiseClient = require("ReadwiseClient")
local T = util.template
local _ = require("gettext")
local N_ = _.ngettext
local slt2 = require('slt2')
local MyClipping = require("clip")
local json = require("json")

local function getOrMigrateSettings()
    local settings = G_reader_settings:readSetting("exporter")
    if not settings then
        -- migrate settings from old plugin and remove specific evernote ones.
        settings = G_reader_settings:readSetting("evernote")
        if type(settings) == "table" then
            settings.domain = nil
            settings.username = nil
            settings.token = nil
        end
    end
    return settings or {}
end

local Exporter = InputContainer:new{
    name = "exporter",
    notebook_name = _("KOReader Notes"),
    notemarks = _("Note: "),
    clipping_dir = DataStorage:getDataDir() .. "/clipboard",

    evernote_token = nil,
    notebook_guid = nil,
}

function Exporter:init()
    self.text_clipping_file = self.clipping_dir .. "/KOReaderClipping.txt"
    self.json_clipping_file = self.clipping_dir .. "/KOReaderClipping.json"
    local settings = getOrMigrateSettings()
    self.notebook_guid = settings.notebook
    self.joplin_IP = settings.joplin_IP or "localhost"
    self.joplin_port = settings.joplin_port or 41185
    self.joplin_token = settings.joplin_token -- or your token
    self.joplin_notebook_guid = settings.joplin_notebook_guid or nil
    self.readwise_token = settings.readwise_token or nil
    self.html_export = settings.html_export or false
    self.joplin_export = settings.joplin_export or false
    self.txt_export = settings.txt_export or false
    self.json_export = settings.json_export or false
    self.readwise_export = settings.readwise_export or false
    --- @todo Is this if block necessary? Nowhere in the code they are assigned both true.
    -- Do they check against external modifications to settings file?

    if self.html_export then
        self.txt_export = false
        self.joplin_export = false
        self.json_export = false
        self.readwise_export = false
    elseif self.txt_export then
        self.joplin_export = false
        self.json_export = false
        self.readwise_export = false
    elseif self.json_export then
        self.joplin_export = false
        self.readwise_export = false
    end

    self.parser = MyClipping:new{
        my_clippings = "/mnt/us/documents/My Clippings.txt",
        history_dir = "./history",
    }
    self.template = slt2.loadfile(self.path.."/note.tpl")
    self:migrateClippings()
    self.config = DocSettings:open(util.joinPath(self.clipping_dir, "exporter.sdr"))

    self.ui.menu:registerToMainMenu(self)
end

function Exporter:isDocless()
    return self.ui == nil or self.ui.document == nil or self.view == nil
end

function Exporter:readyToExport()
    return self.html_export ~= false or
            self.txt_export ~= false or
            self.json_export ~= false or
            self.joplin_export ~= false or
            self.readwise_export ~= false
end

function Exporter:migrateClippings()
    if jit.os == "OSX" then return end
    local old_dir = util.joinPath(util.realpath(util.joinPath(self.path, "..")),
        "evernote.sdr")
    if lfs.attributes(old_dir, "mode") == "directory" then
        local mv_bin = Device:isAndroid() and "/system/bin/mv" or "/bin/mv"
        return util.execute(mv_bin, old_dir, self.clipping_dir) == 0
    end
end

function Exporter:addToMainMenu(menu_items)
    menu_items.exporter = {
        text = _("Export highlights"),
        sub_item_table = {
            {
                text = _("Joplin") ,
                checked_func = function() return self.joplin_export end,
                sub_item_table ={
                    {
                        text = _("Set Joplin IP and Port"),
                        keep_menu_open = true,
                        callback = function()
                            local MultiInputDialog = require("ui/widget/multiinputdialog")
                            local url_dialog
                            url_dialog = MultiInputDialog:new{
                                title = _("Set Joplin IP and port number"),
                                fields = {
                                    {
                                        text = self.joplin_IP,
                                        input_type = "string"
                                    },
                                    {
                                        text = self.joplin_port,
                                        input_type = "number"
                                    }
                                },
                                buttons = {
                                    {
                                        {
                                            text = _("Cancel"),
                                            id = "close",
                                            callback = function()
                                                UIManager:close(url_dialog)
                                            end
                                        },
                                        {
                                            text = _("OK"),
                                            callback = function()
                                                local fields = url_dialog:getFields()
                                                local ip = fields[1]
                                                local port = tonumber(fields[2])
                                                if ip ~= "" then
                                                    if port and port < 65355 then
                                                        self.joplin_IP = ip
                                                        self.joplin_port = port
                                                    end
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
                        text = _("Set authorization token"),
                        keep_menu_open = true,
                        callback = function()
                            local auth_dialog
                            auth_dialog = InputDialog:new{
                                title = _("Set authorization token for Joplin"),
                                input = self.joplin_token,
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
                                            text = _("Set token"),
                                            callback = function()
                                                self.joplin_token = auth_dialog:getInputText()
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
                        text = _("Export to Joplin"),
                        checked_func = function() return self.joplin_export end,
                        callback = function()
                            self.joplin_export = not self.joplin_export
                            if self.joplin_export then
                                self.html_export = false
                                self.txt_export = false
                                self.json_export = false
                                self.readwise_export = false
                            end
                            self:saveSettings()
                        end
                    },
                    {
                        text = _("Help"),
                        keep_menu_open = true,
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = T(_([[You can enter your auth token on your computer by saving an empty token. Then quit KOReader, edit the exporter.joplin_token field in %1/settings.reader.lua after creating a backup, and restart KOReader once you're done.

To export to Joplin, you must forward the IP and port used by this plugin to the localhost:port on which Joplin is listening. This can be done with socat or a similar program. For example:

For Windows: netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=41185 connectaddress=localhost connectport=41184

For Linux: $socat tcp-listen:41185,reuseaddr,fork tcp:localhost:41184

For more information, please visit https://github.com/koreader/koreader/wiki/Highlight-export.]])
                            , BD.dirpath(DataStorage:getDataDir()))
                            })
                        end
                    }
                }
            },
            {
                text = _("Readwise") ,
                checked_func = function() return self.readwise_export end,
                separator = true,
                sub_item_table ={
                    {
                        text = _("Set authorization token"),
                        keep_menu_open = true,
                        callback = function()
                            local auth_dialog
                            auth_dialog = InputDialog:new{
                                title = _("Set authorization token for Readwise"),
                                input = self.readwise_token,
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
                                            text = _("Set token"),
                                            callback = function()
                                                self.readwise_token = auth_dialog:getInputText()
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
                        checked_func = function() return self.readwise_export end,
                        callback = function()
                            self.readwise_export = not self.readwise_export
                            if self.readwise_export then
                                self.html_export = false
                                self.txt_export = false
                                self.json_export = false
                                self.joplin_export = false
                            end
                            self:saveSettings()
                        end
                    },
                    {
                        text = _("Help"),
                        keep_menu_open = true,
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = T(_([[You can enter your auth token on your computer by saving an empty token. Then quit KOReader, edit the exporter.readwise_token field in %1/settings.reader.lua after creating a backup, and restart KOReader once you're done.

For more information, please visit https://github.com/koreader/koreader/wiki/Highlight-export.]])
                            , BD.dirpath(DataStorage:getDataDir()))
                            })
                        end
                    }
                }
            },
            {
                text = _("Export all notes in this book"),
                enabled_func = function()
                    return not self:isDocless() and self:readyToExport() and not self.txt_export
                end,
                callback = function()
                    local export_callback = function()
                        UIManager:nextTick(function()
                            self:exportCurrentNotes(self.view)
                        end)

                        UIManager:show(InfoMessage:new{
                            text = _("Exporting may take several seconds…"),
                            timeout = 1,
                        })
                    end
                    if self.joplin_export or self.readwise_export then
                        NetworkMgr:runWhenOnline(export_callback)
                    else
                        export_callback()
                    end
                end
            },
            {
                text = _("Export all notes in your library"),
                enabled_func = function()
                    return self:readyToExport()
                end,
                callback = function()
                    local export_callback = function()
                        UIManager:nextTick(function()
                            self:exportAllNotes()
                        end)

                        UIManager:show(InfoMessage:new{
                            text = _("Exporting may take several minutes…"),
                            timeout = 1,
                        })
                    end
                    if self.joplin_export or self.readwise_export then
                        NetworkMgr:runWhenOnline(export_callback)
                    else
                        export_callback()
                    end

                end,
                separator = true,
            },
            {
                text = _("Export to local JSON files"),
                checked_func = function() return self.json_export end,
                callback = function()
                    self.json_export = not self.json_export
                    if self.json_export then
                        self.txt_export = false
                        self.html_export = false
                        self.joplin_export = false
                        self.readwise_export = false
                    end
                    self:saveSettings()
                end
            },
            {
                text = _("Export to local HTML files"),
                checked_func = function() return self.html_export end,
                callback = function()
                    self.html_export = not self.html_export
                    if self.html_export then
                        self.txt_export = false
                        self.json_export = false
                        self.joplin_export = false
                        self.readwise_export = false
                    end
                    self:saveSettings()
                end
            },
            {
                text = _("Export to local clipping text file"),
                checked_func = function() return self.txt_export end,
                callback = function()
                    self.txt_export = not self.txt_export
                    if self.txt_export then
                        self.html_export = false
                        self.json_export = false
                        self.joplin_export = false
                        self.readwise_export = false
                    end
                    self:saveSettings()
                end,
                separator = true,
            },
            {
                text = _("Purge history records"),
                callback = function()
                    self.config:purge()
                    UIManager:show(InfoMessage:new{
                        text = _("History records have been purged.\nAll notes will be exported again next time.\n"),
                        timeout = 2,
                    })
                end
            }
        }
    }
end

function Exporter:saveSettings()
    local settings = {
        notebook = self.notebook_guid,
        html_export = self.html_export,
        txt_export = self.txt_export,
        json_export = self.json_export,
        joplin_IP = self.joplin_IP,
        joplin_port = self.joplin_port,
        joplin_token = self.joplin_token,
        joplin_notebook_guid = self.joplin_notebook_guid,
        joplin_export = self.joplin_export,
        readwise_token = self.readwise_token,
        readwise_export = self.readwise_export
    }
    G_reader_settings:saveSetting("exporter", settings)
end

function Exporter:getExportNotebook(client)
    local name = self.notebook_name
    return client:findNotebookByTitle(name) or client:createNotebook(name).guid
end

function Exporter:exportCurrentNotes(view)
    local clippings = self.parser:parseCurrentDoc(view)
    self:exportClippings(clippings)
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

--[[--
Parses highlights and calls exporter functions.

Entry point for exporting highlights. User interface calls this function.
Parses current document and documents from history, passes them to exportClippings().
Highlight: Highlighted text or image in document, stored in "highlights" table in
documents sidecar file. Parser uses this table. If highlight._._.text field is empty parser uses
highlight._._.pboxes field to get an image instead.
Bookmarks: Data in bookmark explorer. Stored in "bookmarks" table of documents sidecar file. Every
field in bookmarks._ has "text" and "notes" fields When user edits a highlight or "renames" bookmark,
text field is created or updated. Parser looks to bookmarks._.text field for edited notes. bookmarks._.notes isn't used for exporting operations.
https://github.com/koreader/koreader/blob/605f6026bbf37856ee54741b8a0697337ca50039/plugins/evernote.koplugin/clip.lua#L229
Clippings: Parsed form of highlights, stored in clipboard/evernote.sdr/metadata.sdr.lua
for all documents. Used only for exporting bookmarks. Internal highlight or bookmark functions
does not use this table.
Booknotes: Every table in clippings table. clippings = {"title" = booknotes}
--]]
function Exporter:exportAllNotes()
    -- Flush highlights of current document.
    if not self:isDocless() then
        self.ui:saveSettings()
    end
    local clippings = self.config:readSetting("clippings") or {}
    clippings = self:updateHistoryClippings(clippings, self.parser:parseHistory())
    clippings = self:updateMyClippings(clippings, self.parser:parseMyClippings())
    -- remove blank entries
    for title, booknotes in pairs(clippings) do
        -- chapter number is zero
        if #booknotes == 0 then
            clippings[title] = nil
        end
    end
    --logger.dbg("clippings", clippings)
    self:exportClippings(clippings)
    self.config:saveSetting("clippings", clippings)
    self.config:flush()
end

function Exporter:exportClippings(clippings)
    local exported_stamp
    local joplin_client
    local readwise_client
    if self.html_export then
        exported_stamp= "html"
    elseif self.json_export then
        exported_stamp= "json"
    elseif self.txt_export then
        os.remove(self.text_clipping_file)
        exported_stamp = "txt"
    elseif self.joplin_export then
        exported_stamp = "joplin"
        joplin_client = JoplinClient:new{
            server_ip = self.joplin_IP,
            server_port = self.joplin_port,
            auth_token = self.joplin_token
        }
        ---@todo Check if user deleted our notebook, in that case note
        -- will end up in random folder in Joplin.
        if not self.joplin_notebook_guid then
            self.joplin_notebook_guid = joplin_client:createNotebook(self.notebook_name)
            self:saveSettings()
        end
    elseif self.readwise_export then
        exported_stamp = "readwise"
        readwise_client = ReadwiseClient:new{
            auth_token = self.readwise_token
        }
    else
        assert("an exported_stamp is expected for a new export type")
    end

    local export_count, error_count = 0, 0
    local export_title, error_title
    for title, booknotes in pairs(clippings) do
        if type(booknotes.exported) ~= "table" then
            booknotes.exported = {}
        end
        -- check if booknotes are exported in this notebook
        -- so that booknotes will still be exported after switching user account
        -- Don't respect exported_stamp on txt export since it isn't possible to delete(update) prior clippings.
        if booknotes.exported[exported_stamp] ~= true or self.txt_export or self.json_export then
            local ok, err
            if self.html_export then
                ok, err = pcall(self.exportBooknotesToHTML, self, title, booknotes)
            elseif self.txt_export then
                ok, err = pcall(self.exportBooknotesToTXT, self, title, booknotes)
            elseif self.json_export then
                ok, err = pcall(self.exportBooknotesToJSON, self, title, booknotes)
            elseif self.joplin_export then
                ok, err = pcall(self.exportBooknotesToJoplin, self, joplin_client, title, booknotes)
            elseif self.readwise_export then
                ok, err = pcall(self.exportBooknotesToReadwise, self, readwise_client, title, booknotes)
            end
            -- Error reporting
            if not ok and err and err:find("Transport not open") then
                --- @note: No recursive callback because it feels fishy here...
                NetworkMgr:beforeWifiAction()
                return
            elseif not ok and err then
                logger.dbg("Error while exporting book", title, err)
                error_count = error_count + 1
                error_title = title
            elseif ok then
                logger.dbg("Exported notes in book:", title)
                export_count = export_count + 1
                export_title = title
                booknotes.exported[exported_stamp] = true
            end
        end
    end

    local msg = "Nothing was exported."
    local all_count = export_count + error_count
    if export_count > 0 and error_count == 0 then
        msg = T(
            N_("Exported notes from the book:\n%1",
               "Exported notes from the book:\n%1\nand %2 others.",
               all_count-1),
            export_title,
            all_count-1
        )
    elseif error_count > 0 then
        msg = T(
            N_("An error occurred while trying to export notes from the book:\n%1",
               "Multiple errors occurred while trying to export notes from the book:\n%1\nand %2 others.",
               error_count-1),
            error_title,
            error_count-1
        )
    end
    if (self.html_export or self.txt_export) and export_count > 0 then
        msg = msg .. T(_("\nNotes can be found in %1/."), BD.dirpath(util.realpath(self.clipping_dir)))
    end
    UIManager:show(InfoMessage:new{ text = msg })
end

function Exporter:exportBooknotesToHTML(title, booknotes)
    local content = slt2.render(self.template, {
        booknotes = booknotes,
        notemarks = self.notemarks,
    })
    --logger.dbg("content", content)
    local html = io.open(self.clipping_dir .. "/" .. title .. ".html", "w")
    if html then
        html:write(content)
        html:close()
    end
end

function Exporter:prepareBooknotesForJSON(booknotes)
    local exportable = {
            title = booknotes.title,
            author = booknotes.author,
            entries = {},
            exported = booknotes.exported,
            file = booknotes.file
    }
    for _, entry in ipairs(booknotes) do
        table.insert(exportable.entries, entry[1])
    end
    return exportable
end

-- This function should handle both multidocument export and single exports.
-- For Single Exports, it will create a JSON file with a object ({}) as root node.
-- For Multidocument export, it will create a JSON file with an array ([]) as root node.
function Exporter:exportToJSON(clippings)
    local file = io.open(self.json_clipping_file, "a")
    if file then
        local exportable = {}
        if table.getn(clippings) == 1 then
            -- We will handle single document export here.
            exportable = self:prepareBooknotesForJSON(clippings[0])
        else
            for _, booknotes in ipairs(clippings) do
                table.insert(exportable, self:prepareBooknotesForJSON(booknotes))
            end
        end
        file:write(json.encode(exportable))
        file:write("\n")
        file:close()
    end
end

function Exporter:exportBooknotesToJSON(title, booknotes)
    logger.dbg("booknotes", booknotes)
    local file = io.open(self.json_clipping_file, "a")
    if file then
        local exportable = self:prepareBooknotesForJSON(booknotes)
        file:write(json.encode(exportable))
        file:write("\n")
        file:close()
    end
end

function Exporter:exportBooknotesToTXT(title, booknotes)
    -- Use wide_space to avoid crengine to treat it specially.
    local wide_space = "\227\128\128"
    local file = io.open(self.text_clipping_file, "a")
    if file then
        file:write(title .. "\n" .. wide_space .. "\n")
        for _ignore1, chapter in ipairs(booknotes) do
            if chapter.title then
                file:write(wide_space .. chapter.title .. "\n" .. wide_space .. "\n")
            end
            for _ignore2, clipping in ipairs(chapter) do
                file:write(wide_space .. wide_space ..
                            T(_("-- Page: %1, added on %2\n"),
                                clipping.page, os.date("%c", clipping.time)))
                if clipping.text then
                    file:write(clipping.text)
                end
                if clipping.note then
                    file:write("\n---\n" .. clipping.note)
                end
                if clipping.image then
                    file:write(_("<An image>"))
                end
                file:write("\n-=-=-=-=-=-\n")
            end
        end

        file:write("\n")
        file:close()
    end
end

function Exporter:exportBooknotesToJoplin(client, title, booknotes)
    if not client:ping() then
        error("Cannot reach Joplin server")
    end

    local note_guid = client:findNoteByTitle(title, self.joplin_notebook_guid)
    local note = ""
    for _, chapter in ipairs(booknotes) do
        if chapter.title then
            note = note .. "\n\t*" .. chapter.title .. "*\n\n * * *"
        end

        for _, clipping in ipairs(chapter) do
            note = note .. os.date("%Y-%m-%d %H:%M:%S \n", clipping.time)
            note = note .. clipping.text
            if clipping.note then
                note = note .. "\n---\n" .. clipping.note
            end
            note = note .. "\n * * *\n"
        end
    end

    if note_guid then
        client:updateNote(note_guid, note)
    else
        client:createNote(title, note, self.joplin_notebook_guid)
    end

end

function Exporter:exportBooknotesToReadwise(client, title, booknotes)
    client:createHighlights(booknotes)
end

return Exporter
