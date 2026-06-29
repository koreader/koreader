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

            -- Для PDF/DjVu, основная функция getSelectedWordContext является хрупкой при работе с длинным текстом.
            -- Она пытается сопоставить полный текст пословно, чтобы найти конец выделения.
            -- Одно несоответствие (например, лишний пробел, дефис) приводит к сбою.
            -- Мы будем использовать укороченную версию текста, чтобы повысить вероятность успешного совпадения.
            local text_for_context = exact
            if (doc.is_pdf or doc.is_djvu) and #exact > 250 then -- Эвристическая длина, после которой текст считается "длинным"
                local words = {}
                for w in exact:gmatch("%S+") do
                    table.insert(words, w)
                    if #words >= 30 then break end -- Используем первые 30 слов, этого достаточно
                end
                text_for_context = table.concat(words, " ")
            end

            -- koptinterface.last_text_boxes. Мы должны принудительно заполнить его
            -- перед вызовом, чтобы получить контекст для уже существующих закладок.
            -- Для CreDocument (EPUB) это не требуется, т.к. у него своя реализация.
            local koptinterface
            if doc.is_pdf or doc.is_djvu then
                koptinterface = require("document/koptinterface")
                koptinterface.last_text_boxes = doc:getTextBoxes(item.page)
            end

            local ok, p, s = pcall(doc.getSelectedWordContext, doc, text_for_context, nb_words, item.pos0, item.pos1)
            if ok and p and s then
                prefix = p
                suffix = s
            else
                logger.warn("bookmarks_sync: Не удалось извлечь контекст для выделения через getSelectedWordContext. Возможно, текст слишком длинный или содержит неточности.")
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
        -- текст с начала страницы/экрана.
        local is_reflowable = not (doc.is_pdf or doc.is_djvu)
        if is_reflowable then
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
                -- Смещаем начальную точку Y примерно на 10%, чтобы пропустить возможные колонтитулы (номера страниц).
                local y_offset = math.floor(screen_h * 0.1)
                local ok, res = pcall(doc.getTextFromPositions, doc, 
                    -- Запрашиваем текст из небольшой горизонтальной полосы вверху страницы,
                    -- чтобы избежать потенциальных ошибок при обработке большого прямоугольника.
                    { x = 0, y = y_offset, page = item.page },
                    -- Высоты в 150 пикселей должно быть достаточно, чтобы захватить несколько строк текста.
                    { x = screen_w, y = y_offset + 150, page = item.page },
                    true
                )
                if ok and res and res.text and res.text ~= "" then
                    exact = res.text:sub(1, 100)
                end
            end
        end
        
        -- Если удалось извлечь начало страницы, формируем якорь
        if exact ~= "" then
            exact = exact:gsub("^%s+", "") -- убираем ведущие пробелы
            
            -- Для простых закладок, используем первые несколько слов как якорь.
            -- Чтобы сделать якорь надежнее, разделим его на 'exact' (первое слово)
            -- и 'suffix' (следующие несколько слов).
            local words = {}
            -- Заменяем всю пунктуацию на пробелы, чтобы правильно разделить слова
            local text_for_word_split = exact:gsub("[%p%c%z]", " ")
            for word in text_for_word_split:gmatch("%S+") do
                table.insert(words, word)
                if #words >= 5 then break end -- Берем до 5 слов для якоря
            end
            
            if #words >= 3 then
                -- Best case: we have prefix, exact, and suffix
                prefix = words[1]
                exact = words[2]
                suffix = table.concat(words, " ", 3)
            elseif #words == 2 then
                -- No prefix, but we have exact and suffix
                exact = words[1]
                suffix = words[2]
            elseif #words == 1 then
                exact = words[1]
            else
                exact = "" -- No words found
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

    -- The original_search_text is the cleaned full text we want to find.
    local original_search_text = anchor.exact

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
    local is_fuzzy_search = false

    -- Let's add detailed logging to understand why the wrong branch is being taken.
    -- The check `doc.configurable.text_wrap == 1` can be unreliable depending on when it's called.
    -- A more direct check is to see if the document is an EPUB or other reflowable format.
    -- CreDocument handles EPUB, FB2, etc. and is always reflowable.
    local is_reflowable = not (doc.is_pdf or doc.is_djvu)
    logger.dbg("bookmarks_sync: Checking document type. Is reflowable? ->", is_reflowable)

    -- Этап 1: Поиск точного совпадения
    if is_reflowable then
        -- EPUB / FB2 (CreDocument)
        logger.dbg("bookmarks_sync: Using EPUB search for text:", original_search_text)
        ok, res = pcall(doc.findAllText, doc, original_search_text, case_insensitive, nb_context_words, max_hits, false)
    else
        -- PDF / DjVu (Fixed-layout)
        logger.dbg("bookmarks_sync: Using PDF search for text:", original_search_text)
        ok, res = pcall(doc.findAllText, doc, original_search_text, case_insensitive, nb_context_words, max_hits)
    end

    -- Этап 2: Если точный поиск не дал результатов, пробуем нечеткий поиск
    if not ok or not res or #res == 0 then
        logger.dbg("bookmarks_sync: Primary search failed for '"..original_search_text.."'. Attempting fuzzy search.")

        -- Применяем нормализацию только для нечеткого поиска
        local normalized_text = original_search_text
        -- Заменяем мягкие переносы (U+00AD) на пустую строку
        normalized_text = normalized_text:gsub("\194\173", "")
        -- Нормализуем пробельные символы (несколько пробелов/переносов -> один пробел)
        normalized_text = normalized_text:gsub("%s+", " ")
        -- Убираем пробелы в начале и конце строки
        normalized_text = normalized_text:gsub("^%s*(.-)%s*$", "%1")
        -- Дополнительная нормализация для повышения шансов на совпадение
        -- Заменяем "умные" кавычки и апострофы на простые
        normalized_text = normalized_text:gsub("[“”]", '"')
        normalized_text = normalized_text:gsub("[‘’]", "'")

        local longest_word = ""
        -- Заменяем всю пунктуацию на пробелы, чтобы правильно разделить слова
        local text_for_word_split = normalized_text:gsub("[%p%c%z]", " ")
        for word in text_for_word_split:gmatch("%S+") do
            if #word > #longest_word then longest_word = word end
        end

        -- Эвристика: используем нечеткий поиск, только если есть достаточно длинное слово
        -- и исходный текст состоит не из одного этого слова.
        if #longest_word > 4 and #longest_word < #original_search_text then
            is_fuzzy_search = true
            local search_text = longest_word
            logger.dbg("bookmarks_sync: Fuzzy search: using longest word:", search_text)

            if is_reflowable then
                ok, res = pcall(doc.findAllText, doc, search_text, case_insensitive, nb_context_words, max_hits, false)
            else
                ok, res = pcall(doc.findAllText, doc, search_text, case_insensitive, nb_context_words, max_hits)
            end
        end
    end

    if not ok or not res or #res == 0 then
        logger.dbg("bookmarks_sync: No matches found for search text: " .. original_search_text, "Error (if any):", tostring(res))
        return nil -- Совпадений не найдено
    end
    logger.dbg("bookmarks_sync: Found", #res, "potential matches.")
    
    local best_match = nil
    local best_score = -1000
    
    local target_prefix_norm = Anchoring.normalizeText(anchor.prefix)
    logger.dbg("bookmarks_sync: target_prefix_norm = ", target_prefix_norm)
    local target_suffix_norm = Anchoring.normalizeText(anchor.suffix)
    logger.dbg("bookmarks_sync: target_suffix_norm = ", target_suffix_norm)
    
    local normalized_original_search = nil
    if is_fuzzy_search then
        -- Для нечеткого поиска нам нужен нормализованный полный текст для проверки контекста
        normalized_original_search = Anchoring.normalizeText(original_search_text)
    end
    
    for _, match in ipairs(res) do
        -- Вычисляем страницу для этого совпадения
        local match_page
        if is_reflowable then
            match_page = doc:getPageFromXPointer(match.start)
        else
            match_page = match.start
        end
        logger.dbg("bookmarks_sync: match_page = ", match_page)
        
        local score = 0
        
        -- Если использовался нечеткий поиск, сначала проверяем полный контекст
        if is_fuzzy_search then
            local full_context = table.concat({match.prev_text or "", match.matched_text or "", match.next_text or ""}, " ")
            local normalized_full_context = Anchoring.normalizeText(full_context)

            if normalized_full_context:find(normalized_original_search, 1, true) then
                score = score + 100 -- Это реальное совпадение, даем большой бонус
                logger.dbg("bookmarks_sync: Fuzzy search: context verified.")
            else
                -- Это ложное срабатывание. Сильно штрафуем и пропускаем.
                score = -2000
            end
        end
        
        -- Проверяем совпадение префиксов и суффиксов
        -- Контекст префикса — это комбинация текста до и начала найденного слова.
        local full_prev_text = (match.prev_text or "") .. (match.matched_word_prefix or "")
        local actual_prefix_norm = Anchoring.normalizeText(full_prev_text)
        -- Контекст суффикса — это комбинация конца найденного слова и текста после него.
        local full_next_text = (match.matched_word_suffix or "") .. (match.next_text or "")
        local actual_suffix_norm = Anchoring.normalizeText(full_next_text)
        logger.dbg("bookmarks_sync: actual_prefix_norm = ", actual_prefix_norm)
        logger.dbg("bookmarks_sync: actual_suffix_norm = ", actual_suffix_norm)
        
        if score > -1000 then -- Продолжаем, только если это не явное ложное срабатывание
            if target_prefix_norm ~= "" and actual_prefix_norm ~= "" then
                -- Приводим строки к одной (минимальной) длине для сравнения конца строки
                local len = math.min(#actual_prefix_norm, #target_prefix_norm)
                if actual_prefix_norm:sub(-len) == target_prefix_norm:sub(-len) then
                    score = score + 50
                    logger.dbg("bookmarks_sync: Prefix match, score +50")
                end
            end
            
            if target_suffix_norm ~= "" and actual_suffix_norm ~= "" then
                -- Приводим строки к одной (минимальной) длине для сравнения начала строки
                local len = math.min(#actual_suffix_norm, #target_suffix_norm)
                if actual_suffix_norm:sub(1, len) == target_suffix_norm:sub(1, len) then
                    score = score + 50
                    logger.dbg("bookmarks_sync: Suffix match, score +50")
                end
            end
        end
        
        -- Штраф за расстояние от примерной страницы (чтобы выбирать ближайшую к прогрессу)
        local page_diff = math.abs(match_page - estimated_page)
        score = score - (page_diff * 2)
        
        if score > best_score then
            logger.dbg("bookmarks_sync: New best match found with score", score)
            best_score = score
            best_match = {
                match = match,
                page = match_page
            }
        end
    end
    
    if best_match then
        logger.dbg("bookmarks_sync: Final best match:", best_match)
        local match = best_match.match
        local page = best_match.page
        
        if is_reflowable then
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
    
    logger.dbg("bookmarks_sync: findAnchor: no suitable match found.")
    return nil
end

return Anchoring
