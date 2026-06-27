local Utf8Proc = require("ffi/utf8proc")
local logger = require("logger")

local Anchoring = {}

-- Нормализация строки для нечеткого поиска и сравнения контекста
function Anchoring.normalizeText(str)
    if not str or type(str) ~= "string" then return "" end
    
    -- Приведение к нижнему регистру
    str = Utf8Proc.lowercase(str)
    
    -- Замена ё -> е
    str = str:gsub("ё", "е")
    
    -- Удаление знаков препинания, скобок, кавычек и лишних пробелов
    str = str:gsub("[%s%p%c%z]", "")
    
    return str
end

-- Безопасное получение контекста для выделения или закладки
-- @param doc - экземпляр документа (self.ui.document)
-- @param item - элемент аннотации (bookmark/highlight)
-- @param nb_words - количество слов контекста (по умолчанию 5)
-- @return exact, prefix, suffix
function Anchoring.getAnchorContext(doc, item, nb_words)
    nb_words = nb_words or 10
    local exact, prefix, suffix = "", "", ""
    
    if item.drawer then
        -- Это выделение (highlight) или заметка (note)
        exact = item.text or item.notes or ""
        
        -- Пытаемся извлечь контекст средствами KOReader
        if doc.getSelectedWordContext and item.pos0 and item.pos1 then
            -- HACK: Для PDF/DjVu getSelectedWordContext зависит от глобального состояния
            -- koptinterface.last_text_boxes. Мы должны принудительно заполнить его
            -- перед вызовом, чтобы получить контекст для уже существующих закладок.
            -- Для CreDocument (EPUB) это не требуется, т.к. у него своя реализация.
            local koptinterface
            if doc.is_pdf or doc.is_djvu then
                koptinterface = require("document/koptinterface")
                koptinterface.last_text_boxes = doc:getTextBoxes(item.page)
            end

            local ok, p, s = pcall(doc.getSelectedWordContext, doc, exact, nb_words, item.pos0, item.pos1)
            if ok and p and s then
                prefix = p
                suffix = s
            else
                logger.warn("bookmarks_sync: Не удалось извлечь контекст для выделения через getSelectedWordContext")
            end
            if koptinterface then
                koptinterface.last_text_boxes = nil -- Очищаем состояние после себя
            end
        else
            logger.warn("bookmarks_sync: Не выполнены условия для getSelectedWordContext")
        end
    else
        -- Это простая закладка страницы (dogear)
        -- Для закладки у нас нет выделенного текста. Нам нужно извлечь
        -- первые 50-60 символов текста с начала страницы/экрана.
        if doc.configurable and doc.configurable.text_wrap == 1 then
            -- EPUB / FB2 (Reflowable)
            if doc.getTextFromXPointer and item.page then
                local t = doc:getTextFromXPointer(item.page)
                if t and t ~= "" then
                    exact = t:sub(1, 100)
                end
            end
        else
            -- PDF / DjVu (Fixed-layout)
            if doc.getTextFromPositions and item.page then
                local screen_w = doc.width or 800
                local screen_h = doc.height or 1024
                local ok, res = pcall(doc.getTextFromPositions, doc, 
                    { x = 0, y = 0, page = item.page }, 
                    { x = screen_w, y = screen_h, page = item.page }, 
                    true
                )
                if ok and res and res.text and res.text ~= "" then
                    exact = res.text:sub(1, 100)
                end
            end
        end
        
        -- Если удалось извлечь начало страницы как exact, берем контекст справа
        if exact ~= "" then
            exact = exact:gsub("^%s+", "") -- убираем ведущие пробелы
            -- Ограничим до 5 слов
            local words = {}
            for w in exact:gmatch("%S+") do
                table.insert(words, w)
                if #words >= 6 then break end
            end
            if #words > 0 then
                exact = table.concat(words, " ", 1, math.min(#words, 5))
            end
        end
    end
    
    return exact, prefix, suffix
end

-- Локальный поиск текста якоря в окрестности сохраненного прогресса
-- @param doc - экземпляр документа
-- @param anchor - объект якоря { exact, prefix, suffix, progress }
-- @return pos0, pos1, page (координаты найденного совпадения в текущем документе)
function Anchoring.findAnchor(doc, anchor, ui)
    if not anchor.exact or anchor.exact == "" then return nil end
    
    local total_pages = doc:getPageCount()
    if not total_pages or total_pages <= 0 then return nil end
    
    -- Вычисляем примерную страницу в текущем документе
    local estimated_page = math.floor(anchor.progress * total_pages)
    if estimated_page < 1 then estimated_page = 1 end
    if estimated_page > total_pages then estimated_page = total_pages end
    
    -- Запускаем поиск совпадений по всей книге с ограничением на количество результатов
    local nb_context_words = 5
    local max_hits = 100
    local case_insensitive = true
    local search_flags = 0x01FF -- IGNORE_DIACRITICS + NORMALIZE_COMPATIBILITY
    
    local ok, res
    if doc.configurable and doc.configurable.text_wrap == 1 then
        -- EPUB / FB2 (CreDocument)
        ok, res = pcall(doc.findAllText, doc, anchor.exact, case_insensitive, nb_context_words, max_hits, false, search_flags)
    else
        -- PDF (PdfDocument)
        ok, res = pcall(doc.findAllText, doc, anchor.exact, case_insensitive, nb_context_words, max_hits)
    end
    
    if not ok or not res or #res == 0 then
        return nil -- Совпадений не найдено
    end
    
    local best_match = nil
    local best_score = -1000
    
    local target_prefix_norm = Anchoring.normalizeText(anchor.prefix)
    local target_suffix_norm = Anchoring.normalizeText(anchor.suffix)
    
    for _, match in ipairs(res) do
        -- Вычисляем страницу для этого совпадения
        local match_page
        if doc.configurable and doc.configurable.text_wrap == 1 then
            match_page = doc:getPageFromXPointer(match.start)
        else
            match_page = match.start
        end
        
        local score = 0
        
        -- Проверяем совпадение префиксов и суффиксов
        local actual_prefix_norm = Anchoring.normalizeText(match.prev_text)
        local actual_suffix_norm = Anchoring.normalizeText(match.next_text)
        
        -- Функция для безопасной проверки окончания строки
        local function endsWith(str, ending)
            return str:sub(-#ending) == ending
        end

        -- Функция для безопасной проверки начала строки
        local function startsWith(str, starting)
            return str:sub(1, #starting) == starting
        end

        if target_prefix_norm ~= "" and actual_prefix_norm ~= "" then
            if endsWith(actual_prefix_norm, target_prefix_norm) then
                score = score + 50
            end
        end
        
        if target_suffix_norm ~= "" and actual_suffix_norm ~= "" then
            if startsWith(actual_suffix_norm, target_suffix_norm) then
                score = score + 50
            end
        end
        
        -- Штраф за расстояние от примерной страницы (чтобы выбирать ближайшую к прогрессу)
        local page_diff = math.abs(match_page - estimated_page)
        score = score - (page_diff * 2)
        
        if score > best_score then
            best_score = score
            best_match = {
                match = match,
                page = match_page
            }
        end
    end
    
    if best_match then
        local match = best_match.match
        local page = best_match.page
        
        if doc.configurable and doc.configurable.text_wrap == 1 then
            -- Для EPUB: pos0 = start (xpointer), pos1 = end (xpointer)
            return match.start, match["end"], page
        else
            -- Для PDF: вычисляем pos0 и pos1 из boxes
            if match.boxes and #match.boxes > 0 then
                local first_box = match.boxes[1]
                local last_box = match.boxes[#match.boxes]
                
                local pos0 = { x = first_box.x, y = first_box.y, page = page }
                local pos1 = { x = last_box.x + last_box.w, y = last_box.y + last_box.h, page = page }
                
                return pos0, pos1, page
            end
        end
    end
    
    return nil
end

return Anchoring
