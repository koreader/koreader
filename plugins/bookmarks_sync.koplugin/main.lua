local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local ButtonDialog = require("ui/widget/buttondialog")
local logger = require("logger")
local Trapper = require("ui/trapper")
local l = require("gettext")

local Anchoring = require("anchoring")
local SyncDB = require("sync_db")

local BookmarkSync = WidgetContainer:extend {
    name = "bookmarks_sync",
    title = l("Bookmarks Sync"),
    is_doc_only = true,
    device_id = nil,
    format = nil,
    _is_importing = false,
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
                text = l("Reset sync status for this book"),
                help_text = l(
                    "This will allow re-importing bookmarks that were previously not found in this book format."),
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
    local menu = {}
    table.insert(menu, {
        text = l("Search scope"),
        sub_text_func = function()
            local scope = G_reader_settings:readSetting("bookmarks_sync_search_scope") or "all"
            if scope == "known" then
                return l("Known books only (History/Cache)")
            elseif scope == "folder" then
                return l("Current folder and subfolders")
            else
                return l("All sources (recommended)")
            end
        end,
        callback = function() self:showSearchScopeDialog() end,
    })
    return menu
end

function BookmarkSync:showSearchScopeDialog()
    local current_scope = G_reader_settings:readSetting("bookmarks_sync_search_scope") or "all"
    local dialog
    local buttons = {}
    local scopes = {
        { key = "all",    text = l("All sources"),         sub_text = l("Both of the above. Most reliable.") },
        { key = "known",  text = l("Known books only"),    sub_text = l("History and cache. Fastest.") },
        { key = "folder", text = l("Current folder only"), sub_text = l("Scans current book's folder and subfolders.") },
    }
    for _, scope_info in ipairs(scopes) do
        table.insert(buttons, { {
            text = scope_info.text,
            sub_text = scope_info.sub_text,
            checked = current_scope == scope_info.key,
            radio = true,
            callback = function()
                G_reader_settings:saveSetting("bookmarks_sync_search_scope", scope_info.key)
                if dialog then UIManager:close(dialog) end
            end,
        } })
    end

    dialog = ButtonDialog:new {
        title = l("Select search scope for sync"),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function BookmarkSync:resetSyncStatus()
    local doc = self.ui.document
    if not doc or not doc.file then
        UIManager:show(InfoMessage:new { text = l("No book is open.") })
        return
    end

    local sync_data = SyncDB.loadBookSync(doc.file)
    if not sync_data or not sync_data.bookmarks or #sync_data.bookmarks == 0 then
        UIManager:show(InfoMessage:new { text = l("No sync data found for this book.") })
        return
    end

    local reset_count = 0
    for _, bm in ipairs(sync_data.bookmarks) do
        if bm.synced_to and bm.synced_to[self.device_id] and bm.synced_to[self.device_id][self.format] then
            bm.synced_to[self.device_id][self.format] = nil
            reset_count = reset_count + 1
        end
    end

    if reset_count > 0 then
        SyncDB.saveBookSync(doc.file, sync_data.bookmarks)
        local N_ = l.ngettext
        local T = require("ffi/util").template
        UIManager:show(InfoMessage:new {
            text = T(N_("Reset sync status for 1 bookmark. It will be re-imported on next sync.", "Reset sync status for %1 bookmarks. They will be re-imported on next sync.", reset_count), reset_count),
            timeout = 4,
        })
        -- Trigger import right away
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

-- Срабатывает, когда книга полностью готова к чтению
function BookmarkSync:onReaderReady()
    logger.dbg("bookmarks_sync: onReaderReady triggered")
    -- Проверяем переименование текущей книги и инициализируем файл bookmarks_sync.lua
    local doc = self.ui.document
    if doc and doc.file then
        local sync_data = SyncDB.loadBookSync(doc.file)
        self.format = doc.file:match("%.([^.]+)$")
        logger.dbg("bookmarks_sync: onReaderReady processing for", doc.file, sync_data)
        local base_name = SyncDB.getBaseName(doc.file)

        if sync_data then
            -- Если открытый файл переименован
            if sync_data.current_basename ~= base_name then
                self:exportLocalBookmarks()
            end
        else
            logger.dbg("bookmarks_sync: No sync data found. Doing initial export.")
            -- Первичный экспорт, если файла синхронизации еще нет
            self:exportLocalBookmarks()
        end

        -- Автоматический импорт закладок из других форматов при открытии книги
        UIManager:nextTick(function()
            logger.dbg("bookmarks_sync: Scheduling importExternalBookmarks")
            self:importExternalBookmarks()
        end)
    else
        logger.dbg("bookmarks_sync: onReaderReady: no document or file.")
    end
end

-- Срабатывает при сохранении настроек книги (обычно при закрытии или выходе в меню)
function BookmarkSync:onSaveSettings()
    logger.dbg("bookmarks_sync: onSaveSettings triggered. Exporting local bookmarks.")
    self:exportLocalBookmarks()
end

-- Срабатывает при добавлении/удалении/изменении закладок в интерфейсе
function BookmarkSync:onAnnotationsModified(event)
    if self._is_importing then
        logger.dbg("bookmarks_sync: onAnnotationsModified skipped during import.")
        return
    end
    -- Небольшая задержка перед экспортом, чтобы KOReader успел применить изменения к сессии
    UIManager:nextTick(function()
        logger.dbg("bookmarks_sync: onAnnotationsModified triggered. Scheduling export.")
        self:exportLocalBookmarks()
    end)
end

-- Экспорт локальных закладок в bookmarks_sync.lua
function BookmarkSync:exportLocalBookmarks()
    logger.dbg("bookmarks_sync: exportLocalBookmarks started.")
    local doc = self.ui.document
    if not doc or not doc.file then
        logger.dbg("bookmarks_sync: exportLocalBookmarks: no document or file. Aborting.")
        return
    end

    local total_pages = doc:getPageCount()
    if not total_pages or total_pages <= 0 then
        logger.dbg("bookmarks_sync: exportLocalBookmarks: invalid page count. Aborting.")
        return
    end

    -- Загружаем существующие закладки из файла синхронизации, чтобы выполнить слияние, а не перезапись.
    local sync_data = SyncDB.loadBookSync(doc.file)
    local existing_sync_bookmarks = (sync_data and sync_data.bookmarks) or {}
    local sync_bookmarks_map = {}
    for _, bm in ipairs(existing_sync_bookmarks) do
        if bm.datetime then
            sync_bookmarks_map[bm.datetime] = bm
        end
    end

    -- Получаем текущие аннотации из книги
    local annotations = self.ui.annotation.annotations or {}
    logger.dbg("bookmarks_sync: Found", #annotations, "total local annotations to process.")
    local current_datetimes = {}

    -- Обновляем или добавляем закладки на основе текущих аннотаций
    for i, item in ipairs(annotations) do
        if item.datetime and not item.deleted and not item.is_service_note then
            current_datetimes[item.datetime] = true -- Отмечаем, что эта закладка все еще активна

            -- Всегда обновляем якорь и данные, чтобы они были актуальными.
            -- Это проще и надежнее, чем пытаться отследить изменения.
            pcall(function()
                logger.dbg("bookmarks_sync: Exporting/updating annotation #", i, item.datetime)
                local exact, prefix, suffix = Anchoring.getAnchorContext(doc, item, 5)
                logger.dbg("bookmarks_sync: exportLocalBookmarks: Context for", item.datetime, "-> prefix:", prefix,
                    "suffix:", suffix)
                local is_reflowable = not (doc.is_pdf or doc.is_djvu)
                local pageno = is_reflowable and doc:getPageFromXPointer(item.page) or item.pageno
                local progress = pageno / total_pages

                -- Get existing bookmark from map to preserve its sync history
                local bm = sync_bookmarks_map[item.datetime] or { datetime = item.datetime }

                -- Update fields with fresh data from the book
                bm.progress = progress
                bm.exact = exact
                bm.prefix = prefix
                bm.suffix = suffix
                bm.drawer = item.drawer
                bm.color = item.color
                bm.notes = item.note or item.notes
                bm.deleted = nil -- Mark as not deleted

                -- Put it back in the map
                sync_bookmarks_map[item.datetime] = bm
            end)
        end
    end

    -- Отмечаем как удаленные те закладки, которые есть в файле синхронизации, но отсутствуют в книге
    for datetime, bm in pairs(sync_bookmarks_map) do
        if not current_datetimes[datetime] then
            -- Проверяем, была ли закладка "мягко удалена" для этого формата во время импорта.
            -- Если да, то ожидается, что она будет отсутствовать, и мы не должны ее "жестко" удалять.
            local is_soft_deleted = bm.synced_to and bm.synced_to[self.device_id] and
            bm.synced_to[self.device_id][self.format]
            if not is_soft_deleted then
                logger.dbg("bookmarks_sync: Marking bookmark as deleted:", datetime)
                bm.deleted = true
            else
                logger.dbg("bookmarks_sync: Bookmark was not found in this format, but keeping it for other formats:",
                    datetime)
            end
        end
    end

    -- Преобразуем карту обратно в список для сохранения
    local final_sync_bookmarks = {}
    for _, bm in pairs(sync_bookmarks_map) do
        table.insert(final_sync_bookmarks, bm)
    end

    logger.dbg("bookmarks_sync: Saving", #final_sync_bookmarks, "bookmarks to sync file.")
    SyncDB.saveBookSync(doc.file, final_sync_bookmarks)
    logger.dbg("bookmarks_sync: exportLocalBookmarks finished.")
end

-- Импорт закладок из других форматов
function BookmarkSync:importExternalBookmarks()
    local doc = self.ui.document
    logger.dbg("bookmarks_sync: importExternalBookmarks started for", doc and doc.file or "nil")
    if not doc or not doc.file then return end

    local sync_data = SyncDB.loadBookSync(doc.file)
    if not sync_data or not sync_data.bookmarks or #sync_data.bookmarks == 0 then
        logger.dbg("bookmarks_sync: No bookmarks found in the sync file to import.")
        return
    end

    logger.dbg("bookmarks_sync: Found", #sync_data.bookmarks, "bookmarks in sync file for potential import.")

    -- Create a lookup map of existing local bookmarks for faster checks.
    local local_annotations = self.ui.annotation.annotations or {}
    local local_bookmarks_by_datetime = {}
    for _, local_bm in ipairs(local_annotations) do
        if local_bm.datetime then
            local_bookmarks_by_datetime[local_bm.datetime] = true
        end
    end

    -- Filter bookmarks that actually need to be imported
    local bookmarks_to_import = {}
    for _, ext_bm in ipairs(sync_data.bookmarks) do
        local is_already_imported = (ext_bm.synced_to and ext_bm.synced_to[self.device_id] and ext_bm.synced_to[self.device_id][self.format])
        if not ext_bm.deleted and not is_already_imported and not local_bookmarks_by_datetime[ext_bm.datetime] then
            table.insert(bookmarks_to_import, ext_bm)
        end
    end

    if #bookmarks_to_import == 0 then
        logger.dbg("bookmarks_sync: No new bookmarks to import from other formats.")
        UIManager:show(InfoMessage:new {
            text = l("Bookmarks are already up to date."),
            timeout = 2,
        })
        return
    end

    local T = require("ffi/util").template

    -- Show a dismissable "working" message to inform the user that we're busy.
    local info = InfoMessage:new { text = l("Syncing bookmarks… (tap to cancel)") }
    UIManager:show(info)
    UIManager:forceRePaint() -- Make sure it's shown before we block

    local doc = self.ui.document
    local completed, results = Trapper:dismissableRunInSubprocess(function()
        -- This part runs in a subprocess and can be slow.
        local subprocess_results = {
            found = {},
            unfound = {},
        }
        for i, ext_bm in ipairs(bookmarks_to_import) do
            local found_in_subprocess = false
            pcall(function() -- Wrap each findAnchor attempt for safety
                logger.dbg("bookmarks_sync: [subprocess] Attempting to find anchor for bookmark #", i, ext_bm.datetime)
                local pos0, pos1, page = Anchoring.findAnchor(doc, ext_bm, self.ui.view.state)
                if pos0 and page then
                    logger.dbg("bookmarks_sync: [subprocess] Anchor found on page", page)
                    found_in_subprocess = true
                    -- We can't pass the full ext_bm table back because it might contain
                    -- complex data. We pass back only what's necessary to create
                    -- the annotation item in the main thread.
                    table.insert(subprocess_results.found, {
                        pos0 = pos0,
                        pos1 = pos1,
                        page = page,
                        -- Pass original bookmark data needed for creation
                        exact = ext_bm.exact,
                        datetime = ext_bm.datetime,
                        drawer = ext_bm.drawer,
                        color = ext_bm.color,
                        notes = ext_bm.notes,
                    })
                end
            end)
            if not found_in_subprocess then
                -- Pass back the original bookmark data for reporting
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

    if #found_bookmarks == 0 and #unfound_bookmarks == 0 then
        logger.info("bookmarks_sync: No new bookmarks found in document to import.")
        return
    end

    -- This part runs back in the main UI thread and should be fast.
    local is_reflowable = not (doc.is_pdf or doc.is_djvu)
    local imported_count = 0
    self._is_importing = true -- Prevent onAnnotationsModified from triggering exports for each imported item
    for _, item_data in ipairs(found_bookmarks) do
        if item_data.drawer then
            -- This is a highlight
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
                item.pboxes = doc:getPageBoxesFromPositions(item_data.page, item_data.pos0, item_data.pos1)
                logger.dbg("bookmarks_sync: item.pboxes = ", item.pboxes)
                if item.pboxes and #item.pboxes > 0 then
                    local box_texts = {}
                    for _, box in ipairs(item.pboxes) do
                        local box_pos0 = { x = box.x, y = box.y, page = item_data.page }
                        local box_pos1 = { x = box.x + box.w, y = box.y + box.h, page = item_data.page }
                        local ok, res = pcall(doc.getTextFromPositions, doc, box_pos0, box_pos1, true)
                        if ok and res and res.text then
                            table.insert(box_texts, res.text)
                        end
                    end
                    logger.dbg("bookmarks_sync: Text from pboxes:", table.concat(box_texts, " "))
                    logger.dbg("bookmarks_sync: pboxes details:", item.pboxes)
                end
                pcall(function() self.ui.highlight:writePdfAnnotation("save", item) end)
            end
            local index = self.ui.annotation:addItem(item)
            self.ui:handleEvent(Event:new("AnnotationsModified",
                { item, nb_highlights_added = 1, index_modified = index }))
        else
            -- This is a simple bookmark (dog-ear).
            local pn_or_xp = is_reflowable and doc:getPageXPointer(item_data.page) or item_data.page
            local chapter = self.ui.toc:getTocTitleByPage(pn_or_xp)
            local text = chapter and chapter ~= "" and T(l("in %1"), chapter) or ""
            local item = {
                page = pn_or_xp,
                text = text,
                chapter = chapter,
                datetime = item_data.datetime, -- Preserve the original datetime
            }
            local index = self.ui.annotation:addItem(item)
            self.ui:handleEvent(Event:new("AnnotationsModified", { item, index_modified = index }))
        end
        imported_count = imported_count + 1
        -- Mark as imported for this device/format
        for _, ext_bm in ipairs(sync_data.bookmarks) do
            if ext_bm.datetime == item_data.datetime then
                ext_bm.synced_to = ext_bm.synced_to or {}
                ext_bm.synced_to[self.device_id] = ext_bm.synced_to[self.device_id] or {}
                ext_bm.synced_to[self.device_id][self.format] = true
                logger.dbg("bookmarks_sync: Imported bookmark", item_data.datetime)
                break
            end
        end
    end
    self._is_importing = false -- Re-enable exports

    -- Handle bookmarks that were not found
    if #unfound_bookmarks > 0 then
        local unfound_texts = {}
        for _, unfound_bm in ipairs(unfound_bookmarks) do
            -- Mark as "synced" for this device/format to prevent future import attempts
            for _, ext_bm in ipairs(sync_data.bookmarks) do
                if ext_bm.datetime == unfound_bm.datetime then
                    ext_bm.synced_to = ext_bm.synced_to or {}
                    ext_bm.synced_to[self.device_id] = ext_bm.synced_to[self.device_id] or {}
                    ext_bm.synced_to[self.device_id][self.format] = true -- "soft delete" for this format
                    logger.warn(
                        "bookmarks_sync: Could not find anchor for bookmark, marking as synced to prevent retries:",
                        unfound_bm.datetime)
                    break
                end
            end
            -- Collect text for the service note
            table.insert(unfound_texts, unfound_bm.exact)
        end

        local N_ = l.ngettext
        local message = T(
            N_("Could not sync 1 bookmark. A note has been added to the book.",
                "Could not sync %1 bookmarks. A note has been added to the book.", #unfound_texts), #unfound_texts)
        UIManager:show(InfoMessage:new { text = message, timeout = 5 })

        -- Create a service note with the list of unfound bookmarks
        local service_note_text = T(l("The following %1 bookmarks could not be synced in this document format:\n"),
            #unfound_texts)
        for i, text in ipairs(unfound_texts) do
            service_note_text = service_note_text .. "\n• " .. text
        end

        local service_item_page
        local service_pos0, service_pos1
        if is_reflowable then
            service_item_page = doc:getPageXPointer(1)
            service_pos0 = service_item_page
            service_pos1 = service_item_page
        else
            service_item_page = 1
            service_pos0 = { page = 1, x = 10, y = 10 } -- Dummy coordinates on page 1
            service_pos1 = { page = 1, x = 20, y = 20 }
        end

        local service_item = {
            pos0 = service_pos0,
            pos1 = service_pos1,
            text = service_note_text, -- "Выделенный" текст, видимый в списке закладок
            datetime = os.date("%Y-%m-%d %H:%M:%S"),
            drawer = "lighten",
            color = "red",             -- Use a distinct color
            notes = service_note_text, -- Содержимое всплывающей заметки
            chapter = self.ui.toc:getTocTitleByPage(service_item_page),
            page = service_item_page,
            is_service_note = true -- Special flag to prevent export
        }
        -- Add it to the document
        self._is_importing = true
        local index = self.ui.annotation:addItem(service_item)
        self.ui:handleEvent(Event:new("AnnotationsModified",
            { service_item, nb_highlights_added = 1, index_modified = index }))
        self._is_importing = false
    end

    if imported_count > 0 then
        logger.dbg("bookmarks_sync: Imported a total of", imported_count, "bookmarks.")

        -- Save the `synced_to` flags we've just set.
        SyncDB.saveBookSync(doc.file, sync_data.bookmarks)

        -- Now that all bookmarks are imported, trigger a single export to ensure consistency.
        self:exportLocalBookmarks()

        local N_ = l.ngettext
        UIManager:show(InfoMessage:new {
            text = T(N_("Synced 1 bookmark from another format", "Synced %1 bookmarks from other formats", imported_count), imported_count),
            timeout = 3,
        })

        -- Force a full UI refresh to ensure all new bookmarks are displayed
        self.ui:handleEvent(Event:new("ForceRepaint"))
    end
end

return BookmarkSync
