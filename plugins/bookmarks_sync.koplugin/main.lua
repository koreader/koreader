local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local UIManager = require("ui/uimanager")
local ButtonDialog = require("ui/widget/buttondialog")
local PathChooser = require("ui/widget/pathchooser")
local logger = require("logger")
local Trapper = require("ui/trapper")
local util = require("util")
local lfs = require("libs/libkoreader-lfs")
local l = require("gettext")
local T = require("ffi/util").template

local Anchoring = require("anchoring")
local SyncDB = require("sync_db")

local BookmarkSync = WidgetContainer:extend {
    name = "bookmarks_sync",
    title = l("Bookmarks Sync"),
    is_doc_only = true,
    device_id = nil,
    format = nil,
    book_id = nil,
    partial_md5 = nil,
    _is_importing = false,
    _book_ready = false,
}

function BookmarkSync:init()
    self.ui.menu:registerToMainMenu(self)
    self.device_id = G_reader_settings:readSetting("device_id")
    if not self.device_id then
        self.device_id = require("random").uuid()
        G_reader_settings:saveSetting("device_id", self.device_id)
    end
end

function BookmarkSync:addToMainMenu(menu_items)
    menu_items.bookmarks_sync = {
        text = self.title,
        sub_item_table = {
            {
                text = l("Sync highlights and bookmarks now"),
                keep_menu_open = false,
                callback = function()
                    self:exportLocalBookmarks()
                    self:importExternalBookmarks()
                    UIManager:show(InfoMessage:new {
                        text = l("Bookmarks sync completed successfully."),
                        timeout = 3,
                    })
                end,
            },
            {
                text = l("Sync shared folder"),
                help_text = l("Merge the local bookmark store with the Syncthing folder."),
                keep_menu_open = false,
                callback = function()
                    self:syncSharedFolder()
                end,
            },
            {
                text = l("Restore deleted bookmarks"),
                keep_menu_open = true,
                callback = function()
                    self:showRestoreDialog()
                end,
            },
            {
                text = l("Reset applied status for this book"),
                help_text = l("Re-search anchors for bookmarks that were previously marked as applied on this device."),
                callback = function()
                    self:resetSyncStatus()
                end,
            },
            {
                text = l("Settings"),
                sub_item_table_func = function()
                    return self:getSettingsMenu()
                end,
            },
        }
    }
end

function BookmarkSync:getSettingsMenu()
    local shared = SyncDB.getSharedRoot() or G_reader_settings:readSetting("bookmarks_sync_shared_path")
    return {
        {
            text = l("Shared folder (Syncthing)"),
            sub_text_func = function()
                return shared or l("Not set")
            end,
            keep_menu_open = true,
            callback = function()
                self:chooseSharedFolder()
            end,
        },
    }
end

function BookmarkSync:chooseSharedFolder()
    local start = SyncDB.getSharedRoot()
        or G_reader_settings:readSetting("bookmarks_sync_shared_path")
        or G_reader_settings:readSetting("home_dir")
        or SyncDB.getLocalRoot()
    UIManager:show(PathChooser:new {
        select_file = false,
        path = start,
        onConfirm = function(path)
            SyncDB.setSharedRoot(path)
            UIManager:show(InfoMessage:new {
                text = T(l("Shared folder set to:\n%1"), path),
                timeout = 3,
            })
        end,
    })
end

function BookmarkSync:ensureBookContext()
    local doc = self.ui.document
    if not doc or not doc.file then return false end
    if self._book_ready and self.book_id and self.partial_md5 then
        return true
    end
    SyncDB.migrateSidecar(doc.file, self.device_id)
    local book_id, fp, format = SyncDB.resolveBook(doc.file, self.device_id)
    if not book_id then return false end
    self.book_id = book_id
    self.partial_md5 = fp
    self.format = format
    self._book_ready = true
    return true
end

function BookmarkSync:resetSyncStatus()
    if not self:ensureBookContext() then
        UIManager:show(InfoMessage:new { text = l("No book is open.") })
        return
    end
    local root = SyncDB.getLocalRoot()
    local reset_count = 0
    -- Writing a new seen with journal 0 is wrong; instead markBack to force re-anchor,
    -- or simply remove the notion by creating back > seen. Plan: reset means clear applied
    -- by writing back so needsReanchor becomes true without deleting seen files.
    for _, mark in ipairs(SyncDB.listMarks(root, self.book_id)) do
        if SyncDB.isSeen(root, self.book_id, mark.datetime, self.device_id, self.partial_md5)
            and not SyncDB.isMarkGone(root, self.book_id, mark.datetime) then
            SyncDB.markBack(root, self.book_id, mark.datetime, self.device_id)
            reset_count = reset_count + 1
        end
    end
    if reset_count > 0 then
        local N_ = l.ngettext
        UIManager:show(InfoMessage:new {
            text = T(N_("Reset applied status for 1 bookmark.",
                "Reset applied status for %1 bookmarks.", reset_count), reset_count),
            timeout = 4,
        })
        UIManager:nextTick(function()
            self:importExternalBookmarks()
        end)
    else
        UIManager:show(InfoMessage:new {
            text = l("No bookmarks needed a status reset."),
            timeout = 3,
        })
    end
end

function BookmarkSync:showRestoreDialog()
    if not self:ensureBookContext() then
        UIManager:show(InfoMessage:new { text = l("No book is open.") })
        return
    end
    local root = SyncDB.getLocalRoot()
    local gone_marks = SyncDB.listGoneMarks(root, self.book_id)
    if #gone_marks == 0 then
        UIManager:show(InfoMessage:new {
            text = l("No deleted bookmarks to restore."),
            timeout = 3,
        })
        return
    end
    local buttons = {}
    for _, mark in ipairs(gone_marks) do
        local label = mark.exact or mark.datetime
        if #label > 60 then
            label = label:sub(1, 57) .. "…"
        end
        local datetime = mark.datetime
        table.insert(buttons, { {
            text = label,
            callback = function()
                SyncDB.markBack(root, self.book_id, datetime, self.device_id)
                UIManager:show(InfoMessage:new {
                    text = l("Bookmark restored."),
                    timeout = 2,
                })
                UIManager:nextTick(function()
                    self:importExternalBookmarks()
                end)
            end,
        } })
    end
    UIManager:show(ButtonDialog:new {
        title = l("Restore deleted bookmarks"),
        buttons = buttons,
    })
end

function BookmarkSync:resolveConflictsSequentially(conflicts, index, on_done)
    index = index or 1
    if index > #conflicts then
        if on_done then on_done() end
        return
    end
    local conflict = conflicts[index]
    local a = conflict.local_data or {}
    local b = conflict.remote_data or {}
    local function preview(bm)
        local parts = {}
        if bm.exact then table.insert(parts, bm.exact) end
        if bm.notes or bm.note then table.insert(parts, T(l("Note: %1"), bm.notes or bm.note)) end
        if bm.color then table.insert(parts, T(l("Color: %1"), bm.color)) end
        if bm.drawer then table.insert(parts, T(l("Style: %1"), bm.drawer)) end
        local text = table.concat(parts, "\n")
        if #text > 400 then text = text:sub(1, 397) .. "…" end
        return text ~= "" and text or l("(empty)")
    end
    UIManager:show(MultiConfirmBox:new {
        text = T(l("Bookmark conflict.\n\nThis device:\n%1\n\nOther copy:\n%2"),
            preview(a), preview(b)),
        choice1_text = l("Keep this device"),
        choice2_text = l("Keep other copy"),
        choice1_callback = function()
            conflict.choice = "local"
            self:applyConflictChoice(conflict)
            self:resolveConflictsSequentially(conflicts, index + 1, on_done)
        end,
        choice2_callback = function()
            conflict.choice = "remote"
            self:applyConflictChoice(conflict)
            self:resolveConflictsSequentially(conflicts, index + 1, on_done)
        end,
        cancel_callback = function()
            -- Leave unresolved; previous version stays.
            self:resolveConflictsSequentially(conflicts, index + 1, on_done)
        end,
    })
end

function BookmarkSync:applyConflictChoice(conflict)
    if not conflict or not conflict.choice or not conflict.rel then return end
    local root = SyncDB.getLocalRoot()
    local chosen = conflict.choice == "local" and conflict.local_data or conflict.remote_data
    chosen = util.tableDeepCopy(chosen)
    chosen.loc = SyncDB.mergeLoc(
        (conflict.local_data and conflict.local_data.loc) or {},
        (conflict.remote_data and conflict.remote_data.loc) or {}
    )
    SyncDB.writeLua(root .. "/" .. conflict.rel, chosen)
    local _, log_rel = SyncDB.appendJournal(root, conflict.rel, self.device_id)
    -- Re-queue for push to shared
    local pending = G_reader_settings:readSetting("bookmarks_sync_pending") or {}
    local function queue(rel)
        for _, p in ipairs(pending) do
            if p == rel then return end
        end
        table.insert(pending, rel)
    end
    queue(conflict.rel)
    queue(log_rel)
    G_reader_settings:saveSetting("bookmarks_sync_pending", pending)

    if conflict.conflict_path and lfs.attributes(conflict.conflict_path, "mode") == "file" then
        os.remove(conflict.conflict_path)
    end
    local shared = SyncDB.getSharedRoot()
    if shared then
        SyncDB.writeLua(shared .. "/" .. conflict.rel, chosen)
        for _, cpath in ipairs(SyncDB.findConflictCopies(shared, conflict.rel)) do
            os.remove(cpath)
        end
        SyncDB.appendJournal(shared, conflict.rel, self.device_id)
    end
end

function BookmarkSync:syncSharedFolder()
    if not SyncDB.getSharedRoot() and not G_reader_settings:readSetting("bookmarks_sync_shared_path") then
        UIManager:show(InfoMessage:new {
            text = l("Set the shared Syncthing folder in Bookmarks Sync settings first."),
            timeout = 4,
        })
        return
    end
    -- Collect conflicts during pull without blocking; resolve after.
    local pending_conflicts = {}
    local ok, err = SyncDB.pullShared(self.device_id, function(conflict)
        table.insert(pending_conflicts, conflict)
        return nil -- defer choice
    end)
    if not ok then
        UIManager:show(InfoMessage:new {
            text = err == "no_shared"
                and l("Shared folder is not available.")
                or l("Could not read the shared folder."),
            timeout = 4,
        })
        return
    end

    local function finish_push()
        local pushed, perr = SyncDB.pushShared(self.device_id)
        if not pushed then
            UIManager:show(InfoMessage:new {
                text = perr == "no_shared"
                    and l("Shared folder is not available.")
                    or l("Could not update the shared folder."),
                timeout = 4,
            })
            return
        end
        UIManager:show(InfoMessage:new {
            text = l("Shared folder sync finished."),
            timeout = 3,
        })
        if self.ui.document and self.ui.document.file then
            UIManager:nextTick(function()
                self:importExternalBookmarks()
            end)
        end
    end

    if #pending_conflicts > 0 then
        self:resolveConflictsSequentially(pending_conflicts, 1, finish_push)
    else
        finish_push()
    end
end

function BookmarkSync:onReaderReady()
    logger.dbg("bookmarks_sync: onReaderReady triggered")
    local doc = self.ui.document
    if not doc or not doc.file then
        logger.dbg("bookmarks_sync: onReaderReady: no document or file.")
        return
    end
    self._book_ready = false
    if not self:ensureBookContext() then return end
    self:exportLocalBookmarks()
    UIManager:nextTick(function()
        self:importExternalBookmarks()
    end)
end

function BookmarkSync:onSaveSettings()
    logger.dbg("bookmarks_sync: onSaveSettings triggered. Exporting local bookmarks.")
    self:exportLocalBookmarks()
end

function BookmarkSync:onAnnotationsModified(event)
    if self._is_importing then
        logger.dbg("bookmarks_sync: onAnnotationsModified skipped during import.")
        return
    end
    UIManager:nextTick(function()
        self:exportLocalBookmarks()
    end)
end

function BookmarkSync:exportLocalBookmarks()
    logger.dbg("bookmarks_sync: exportLocalBookmarks started.")
    if not self:ensureBookContext() then return end
    local doc = self.ui.document
    local total_pages = doc:getPageCount()
    if not total_pages or total_pages <= 0 then return end

    local root = SyncDB.getLocalRoot()
    local annotations = self.ui.annotation.annotations or {}
    local current_datetimes = {}
    local is_reflowable = not (doc.is_pdf or doc.is_djvu)

    for i, item in ipairs(annotations) do
        if item.datetime and not item.deleted and not item.is_service_note then
            current_datetimes[item.datetime] = true
            pcall(function()
                local exact, prefix, suffix = Anchoring.getAnchorContext(doc, item, 5)
                local pageno = is_reflowable and doc:getPageFromXPointer(item.page) or item.pageno
                local progress = pageno / total_pages
                local loc = {
                    [self.partial_md5] = {
                        format = self.format,
                        pos0 = item.pos0,
                        pos1 = item.pos1,
                        page = item.page,
                        pageno = item.pageno,
                        pboxes = item.pboxes,
                    },
                }
                SyncDB.upsertMarkFromAnnotation(root, self.book_id, {
                    datetime = item.datetime,
                    progress = progress,
                    exact = exact,
                    prefix = prefix,
                    suffix = suffix,
                    drawer = item.drawer,
                    color = item.color,
                    notes = item.note or item.notes,
                    loc = loc,
                }, self.device_id)
                -- Local annotation present counts as seen for this fingerprint.
                if not SyncDB.isSeen(root, self.book_id, item.datetime, self.device_id, self.partial_md5) then
                    SyncDB.markSeen(root, self.book_id, item.datetime, self.device_id, self.partial_md5)
                end
            end)
        end
    end

    -- Marks present in store but missing from the book → gone (unless soft-miss / not yet applied).
    for _, mark in ipairs(SyncDB.listMarks(root, self.book_id)) do
        if not current_datetimes[mark.datetime] then
            local gone = SyncDB.isMarkGone(root, self.book_id, mark.datetime)
            local seen = SyncDB.isSeen(root, self.book_id, mark.datetime, self.device_id, self.partial_md5)
            local has_loc = mark.loc and mark.loc[self.partial_md5]
            -- Soft miss: already tried and marked seen without a local annotation.
            -- Hard delete: was seen with loc / was in this book before.
            if gone == false and seen and has_loc then
                -- If annotation vanished after being applied here, treat as user delete.
                -- Heuristic: if it had loc for this fp and is no longer in annotations.
                SyncDB.markGone(root, self.book_id, mark.datetime, self.device_id)
                logger.dbg("bookmarks_sync: Marking bookmark as gone:", mark.datetime)
            end
        end
    end
    logger.dbg("bookmarks_sync: exportLocalBookmarks finished.")
end

function BookmarkSync:importExternalBookmarks()
    if not self:ensureBookContext() then return end
    local doc = self.ui.document
    local root = SyncDB.getLocalRoot()
    local marks = SyncDB.listMarks(root, self.book_id)
    if #marks == 0 then
        logger.dbg("bookmarks_sync: No bookmarks in store to import.")
        return
    end

    local local_annotations = self.ui.annotation.annotations or {}
    local local_by_datetime = {}
    for _, local_bm in ipairs(local_annotations) do
        if local_bm.datetime then
            local_by_datetime[local_bm.datetime] = true
        end
    end

    local bookmarks_to_import = {}
    for _, mark in ipairs(marks) do
        local gone = SyncDB.isMarkGone(root, self.book_id, mark.datetime)
        if gone then
            -- skip deleted
        elseif gone == nil then
            -- ambiguous gone/back same journal number → ask
            table.insert(bookmarks_to_import, { mark = mark, ambiguous = true })
        elseif local_by_datetime[mark.datetime] then
            -- already in book; still may need loc for this fingerprint
            if SyncDB.needsReanchor(root, self.book_id, mark.datetime, self.device_id, self.partial_md5)
                and not (mark.loc and mark.loc[self.partial_md5]) then
                table.insert(bookmarks_to_import, { mark = mark })
            end
        elseif SyncDB.needsReanchor(root, self.book_id, mark.datetime, self.device_id, self.partial_md5)
            or not SyncDB.isSeen(root, self.book_id, mark.datetime, self.device_id, self.partial_md5) then
            table.insert(bookmarks_to_import, { mark = mark })
        end
    end

    -- Resolve ambiguous gone/back first.
    local ambiguous = {}
    local normal = {}
    for _, item in ipairs(bookmarks_to_import) do
        if item.ambiguous then
            table.insert(ambiguous, item.mark)
        else
            table.insert(normal, item.mark)
        end
    end

    local function do_import(list)
        if #list == 0 then
            if #ambiguous == 0 then
                logger.dbg("bookmarks_sync: No new bookmarks to import.")
            end
            return
        end

        local info = InfoMessage:new { text = l("Syncing bookmarks… (tap to cancel)") }
        UIManager:show(info)
        UIManager:forceRePaint()

        local completed, results = Trapper:dismissableRunInSubprocess(function()
            local subprocess_results = { found = {}, unfound = {} }
            for i, ext_bm in ipairs(list) do
                local found_in_subprocess = false
                -- Prefer existing coordinates for this fingerprint.
                local loc = ext_bm.loc and ext_bm.loc[self.partial_md5]
                if loc and loc.pos0 and (loc.page or loc.pageno) then
                    found_in_subprocess = true
                    table.insert(subprocess_results.found, {
                        pos0 = loc.pos0,
                        pos1 = loc.pos1,
                        page = loc.page or loc.pageno,
                        pboxes = loc.pboxes,
                        exact = ext_bm.exact,
                        datetime = ext_bm.datetime,
                        drawer = ext_bm.drawer,
                        color = ext_bm.color,
                        notes = ext_bm.notes or ext_bm.note,
                        from_loc = true,
                    })
                else
                    pcall(function()
                        local pos0, pos1, page = Anchoring.findAnchor(doc, ext_bm, self.ui.view.state)
                        if pos0 and page then
                            found_in_subprocess = true
                            table.insert(subprocess_results.found, {
                                pos0 = pos0,
                                pos1 = pos1,
                                page = page,
                                exact = ext_bm.exact,
                                datetime = ext_bm.datetime,
                                drawer = ext_bm.drawer,
                                color = ext_bm.color,
                                notes = ext_bm.notes or ext_bm.note,
                            })
                        end
                    end)
                end
                if not found_in_subprocess then
                    table.insert(subprocess_results.unfound, ext_bm)
                end
            end
            return subprocess_results
        end, info)

        UIManager:close(info)
        if not completed then
            logger.info("bookmarks_sync: Import cancelled by user.")
            return
        end

        local found_bookmarks = (results and results.found) or {}
        local unfound_bookmarks = (results and results.unfound) or {}
        local is_reflowable = not (doc.is_pdf or doc.is_djvu)
        local imported_count = 0
        self._is_importing = true

        for _, item_data in ipairs(found_bookmarks) do
            if not local_by_datetime[item_data.datetime] then
                if item_data.drawer then
                    local item = {
                        pos0 = item_data.pos0,
                        pos1 = item_data.pos1,
                        text = item_data.exact,
                        datetime = item_data.datetime or os.date("%Y-%m-%d %H:%M:%S"),
                        drawer = item_data.drawer,
                        color = item_data.color,
                        notes = item_data.notes,
                        chapter = self.ui.toc:getTocTitleByPage(item_data.page),
                    }
                    if is_reflowable then
                        item.page = item_data.pos0
                    else
                        item.page = item_data.page
                        item.pboxes = item_data.pboxes
                            or doc:getPageBoxesFromPositions(item_data.page, item_data.pos0, item_data.pos1)
                        pcall(function() self.ui.highlight:writePdfAnnotation("save", item) end)
                    end
                    local index = self.ui.annotation:addItem(item)
                    self.ui:handleEvent(Event:new("AnnotationsModified",
                        { item, nb_highlights_added = 1, index_modified = index }))
                else
                    local pn_or_xp = is_reflowable and doc:getPageXPointer(item_data.page) or item_data.page
                    local chapter = self.ui.toc:getTocTitleByPage(pn_or_xp)
                    local text = chapter and chapter ~= "" and T(l("in %1"), chapter) or ""
                    local item = {
                        page = pn_or_xp,
                        text = text,
                        chapter = chapter,
                        datetime = item_data.datetime,
                    }
                    local index = self.ui.annotation:addItem(item)
                    self.ui:handleEvent(Event:new("AnnotationsModified", { item, index_modified = index }))
                end
                imported_count = imported_count + 1
                local_by_datetime[item_data.datetime] = true
            end

            -- Persist loc for this fingerprint and mark seen.
            local existing = SyncDB.readMark(root, self.book_id, item_data.datetime) or {
                datetime = item_data.datetime,
                exact = item_data.exact,
                drawer = item_data.drawer,
                color = item_data.color,
                notes = item_data.notes,
            }
            existing.loc = existing.loc or {}
            if not item_data.from_loc then
                existing.loc[self.partial_md5] = {
                    format = self.format,
                    pos0 = item_data.pos0,
                    pos1 = item_data.pos1,
                    page = item_data.page,
                }
                SyncDB.writeMark(root, self.book_id, existing, self.device_id, true)
            end
            SyncDB.markSeen(root, self.book_id, item_data.datetime, self.device_id, self.partial_md5)
        end
        self._is_importing = false

        if #unfound_bookmarks > 0 then
            local unfound_texts = {}
            for _, unfound_bm in ipairs(unfound_bookmarks) do
                SyncDB.markSeen(root, self.book_id, unfound_bm.datetime, self.device_id, self.partial_md5)
                table.insert(unfound_texts, unfound_bm.exact or unfound_bm.datetime)
            end
            local N_ = l.ngettext
            UIManager:show(InfoMessage:new {
                text = T(N_("Could not sync 1 bookmark. A note has been added to the book.",
                    "Could not sync %1 bookmarks. A note has been added to the book.", #unfound_texts), #unfound_texts),
                timeout = 5,
            })
            local service_note_text = T(l("The following %1 bookmarks could not be synced in this document format:\n"),
                #unfound_texts)
            for _, text in ipairs(unfound_texts) do
                service_note_text = service_note_text .. "\n• " .. text
            end
            local service_item_page, service_pos0, service_pos1
            if is_reflowable then
                service_item_page = doc:getPageXPointer(1)
                service_pos0 = service_item_page
                service_pos1 = service_item_page
            else
                service_item_page = 1
                service_pos0 = { page = 1, x = 10, y = 10 }
                service_pos1 = { page = 1, x = 20, y = 20 }
            end
            local service_item = {
                pos0 = service_pos0,
                pos1 = service_pos1,
                text = service_note_text,
                datetime = os.date("%Y-%m-%d %H:%M:%S"),
                drawer = "lighten",
                color = "red",
                notes = service_note_text,
                chapter = self.ui.toc:getTocTitleByPage(service_item_page),
                page = service_item_page,
                is_service_note = true,
            }
            self._is_importing = true
            local index = self.ui.annotation:addItem(service_item)
            self.ui:handleEvent(Event:new("AnnotationsModified",
                { service_item, nb_highlights_added = 1, index_modified = index }))
            self._is_importing = false
        end

        if imported_count > 0 then
            local N_ = l.ngettext
            UIManager:show(InfoMessage:new {
                text = T(N_("Synced 1 bookmark from another format",
                    "Synced %1 bookmarks from other formats", imported_count), imported_count),
                timeout = 3,
            })
            self.ui:handleEvent(Event:new("ForceRepaint"))
        end
    end

    if #ambiguous > 0 then
        local function ask_next(i)
            if i > #ambiguous then
                do_import(normal)
                return
            end
            local mark = ambiguous[i]
            UIManager:show(MultiConfirmBox:new {
                text = T(l("Bookmark was both deleted and restored.\n\n%1\n\nWhat should be kept?"),
                    mark.exact or mark.datetime),
                choice1_text = l("Keep deleted"),
                choice2_text = l("Restore"),
                choice1_callback = function()
                    SyncDB.markGone(root, self.book_id, mark.datetime, self.device_id)
                    ask_next(i + 1)
                end,
                choice2_callback = function()
                    SyncDB.markBack(root, self.book_id, mark.datetime, self.device_id)
                    table.insert(normal, mark)
                    ask_next(i + 1)
                end,
                cancel_callback = function()
                    ask_next(i + 1)
                end,
            })
        end
        ask_next(1)
    else
        do_import(normal)
    end
end

return BookmarkSync
