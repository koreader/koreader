local InputContainer = require("ui/widget/container/inputcontainer")
local LoginDialog = require("ui/widget/logindialog")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local UIManager = require("ui/uimanager")
local ConfirmBox = require("ui/widget/confirmbox")
local Screen = require("device").screen
local util = require("ffi/util")
local Device = require("device")
local DEBUG = require("dbg")
local T = require("ffi/util").template
local _ = require("gettext")
local slt2 = require('slt2')
local MyClipping = require("clip")
local realpath = require("ffi/util").realpath

local EvernoteExporter = InputContainer:new{
    name = "evernote",
    login_title = _("Login to Evernote"),
    notebook_name = _("KOReader Notes"),
    evernote_domain = nil,
    notemarks = _("Note: "),
    clipping_dir = DataStorage:getDataDir() .. "/clipboard",

    evernote_token = nil,
    notebook_guid = nil,
}

function EvernoteExporter:init()
    self.text_clipping_file = self.clipping_dir .. "/KOReaderClipping.txt"
    local settings = G_reader_settings:readSetting("evernote") or {}
    self.evernote_domain = settings.domain
    self.evernote_username = settings.username or ""
    self.evernote_token = settings.token
    self.notebook_guid = settings.notebook
    self.html_export = settings.html_export or false
    if self.html_export then
        self.txt_export = false
    else
        self.txt_export = settings.txt_export or false
    end

    self.parser = MyClipping:new{
        my_clippings = "/mnt/us/documents/My Clippings.txt",
        history_dir = "./history",
    }
    self.template = slt2.loadfile(self.path.."/note.tpl")
    self:migrateClippings()
    self.config = DocSettings:open(util.joinPath(self.clipping_dir, "evernote.sdr"))

    self.ui.menu:registerToMainMenu(self)
end

function EvernoteExporter:isDocless()
    return self.ui == nil or self.ui.document == nil or self.view == nil
end

function EvernoteExporter:readyToExport()
    return self.evernote_token ~= nil or self.html_export ~= false or self.txt_export ~= false
end

function EvernoteExporter:migrateClippings()
    local old_dir = util.joinPath(util.realpath(util.joinPath(self.path, "..")),
        "evernote.sdr")
    if lfs.attributes(old_dir, "mode") == "directory" then
        local mv_bin = Device:isAndroid() and "/system/bin/mv" or "/bin/mv"
        return util.execute(mv_bin, old_dir, self.clipping_dir) == 0
    end
end

function EvernoteExporter:addToMainMenu(menu_items)
    menu_items.evernote = {
        text = _("Evernote"),
        sub_item_table = {
            {
                text_func = function()
                    local domain
                    if self.evernote_domain == "sandbox" then
                        domain = "Sandbox"
                    elseif self.evernote_domain == "yinxiang" then
                        domain = "Yinxiang"
                    else
                        domain = "Evernote"
                    end
                    return self.evernote_token and (_("Logout") .. " " .. domain)
                            or _("Login")
                end,
                callback_func = function()
                    return self.evernote_token and function() self:logout() end
                            or nil
                end,
                sub_item_table_func = function()
                    return not self.evernote_token and {
                        {
                            text = "Evernote",
                            callback = function()
                                self.evernote_domain = nil
                                self:login()
                            end
                        },
                        {
                            text = "印象笔记",
                            callback = function()
                                self.evernote_domain = "yinxiang"
                                self:login()
                            end
                        }
                    } or nil
                end,
            },
            {
                text = _("Export all notes in this book"),
                enabled_func = function()
                    return not self:isDocless() and self:readyToExport() and not self.txt_export
                end,
                callback = function()
                    UIManager:scheduleIn(0.5, function()
                        self:exportCurrentNotes(self.view)
                    end)

                    UIManager:show(InfoMessage:new{
                        text = _("Exporting may take several seconds…"),
                        timeout = 1,
                    })
                end
            },
            {
                text = _("Export all notes in your library"),
                enabled_func = function()
                    return self:readyToExport()
                end,
                callback = function()
                    UIManager:scheduleIn(0.5, function()
                        self:exportAllNotes()
                    end)

                    UIManager:show(InfoMessage:new{
                        text = _("Exporting may take several minutes…"),
                        timeout = 1,
                    })
                end
            },
            {
                text = _("Export to local HTML files"),
                checked_func = function() return self.html_export end,
                callback = function()
                    self.html_export = not self.html_export
                    if self.html_export then self.txt_export = false end
                    self:saveSettings()
                end
            },
            {
                text = _("Export to local clipping text file"),
                checked_func = function() return self.txt_export end,
                callback = function()
                    self.txt_export = not self.txt_export
                    if self.txt_export then self.html_export = false end
                    self:saveSettings()
                end
            },
            {
                text = _("Purge history records"),
                callback = function()
                    self.config:purge()
                    UIManager:show(ConfirmBox:new{
                        text = _("History records have been purged.\nAll notes will be exported again next time.\nWould you like to remove the existing KOReaderClipping.txt file to avoid duplication?\nRecords will be appended to KOReaderClipping.txt instead of being overwritten."),
                        ok_text = _("Yes, remove it"),
                        ok_callback = function()
                            os.remove(self.text_clipping_file)
                        end,
                        cancel_text = _("No, keep it"),
                    })
                end
            }
        }
    }
end

function EvernoteExporter:login()
    if not NetworkMgr:isOnline() then
        NetworkMgr:promptWifiOn()
    end
    self.login_dialog = LoginDialog:new{
        title = self.login_title,
        username = self.evernote_username or "",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    enabled = true,
                    callback = function()
                        self:closeDialog()
                    end,
                },
                {
                    text = _("Login"),
                    enabled = true,
                    callback = function()
                        local username, password = self:getCredential()
                        self:closeDialog()
                        UIManager:scheduleIn(0.5, function()
                            self:doLogin(username, password)
                        end)

                        UIManager:show(InfoMessage:new{
                            text = _("Logging in. Please wait…"),
                            timeout = 1,
                        })
                    end,
                },
            },
        },
        width = Screen:getWidth() * 0.8,
        height = Screen:getHeight() * 0.4,
    }

    self.login_dialog:onShowKeyboard()
    UIManager:show(self.login_dialog)
end

function EvernoteExporter:closeDialog()
    self.login_dialog:onClose()
    UIManager:close(self.login_dialog)
end

function EvernoteExporter:getCredential()
    return self.login_dialog:getCredential()
end

function EvernoteExporter:doLogin(username, password)
    local EvernoteOAuth = require("EvernoteOAuth")
    local EvernoteClient = require("EvernoteClient")

    local oauth = EvernoteOAuth:new{
        domain = self.evernote_domain,
        username = username,
        password = password,
    }
    self.evernote_username = username
    local ok, token = pcall(oauth.getToken, oauth)
    -- prompt users to turn on Wifi if network is unreachable
    if not ok and token then
        UIManager:show(InfoMessage:new{
            text = _("An error occurred while logging in:") .. "\n" .. token,
        })
        return
    end

    local client = EvernoteClient:new{
        domain = self.evernote_domain,
        authToken = token,
    }
    local guid
    ok, guid = pcall(self.getExportNotebook, self, client)
    if not ok and guid and guid:find("Transport not open") then
        NetworkMgr:promptWifiOn()
        return
    elseif not ok and guid then
        UIManager:show(InfoMessage:new{
            text = _("An error occurred while logging in:") .. "\n" .. guid,
        })
    elseif ok and guid then
        self.evernote_token = token
        self.notebook_guid = guid
        UIManager:show(InfoMessage:new{
            text = _("Logged in to Evernote."),
        })
    end

    self:saveSettings()
end

function EvernoteExporter:logout()
    self.evernote_token = nil
    self.notebook_guid = nil
    self.evernote_domain = nil
    self:saveSettings()
end

function EvernoteExporter:saveSettings()
    local settings = {
        domain = self.evernote_domain,
        username = self.evernote_username,
        token = self.evernote_token,
        notebook = self.notebook_guid,
        html_export = self.html_export,
        txt_export = self.txt_export,
    }
    G_reader_settings:saveSetting("evernote", settings)
end

function EvernoteExporter:getExportNotebook(client)
    local name = self.notebook_name
    return client:findNotebookByTitle(name) or client:createNotebook(name).guid
end

function EvernoteExporter:exportCurrentNotes(view)
    local clippings = self.parser:parseCurrentDoc(view)
    self:exportClippings(clippings)
end

function EvernoteExporter:updateHistoryClippings(clippings, new_clippings)
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
                    DEBUG("found new notes in history", booknotes.title)
                    clippings[title] = booknotes
                end
            end
        end
    end
    return clippings
end

function EvernoteExporter:updateMyClippings(clippings, new_clippings)
    -- only new titles or new notes in My clippings are updated to clippings
    -- since appending is the only way to modify notes in My Clippings
    for title, booknotes in pairs(new_clippings) do
        if clippings[title] == nil or #clippings[title] < #booknotes then
            DEBUG("found new notes in MyClipping", booknotes.title)
            clippings[title] = booknotes
        end
    end
    return clippings
end

function EvernoteExporter:exportAllNotes()
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
    --DEBUG("clippings", clippings)
    self:exportClippings(clippings)
    self.config:saveSetting("clippings", clippings)
    self.config:flush()
end

function EvernoteExporter:exportClippings(clippings)
    local client = nil
    local exported_stamp
    if not self.html_export and not self.txt_export then
        client = require("EvernoteClient"):new{
            domain = self.evernote_domain,
            authToken = self.evernote_token,
        }
        exported_stamp = self.notebook_guid
    elseif self.html_export then
        exported_stamp= "html"
    elseif self.txt_export then
        exported_stamp = "txt"
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
        if booknotes.exported[exported_stamp] ~= true then
            local ok, err
            if self.html_export then
                ok, err = pcall(self.exportBooknotesToHTML, self, title, booknotes)
            elseif self.txt_export then
                ok, err = pcall(self.exportBooknotesToTXT, self, title, booknotes)
            else
                ok, err = pcall(self.exportBooknotesToEvernote, self, client, title, booknotes)
            end
            -- error reporting
            if not ok and err and err:find("Transport not open") then
                NetworkMgr:promptWifiOn()
                return
            elseif not ok and err then
                DEBUG("Error occurs when exporting book:", title, err)
                error_count = error_count + 1
                error_title = title
            elseif ok then
                DEBUG("Exported notes in book:", title)
                export_count = export_count + 1
                export_title = title
                booknotes.exported[exported_stamp] = true
            end
        end
    end

    local msg = "Nothing was exported."
    local all_count = export_count + error_count
    if export_count > 0 and error_count == 0 then
        if all_count == 1 then
            msg = _("Exported notes from book:") .. "\n" .. export_title
        else
            msg = T(
                _("Exported notes from book:\n%1\nand %2 others."),
                export_title,
                all_count-1
            )
        end
    elseif error_count > 0 then
        if all_count == 1 then
            msg = _("An error occurred while trying to export notes from book:") .. "\n" .. error_title
        else
            msg = T(
                _("Multiple errors occurred while trying to export notes from book:\n%1\nand %2 others."),
                error_title,
                error_count-1
            )
        end
    end
    if (self.html_export or self.txt_export) and export_count > 0 then
        msg = msg .. T(_("\nNotes can be found in %1/."), realpath(self.clipping_dir))
    end
    UIManager:show(InfoMessage:new{ text = msg })
end

function EvernoteExporter:exportBooknotesToEvernote(client, title, booknotes)
    local content = slt2.render(self.template, {
        booknotes = booknotes,
        notemarks = self.notemarks,
    })
    --DEBUG("content", content)
    local note_guid = client:findNoteByTitle(title, self.notebook_guid)
    local resources = {}
    for _, chapter in ipairs(booknotes) do
        for _, clipping in ipairs(chapter) do
            if clipping.image then
                table.insert(resources, {
                    image = clipping.image
                })
                -- nullify clipping image after passing it to evernote client
                clipping.image = nil
            end
        end
    end
    if not note_guid then
        client:createNote(title, content, resources, {}, self.notebook_guid)
    else
        client:updateNote(note_guid, title, content, resources, {}, self.notebook_guid)
    end
end

function EvernoteExporter:exportBooknotesToHTML(title, booknotes)
    local content = slt2.render(self.template, {
        booknotes = booknotes,
        notemarks = self.notemarks,
    })
    --DEBUG("content", content)
    local html = io.open(self.clipping_dir .. "/" .. title .. ".html", "w")
    if html then
        html:write(content)
        html:close()
    end
end

function EvernoteExporter:exportBooknotesToTXT(title, booknotes)
    -- Use wide_space to avoid crengine to treat it specially.
    local wide_space = "\227\128\128"
    local file_modification = lfs.attributes(self.text_clipping_file, "modification") or 0
    local file = io.open(self.text_clipping_file, "a")
    if file then
        file:write(title .. "\n" .. wide_space .. "\n")
        for _ignore1, chapter in ipairs(booknotes) do
            if chapter.title then
                file:write(wide_space .. chapter.title .. "\n" .. wide_space .. "\n")
            end
            for _ignore2, clipping in ipairs(chapter) do
                -- If this clipping has already been exported, we ignore it.
                if clipping.time >= file_modification then
                    file:write(wide_space .. wide_space ..
                               T(_("-- Page: %1, added on %2\n"),
                                 clipping.page, os.date("%c", clipping.time)))
                    if clipping.text then
                        file:write(clipping.text)
                    end
                    if clipping.image then
                        file:write(_("<An image>"))
                    end
                    file:write("\n-=-=-=-=-=-\n")
                end
            end
        end

        file:write("\n")
        file:close()
    end
end

return EvernoteExporter
