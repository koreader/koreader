local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local ButtonDialog = require("ui/widget/buttondialog")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

local Anchoring = require("anchoring")
local SyncDB = require("sync_db")

local BookmarkSync = WidgetContainer:extend{
    name = "bookmarks_sync",
    title = _("Bookmarks Sync"),
    is_doc_only = true,
}

function BookmarkSync:init()
    self.ui.menu:registerToMainMenu(self)
end

function BookmarkSync:addToMainMenu(menu_items)
    menu_items.bookmarks_sync = {
        text = self.title,
        sub_item_table = {
            {
                text = _("Sync highlights and bookmarks now"),
                keep_menu_open = false,
                callback = function()
                    self:exportLocalBookmarks()
                    self:importExternalBookmarks()
                    UIManager:show(InfoMessage:new{
                        text = _("Bookmarks sync completed successfully."),
                        timeout = 3,
                    })
                end,
            },
            {
                text = _("Settings"),
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
        text = _("Search scope"),
        sub_text_func = function()
            local scope = G_reader_settings:readSetting("bookmarks_sync_search_scope") or "all"
            if scope == "known" then
                return _("Known books only (History/Cache)")
            elseif scope == "folder" then
                return _("Current folder and subfolders")
            else
                return _("All sources (recommended)")
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
        { key = "all",    text = _("All sources"),    sub_text = _("Both of the above. Most reliable.") },
        { key = "known",  text = _("Known books only"),  sub_text = _("History and cache. Fastest.") },
        { key = "folder", text = _("Current folder only"), sub_text = _("Scans current book's folder and subfolders.") },
    }
    for _, scope_info in ipairs(scopes) do
        table.insert(buttons, {{
            text = scope_info.text,
            sub_text = scope_info.sub_text,
            checked = current_scope == scope_info.key,
            radio = true,
            callback = function()
                G_reader_settings:saveSetting("bookmarks_sync_search_scope", scope_info.key)
                if dialog then UIManager:close(dialog) end
            end,
        }})
    end

    dialog = ButtonDialog:new{
        title = _("Select search scope for sync"),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

-- Срабатывает, когда книга полностью готова к чтению
function BookmarkSync:onReaderReady()
    logger.dbg("bookmarks_sync: onReaderReady triggered")
    -- Проверяем переименование текущей книги и инициализируем файл bookmarks_sync.lua
    local doc = self.ui.document
    if doc and doc.file then
        local sync_data = SyncDB.loadBookSync(doc.file)
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
    -- Небольшая задержка перед экспортом, чтобы KOReader успел применить изменения к сессии
    UIManager:nextTick(function()
        logger.dbg("bookmarks_sync: onAnnotationsModified triggered. Scheduling export.")
        self:exportLocalBookmarks()
    end)
end

-- Экспорт локальных закладок в bookmarks_sync.lua
function BookmarkSync:exportLocalBookmarks()
    local doc = self.ui.document
    logger.dbg("bookmarks_sync: exportLocalBookmarks started.")
    if not doc or not doc.file then
        logger.dbg("bookmarks_sync: exportLocalBookmarks: no document or file. Aborting.")
        return
    end
    
    local total_pages = doc:getPageCount()
    if not total_pages or total_pages <= 0 then
        logger.dbg("bookmarks_sync: exportLocalBookmarks: invalid page count. Aborting.")
        return
    end
    
    local annotations = self.ui.annotation.annotations or {}
    logger.dbg("bookmarks_sync: Found", #annotations, "total local annotations.")
    local sync_bookmarks = {}
    
    for i, item in ipairs(annotations) do
        if not item.deleted then
            logger.dbg("bookmarks_sync: Exporting annotation #", i, item.datetime)
            local exact, prefix, suffix = Anchoring.getAnchorContext(doc, item, 5)
            logger.dbg("bookmarks_sync: Anchor context:", {exact=exact, prefix=prefix, suffix=suffix})
            local is_reflowable = not (doc.is_pdf or doc.is_djvu)
            local pageno
            if is_reflowable then -- Reflowable
                pageno = doc:getPageFromXPointer(item.page)
            else -- Fixed-layout
                pageno = item.pageno
            end
            local progress = pageno / total_pages
            
            table.insert(sync_bookmarks, {
                datetime = item.datetime,
                progress = progress,
                exact = exact,
                prefix = prefix,
                suffix = suffix,
                drawer = item.drawer,
                color = item.color,
                notes = item.note or item.notes
            })
        end
    end
    
    logger.dbg("bookmarks_sync: Saving", #sync_bookmarks, "bookmarks to sync file.")
    SyncDB.saveBookSync(doc.file, sync_bookmarks)
    logger.dbg("bookmarks_sync: exportLocalBookmarks finished.")
end

-- Импорт закладок из других форматов
function BookmarkSync:importExternalBookmarks()
    local doc = self.ui.document
    logger.dbg("bookmarks_sync: importExternalBookmarks started for", doc and doc.file or "nil")
    if not doc or not doc.file then return end
    
    local matches = SyncDB.findMatchingSyncFiles(doc.file)
    if #matches == 0 then
        logger.dbg("bookmarks_sync: No matching files found for sync.")
        return
    end
    
    logger.dbg("bookmarks_sync: Found", #matches, "matching files for sync.")
    local local_annotations = self.ui.annotation.annotations or {}
    local imported_count = 0
    local is_reflowable = not (doc.is_pdf or doc.is_djvu)
    
    for _, match in ipairs(matches) do
        logger.dbg("bookmarks_sync: Processing match file:", match.filepath)
        pcall(function() -- Обертка для безопасности, чтобы ошибка в одном файле не сломала все
            for i, ext_bm in ipairs(match.bookmarks) do
                logger.dbg("bookmarks_sync: Checking external bookmark #", i, ext_bm.datetime)
                -- Проверяем, нет ли уже этой закладки локально
                local exists = false
                for _, local_bm in ipairs(local_annotations) do
                    if local_bm.datetime == ext_bm.datetime or (ext_bm.exact ~= "" and local_bm.text == ext_bm.exact) then
                        exists = true
                        break
                    end
                end
                
                if not exists and not ext_bm.deleted then
                    logger.dbg("bookmarks_sync: Bookmark does not exist locally. Attempting to find anchor.")
                    local pos0, pos1, page = Anchoring.findAnchor(doc, ext_bm, self.ui)
                    logger.dbg("bookmarks_sync: findAnchor result:", {pos0=pos0, pos1=pos1, page=page})
                    if pos0 and page then
                        logger.dbg("bookmarks_sync: Anchor found on page", page, ". Importing.")
                        if ext_bm.drawer then
                            -- Это выделение (highlight)
                            local item = {
                                pos0 = pos0, pos1 = pos1, text = ext_bm.exact,
                                datetime = ext_bm.datetime or os.date("%Y-%m-%d %H:%M:%S"),
                                drawer = ext_bm.drawer, color = ext_bm.color, notes = ext_bm.notes,
                                chapter = self.ui.toc:getTocTitleByPage(page),
                            }
                            logger.dbg("item (1) = ", item)
                            if is_reflowable then
                                -- For EPUB, the 'page' field must be the starting xpointer of the highlight,
                                -- which is what findAnchor returns in pos0.
                                item.page = pos0
                            else
                                -- Для PDF/DjVu 'page' - это всегда номер страницы.
                                item.page = page
                                item.pboxes = doc:getPageBoxesFromPositions(page, pos0, pos1)
                                pcall(function() self.ui.highlight:writePdfAnnotation("save", item) end)
                            end
                            logger.dbg("item (2) = ", item)
                            local index = self.ui.annotation:addItem(item)
                            self.ui:handleEvent(Event:new("AnnotationsModified", {
                                item, nb_highlights_added = 1, index_modified = index
                            }))
                            imported_count = imported_count + 1
                            logger.dbg("bookmarks_sync: Imported a highlight.")
                        else
                            -- Это простая закладка (bookmark)
                            local bm_page = page
                            if is_reflowable then
                                -- Для EPUB-документов нужно передавать xpointer, а не номер страницы.
                                bm_page = doc:getXPointerFromPage(page)
                            end
                            if not self.ui.bookmark:isPageBookmarked(bm_page) then
                                self.ui.bookmark:toggleBookmark(bm_page)
                                imported_count = imported_count + 1
                                logger.dbg("bookmarks_sync: Imported a bookmark.")
                            else
                                logger.dbg("bookmarks_sync: Page already bookmarked, skipping.")
                            end
                        end
                    else
                        logger.dbg("bookmarks_sync: Anchor not found for this bookmark. Skipping.")
                    end
                else
                    logger.dbg("bookmarks_sync: Bookmark already exists or is deleted. Skipping.")
                end
            end
        end)
    end
    
    if imported_count > 0 then
        logger.dbg("bookmarks_sync: Imported a total of", imported_count, "bookmarks.")
        local T = require("ffi/util").template
        local N_ = _.ngettext
        UIManager:show(InfoMessage:new{
            text = T(N_("Synced 1 bookmark from another format", "Synced %1 bookmarks from other formats", imported_count), imported_count),
            timeout = 3,
        })
        -- Принудительно обновляем весь интерфейс, чтобы гарантированно отобразить все новые закладки
        self.ui:handleEvent(Event:new("ForceRepaint"))
    elseif #matches > 0 then
        logger.dbg("bookmarks_sync: No new bookmarks to import from other formats.")
        UIManager:show(InfoMessage:new{
            text = _("Bookmarks are already up to date."),
            timeout = 2,
        })
    end
end

return BookmarkSync
