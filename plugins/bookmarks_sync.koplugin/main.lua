local WidgetContainer = require("ui/widget/container/widgetcontainer")
local LuaSettings = require("luasettings")
local logger = require("logger")

local MyBackupPlugin = WidgetContainer:extend{
    name = "my_bookmark_backup",
}

function MyBackupPlugin:init()
    -- Регистрируем плагин в главном меню
    self.ui.menu:registerToMainMenu(self)
end

-- Событие 1: Срабатывает при любом изменении закладок/выделений в интерфейсе
function MyBackupPlugin:onAnnotationsModified(event)
    logger.info("MyBackupPlugin: Аннотации изменились!", event)
    
    -- Пример: получить текущий список всех аннотаций книги
    local annotations = self.ui.annotation.annotations
    
    -- Здесь можно вызвать вашу функцию нормализации и записи
    self:updateMyCustomBackup(annotations)
end

-- Событие 2: Срабатывает при сохранении настроек книги на флешку
function MyBackupPlugin:onSaveSettings()
    logger.info("MyBackupPlugin: Настройки книги сохраняются.")
    
    -- Получаем доступ к стандартному хранилищу настроек текущей книги (.sdr)
    local doc_settings = self.ui.doc_settings
    local annotations = doc_settings:readSetting("annotations")
    
    self:updateMyCustomBackup(annotations)
end

-- Ваша функция для обработки и бэкапа
function MyBackupPlugin:updateMyCustomBackup(annotations)
    if not annotations then return end
    
    -- 1. Нормализуем данные (вытаскиваем текст, контекст, прогресс)
    local export_data = {}
    for i, item in ipairs(annotations) do
        table.insert(export_data, {
            id = item.datetime .. "_" .. i, -- Уникальный локальный ID
            progress = item.pageno / self.ui.document:getPageCount(), -- Относительный прогресс
            exact = item.text, -- Выделенный текст
            note = item.note, -- Заметка пользователя
            deleted = item.deleted or false
        })
    end
    
    -- 2. Записываем в свой собственный файл (например, в общую папку бэкапов)
    local backup_filepath = "/sdcard/koreader/my_sync_bookmarks.lua"
    local my_db = LuaSettings:open(backup_filepath)
    
    -- Используем имя книги в качестве ключа
    local book_title = self.ui.document.info.title or "unknown_book"
    my_db:saveSetting(book_title, export_data)
    my_db:flush() -- Запись на диск
    
    logger.info("MyBackupPlugin: Бэкап обновлен для книги: " .. book_title)
end

return MyBackupPlugin
