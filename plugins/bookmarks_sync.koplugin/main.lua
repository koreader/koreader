local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
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
            }
        }
    }
end

-- Срабатывает, когда книга полностью готова к чтению
function BookmarkSync:onReaderReady()
    -- Проверяем переименование текущей книги и инициализируем файл bookmarks_sync.lua
    local doc = self.ui.document
    if doc and doc.file then
        local sync_data = SyncDB.loadBookSync(doc.file)
        local base_name = SyncDB.getBaseName(doc.file)
        
        if sync_data then
            -- Если открытый файл переименован
            if sync_data.current_basename ~= base_name then
                self:exportLocalBookmarks()
            end
        else
            -- Первичный экспорт, если файла синхронизации еще нет
            self:exportLocalBookmarks()
        end
        
        -- Автоматический импорт закладок из других форматов при открытии книги
        UIManager:nextTick(function()
            self:importExternalBookmarks()
        end)
    end
end

-- Срабатывает при сохранении настроек книги (обычно при закрытии или выходе в меню)
function BookmarkSync:onSaveSettings()
    self:exportLocalBookmarks()
end

-- Срабатывает при добавлении/удалении/изменении закладок в интерфейсе
function BookmarkSync:onAnnotationsModified(event)
    -- Небольшая задержка перед экспортом, чтобы KOReader успел применить изменения к сессии
    UIManager:nextTick(function()
        self:exportLocalBookmarks()
    end)
end

-- Экспорт локальных закладок в bookmarks_sync.lua
function BookmarkSync:exportLocalBookmarks()
    local doc = self.ui.document
    if not doc or not doc.file then return end
    
    local total_pages = doc:getPageCount()
    if not total_pages or total_pages <= 0 then return end
    
    local annotations = self.ui.annotation.annotations or {}
    local sync_bookmarks = {}
    
    for _, item in ipairs(annotations) do
        if not item.deleted then
            local exact, prefix, suffix = Anchoring.getAnchorContext(doc, item, 5)
            
            -- Вычисляем прогресс.
            -- Для PDF/DjVu (paging) у нас есть item.pageno.
            -- Для EPUB/FB2 (reflowable) у нас есть item.page, который является xpointer-ом.
            -- Нам нужно получить номер страницы из xpointer-а в любом режиме (rolling или paging).
            local pageno
            if doc.configurable and doc.configurable.text_wrap == 1 then -- Reflowable
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
                note = item.note or item.notes
            })
        end
    end
    
    SyncDB.saveBookSync(doc.file, sync_bookmarks)
end

-- Импорт закладок из других форматов
function BookmarkSync:importExternalBookmarks()
    local doc = self.ui.document
    if not doc or not doc.file then return end
    
    local matches = SyncDB.findMatchingSyncFiles(doc.file)
    if #matches == 0 then
        logger.info("bookmarks_sync: Нет подходящих файлов для синхронизации.")
        return
    end
    
    local local_annotations = self.ui.annotation.annotations or {}
    local imported_count = 0
    
    for _, match in ipairs(matches) do
        for _, ext_bm in ipairs(match.bookmarks) do
            -- Проверяем, нет ли уже этой закладки локально (по совпадению текста или времени)
            local exists = false
            for _, local_bm in ipairs(local_annotations) do
                if local_bm.datetime == ext_bm.datetime or 
                   (ext_bm.exact ~= "" and local_bm.text == ext_bm.exact) then
                    exists = true
                    break
                end
            end
            
            if not exists and not ext_bm.deleted then
                -- Ищем позицию текста в текущем документе
                local pos0, pos1, page = Anchoring.findAnchor(doc, ext_bm, self.ui)
                if pos0 and page then
                    -- Добавляем закладку/выделение локально
                    if ext_bm.drawer then
                        -- Это выделение (highlight)
                        local item = {
                            page = self.ui.paging and page or pos0,
                            pos0 = pos0,
                            pos1 = pos1,
                            text = ext_bm.exact,
                            datetime = ext_bm.datetime or os.date("%Y-%m-%d %H:%M:%S"),
                            drawer = ext_bm.drawer,
                            color = ext_bm.color,
                            note = ext_bm.note,
                            chapter = self.ui.toc:getTocTitleByPage(page),
                        }
                        if self.ui.paging then
                            -- Для PDF вычисляем pboxes
                            item.pboxes = doc:getPageBoxesFromPositions(page, pos0, pos1)
                            pcall(function() self.ui.highlight:writePdfAnnotation("save", item) end)
                        end
                        
                        local index = self.ui.annotation:addItem(item)
                        self.ui:handleEvent(Event:new("AnnotationsModified", {
                            item, 
                            nb_highlights_added = 1, 
                            index_modified = index
                        }))
                        imported_count = imported_count + 1
                    else
                        -- Это простая закладка (bookmark)
                        if not self.ui.bookmark:isPageBookmarked(page) then
                            self.ui.bookmark:toggleBookmark(page)
                            imported_count = imported_count + 1
                        end
                    end
                end
            end
        end
    end
    
    if imported_count > 0 then
        logger.info("bookmarks_sync: Импортировано закладок из других форматов:", imported_count)
        self.view.footer:maybeUpdateFooter()
        if self.ui.bookmark.bookmark_menu then
            self.ui.bookmark:updateBookmarkList()
        end
    end
end

return BookmarkSync
