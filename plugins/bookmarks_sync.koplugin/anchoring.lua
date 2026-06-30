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

-- Иногда findText в бэкенде может быть слишком "жадным" и возвращать боксы
-- для нескольких отдельных совпадений на странице как один результат.
-- Это приводит к выделению больших кусков текста.
-- Мы можем попытаться "подрезать" результат, ища большие разрывы между боксами.
local function pruneGreedySearchResult(res, doc)
    -- Эта эвристика применяется только для PDF/DjVu (fixed layout)
    if not res or not res[1] or #res <= 1 or not (doc.is_pdf or doc.is_djvu) then
        return res
    end

    local last_box_idx = 1
    for i = 1, #res - 1 do
        local box1 = res[i]
        local box2 = res[i + 1]
        -- Эвристика для обнаружения больших разрывов между боксами
        local vertical_gap = box2.y - (box1.y + box1.h)
        local horizontal_gap = box2.x - (box1.x + box1.w)

        if box2.y > box1.y + box1.h * 0.5 then -- На новой строке
            -- Большой вертикальный разрыв (более чем в 2 раза больше высоты строки) скорее всего указывает на новый абзац
            if box1.h > 0 and vertical_gap > box1.h * 2 then
                break
            end
        else -- На той же строке
            -- Большой горизонтальный разрыв (более 3 ширин пробела) также может указывать на разрыв
            if box1.h > 0 and horizontal_gap > box1.h * 3 then
                break
            end
        end
        last_box_idx = i + 1
    end

    if last_box_idx < #res then
        logger.info(string.format("bookmarks_sync: Pruning greedy search result from %d to %d boxes", #res, last_box_idx))
        for i = #res, last_box_idx + 1, -1 do table.remove(res, i) end
    end
    return res
end

-- Безопасное получение контекста для выделения или закладки
-- @param doc - экземпляр документа (self.ui.document)
-- @param item - элемент аннотации (bookmark/highlight)
-- @param nb_words - количество слов контекста (по умолчанию 5)
-- @return exact, prefix, suffix
function Anchoring.getAnchorContext(doc, item, nb_words)
    nb_words = nb_words or 10
    local exact, prefix, suffix = "", "", ""

    -- Эвристика для очистки контекста от "мусора" (например, номеров страниц).
    -- Иногда getSelectedWordContext захватывает текст из колонтитулов.
    local function cleanupContext(context_str)
        if not context_str or context_str == "" then return "" end
        local words = {}
        for word in context_str:gmatch("%S+") do
            table.insert(words, word)
        end

        if #words == 0 then return "" end

        -- Убираем числовые "слова" только с начала строки
        while #words > 0 and words[1]:match("^%d+$") do
            logger.dbg("bookmarks_sync: Stripping leading numeric-only word from context:", words[1])
            table.remove(words, 1)
        end

        -- Убираем числовые "слова" только с конца строки
        while #words > 0 and words[#words]:match("^%d+$") do
            logger.dbg("bookmarks_sync: Stripping trailing numeric-only word from context:", words[#words])
            table.remove(words)
        end

        return table.concat(words, " ")
    end

    logger.dbg("bookmarks_sync: getAnchorContext: Starting for item.text:", item.text)

    if item.drawer then
        -- Это выделение (highlight) или заметка (note)
        exact = item.text or item.notes or ""

        -- Пытаемся извлечь контекст средствами KOReader
        if doc.getSelectedWordContext and item.pos0 and item.pos1 then
            -- HACK: Для PDF/DjVu getSelectedWordContext зависит от глобального состояния

            local text_for_context = exact
            if doc.is_pdf or doc.is_djvu then
                logger.dbg("bookmarks_sync: getAnchorContext: PDF/DjVu document, preparing text_for_context.")
                -- Для PDF/DjVu, функция getSelectedWordContext является хрупкой при работе с длинным текстом.
                -- Она пытается сопоставить полный текст пословно, чтобы найти конец выделения.
                -- Одно несоответствие (например, лишний пробел, дефис) приводит к сбою.
                -- Мы будем использовать укороченную и очищенную версию текста (первые 5 слов),
                -- чтобы повысить вероятность успешного совпадения.
                -- Для PDF/DjVu, функция getSelectedWordContext очень чувствительна к тексту.
                -- Текст, сохраненный в закладке (item.text), может немного отличаться от того,
                -- как движок извлекает его из документа в данный момент (из-за нормализации и т.д.).
                -- Это приводит к сбою при поиске контекста.
                --
                -- РЕШЕНИЕ: Вместо того, чтобы использовать item.text, мы заново извлекаем
                -- "сырой" текст из документа, используя те же координаты закладки (item.pos0, item.pos1).
                -- Этот "сырой" текст гарантированно будет соответствовать тому, что ожидает
                -- getSelectedWordContext, так как обе функции работают с одним и тем же представлением документа.
                local ok, res = pcall(doc.getTextFromPositions, doc, item.pos0, item.pos1, true) -- true = не рисовать выделение
                if ok and res and res.text and res.text ~= "" then
                    text_for_context = res.text
                    logger.dbg("bookmarks_sync: getAnchorContext: Re-extracted raw text from position:", text_for_context)
                else
                    -- Если не удалось извлечь текст, используем исходный.
                    -- Контекст, скорее всего, не найдется, но это лучше, чем ничего.
                    logger.warn("bookmarks_sync: getAnchorContext: Failed to re-extract text, falling back to original.")
                end

                -- Теперь, когда у нас есть "правильный" текст, берем из него первые 5 слов
                -- для передачи в getSelectedWordContext.
                local words = {}
                for w in text_for_context:gmatch("%S+") do
                    table.insert(words, w)
                    if #words >= 5 then break end -- Используем первые 5 слов, этого достаточно
                end
                if #words > 0 then
                    text_for_context = table.concat(words, " ")
                end
                logger.dbg("bookmarks_sync: getAnchorContext: text_for_context for getSelectedWordContext is now:",
                    text_for_context)
            end

            local koptinterface
            local corrected_pos0 = item.pos0 -- Начинаем с исходной позиции

            if doc.is_pdf or doc.is_djvu then
                koptinterface = require("document/koptinterface")
                logger.dbg("bookmarks_sync: getAnchorContext: Preparing koptinterface for context extraction.")
                -- koptinterface.last_text_boxes. Мы должны принудительно заполнить его
                -- перед вызовом, чтобы получить контекст для уже существующих закладок.
                koptinterface.last_text_boxes = doc:getTextBoxes(item.page)
                -- Хак для коррекции позиции был удален. Другие улучшения (pruneGreedySearchResult)
                -- должны делать начальную позицию более надежной, а сам хак вызывал
                -- несовместимость с getSelectedWordContext. Теперь мы доверяем item.pos0.
                logger.dbg("bookmarks_sync: getAnchorContext: Using original item.pos0 for context extraction:",
                    corrected_pos0)
            end

            -- Вызываем getSelectedWordContext с (потенциально исправленной) стартовой позицией.
            -- Вторая позиция (item.pos1) не используется в реализации для koptinterface.
            local ok, p, s = pcall(doc.getSelectedWordContext, doc, text_for_context, nb_words, corrected_pos0, item
                .pos1)
            logger.dbg("bookmarks_sync: getAnchorContext: getSelectedWordContext call result: ok=", ok, "prefix=", p,
                "suffix=", s)
            if ok and p and s then
                prefix = p
                suffix = s
            else
                logger.warn(
                    "bookmarks_sync: Failed to extract context via getSelectedWordContext. Text might be too long or have inaccuracies. Error:",
                    p)
            end
            if koptinterface then
                koptinterface.last_text_boxes = nil -- Очищаем состояние после себя
            end
        else
            logger.warn("bookmarks_sync: Не выполнены условия для getSelectedWordContext")
        end
    else
        logger.dbg("bookmarks_sync: getAnchorContext: Processing a simple page bookmark (dogear).")

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

            prefix = cleanupContext(prefix)
            suffix = cleanupContext(suffix)
        end
    end

    logger.dbg("bookmarks_sync: getAnchorContext: Final result -> exact:", exact, "prefix:", prefix, "suffix:", suffix)

    return exact, prefix, suffix
end

-- Локальный поиск текста якоря в окрестности сохраненного прогресса
-- @param doc - экземпляр документа
-- @param anchor - объект якоря { exact, prefix, suffix, progress }
-- @param view_state - текущее состояние вида (для zoom, rotation)
function Anchoring.findAnchor(doc, anchor, view_state)
    if not anchor.exact or anchor.exact == "" then return nil end

    -- The original_search_text is the cleaned full text we want to find.
    local original_search_text = anchor.exact

    local total_pages = doc:getPageCount()
    if not total_pages or total_pages <= 0 then return nil end

    -- Вычисляем примерную страницу в текущем документе
    local estimated_page = math.floor(anchor.progress * total_pages)
    if estimated_page < 1 then estimated_page = 1 end
    if estimated_page > total_pages then estimated_page = total_pages end

    local is_reflowable = not (doc.is_pdf or doc.is_djvu)
    local is_fixed_layout = not is_reflowable

    -- =================================================================
    -- СТРАТЕГИЯ 1: "Быстрый путь" - поиск полного контекста, затем уточнение.
    -- Сначала ищем полный контекст (prefix + exact + suffix). Это очень быстро и точно находит место.
    -- Затем, на найденной странице, ищем только 'exact', чтобы получить точные координаты для выделения.
    -- Эта стратегия особенно эффективна для PDF/DjVu.
    -- =================================================================
    if is_fixed_layout and anchor.prefix and anchor.prefix ~= "" and anchor.suffix and anchor.suffix ~= "" then
        local full_context_text = table.concat({ anchor.prefix, anchor.exact, anchor.suffix }, " ")
        logger.dbg("bookmarks_sync: findAnchor: Strategy 1 (Fast Path): Attempting full context search for:",
            full_context_text)

        local case_insensitive = true
        -- Для PDF/DjVu ограничиваем поиск небольшим окном вокруг предполагаемой страницы для скорости.
        local search_radius_pages = math.max(10, math.floor(total_pages * 0.05)) -- +/- 5% или 10 страниц
        local start_page = math.max(1, estimated_page - search_radius_pages)
        local end_page = math.min(total_pages, estimated_page + search_radius_pages)
        logger.dbg("bookmarks_sync: findAnchor: Fast Path search range: pages", start_page, "to", end_page)

        -- Ищем полный контекст, начиная со start_page.
        -- findText сам продолжит поиск по последующим страницам, поэтому цикл не нужен.
        local full_context_ok, full_context_res = pcall(doc.findText, doc, full_context_text, 0, 0, case_insensitive,
            start_page)
        logger.dbg("bookmarks_sync: findAnchor: Fast Path: Full context search from page", start_page, "result:",
            full_context_res)

        if full_context_ok and full_context_res and #full_context_res > 0 then
            -- Поиск мог вернуть результат на другой странице.
            local match_page = full_context_res.page or (full_context_res[1] and full_context_res[1].page) or start_page

            -- Проверяем, что найденная страница находится в пределах нашего окна поиска.
            if match_page <= end_page then
                logger.dbg("bookmarks_sync: findAnchor: Fast Path: Full context found on page", match_page,
                    "(searched from page", start_page, ")")

                -- Контекст найден. Теперь ищем 'exact' на этой же странице для точного выделения.
                local exact_ok, exact_res = pcall(doc.findText, doc, anchor.exact, 0, 0, case_insensitive, match_page)
                if exact_ok then exact_res = pruneGreedySearchResult(exact_res, doc) end
                if exact_ok and exact_res and #exact_res > 0 then
                    -- Отлично, нашли точное совпадение. Используем его координаты.
                    local first_box = exact_res[1]
                    local last_box = exact_res[#exact_res]
                    local refined_page = exact_res.page or first_box.page or match_page
                    local pos0 = { -- Используем центр первого слова
                        x = first_box.x + first_box.w / 2,
                        y = first_box.y + first_box.h / 2,
                        page = refined_page,
                        zoom = view_state and view_state.zoom,
                        rotation = view_state and view_state.rotation
                    }
                    local pos1 = { -- Используем центр последнего слова
                        x = last_box.x + last_box.w / 2,
                        y = last_box.y + last_box.h / 2,
                        page = refined_page,
                        zoom = view_state and view_state.zoom,
                        rotation = view_state and view_state.rotation
                    }
                    logger.info("bookmarks_sync: findAnchor: Found and refined anchor using Fast Path on page",
                        refined_page)
                    return pos0, pos1, refined_page
                else
                    logger.warn("bookmarks_sync: findAnchor: Fast Path: Full context found on page", match_page,
                        ", but failed to refine to 'exact'. Falling back.")
                    -- Не удалось уточнить. "Быстрый путь" не сработал, переходим к основной, более медленной стратегии.
                end
            else
                logger.dbg("bookmarks_sync: findAnchor: Fast Path: Found a match on page", match_page,
                    "but it is outside the search radius (", start_page, "-", end_page, "). Falling back.")
            end
        end
    end

    local nb_context_words = 5
    local max_hits = 200
    local case_insensitive = true
    local search_flags = 0x01FF -- IGNORE_DIACRITICS + NORMALIZE_COMPATIBILITY

    local ok, res
    local is_fuzzy_search = false

    logger.dbg("bookmarks_sync: Checking document type. Is reflowable? ->", is_reflowable)

    -- =================================================================
    -- СТРАТЕГИЯ 2: Поиск по 'exact' (основной текст закладки)
    -- =================================================================
    if is_reflowable then
        logger.dbg("bookmarks_sync: Using EPUB search for text:", original_search_text)
        logger.dbg("bookmarks_sync: findAllText params (exact):", original_search_text, case_insensitive,
            nb_context_words, max_hits, false)
        ok, res = pcall(doc.findAllText, doc, original_search_text, case_insensitive, nb_context_words, max_hits, false)
        logger.dbg("bookmarks_sync: findAllText result (exact): ok=", ok, "res=", res)
    else
        logger.dbg("bookmarks_sync: Using PDF search for text:", original_search_text)
        logger.dbg("bookmarks_sync: findAllText params (exact):", original_search_text, case_insensitive,
            nb_context_words, max_hits)
        ok, res = pcall(doc.findAllText, doc, original_search_text, case_insensitive, nb_context_words, max_hits)
    end

    -- =================================================================
    -- СТРАТЕГИЯ 2.1: Поиск по первому предложению для длинных выделений
    -- =================================================================
    if (not ok or not res or #res == 0) and #original_search_text > 100 then -- Эвристика для "длинного" текста
        logger.dbg("bookmarks_sync: Primary search failed for long text. Attempting search by first sentence.")

        -- Пытаемся найти первое предложение. Простое разделение по знакам препинания.
        local first_sentence = original_search_text:match("([^.!?]+[.!?])")
        if first_sentence then
            first_sentence = first_sentence:gsub("^%s+", ""):gsub("%s+$", "") -- Убираем пробелы по краям
            -- Ищем, только если предложение достаточно длинное, чтобы быть уникальным
            if #first_sentence > 20 then
                is_fuzzy_search = true -- Мы должны будем проверить полный контекст
                local search_text = first_sentence
                logger.dbg("bookmarks_sync: Sentence search: using first sentence:", search_text)

                -- Запрашиваем гораздо больший контекст, чтобы вместить все длинное выделение
                local large_context_words = math.floor(#original_search_text / 4) +
                    10 -- Эвристика: 1 слово ~ 4 символа + запас
                if is_reflowable then
                    logger.dbg("bookmarks_sync: findAllText params (sentence):", search_text, case_insensitive,
                        large_context_words, max_hits, false)
                    ok, res = pcall(doc.findAllText, doc, search_text, case_insensitive, large_context_words, max_hits,
                        false)
                    logger.dbg("bookmarks_sync: findAllText result (sentence): ok=", ok, "res=", res)
                else
                    ok, res = pcall(doc.findAllText, doc, search_text, case_insensitive, large_context_words, max_hits)
                end
            end
        end
    end

    -- =================================================================
    -- СТРАТЕГИЯ 3: "Нечеткий" поиск по самому длинному слову
    -- =================================================================
    if not ok or not res or #res == 0 then
        logger.dbg("bookmarks_sync: Primary search failed for '" .. original_search_text .. "'. Attempting fuzzy search.")

        -- Применяем нормализацию только для нечеткого поиска
        local normalized_text = original_search_text
        -- Заменяем мягкие переносы (U+00AD) на пустую строку
        normalized_text = normalized_text:gsub("[\194\173]", "")
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
                logger.dbg("bookmarks_sync: findAllText params (fuzzy):", search_text, case_insensitive, nb_context_words,
                    max_hits, false)
                ok, res = pcall(doc.findAllText, doc, search_text, case_insensitive, nb_context_words, max_hits, false,
                    true)
                logger.dbg("bookmarks_sync: findAllText result (fuzzy): ok=", ok, "res=", res)
            else
                ok, res = pcall(doc.findAllText, doc, search_text, case_insensitive, nb_context_words, max_hits)
            end
        end
    end

    if not ok or not res or #res == 0 then
        logger.dbg("bookmarks_sync: findAnchor: No matches found for search text: " .. original_search_text,
            "Error (if any):", tostring(res))
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
            local full_context = table.concat({ match.prev_text or "", match.matched_text or "", match.next_text or "" },
                " ")
            local normalized_full_context = Anchoring.normalizeText(full_context)

            if normalized_full_context:find(normalized_original_search, 1, true) then -- literal search
                score = score +
                    100                                                               -- Это реальное совпадение, даем большой бонус
                logger.dbg("bookmarks_sync: Fuzzy search: context verified.")
            else
                -- Это ложное срабатывание. Сильно штрафуем и пропускаем.
                score = -2000
            end
        end

        -- Проверяем совпадение префиксов и суффиксов
        -- Контекст префикса - это комбинация текста до и начала найденного слова.
        local full_prev_text = (match.prev_text or "") .. (match.matched_word_prefix or "")
        local actual_prefix_norm = Anchoring.normalizeText(full_prev_text)
        -- Контекст суффикса — это комбинация конца найденного слова и текста после него.
        local full_next_text = (match.matched_word_suffix or "") .. (match.next_text or "")
        local actual_suffix_norm = Anchoring.normalizeText(full_next_text)
        logger.dbg("bookmarks_sync: actual_prefix_norm = ", actual_prefix_norm)
        logger.dbg("bookmarks_sync: actual_suffix_norm = ", actual_suffix_norm)

        if score > -1000 then -- Продолжаем, только если это не явное ложное срабатывание от нечеткого поиска
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
            -- For PDF: We need to ensure pos0 and pos1 correspond ONLY to anchor.exact.
            -- The match.boxes from findAllText might be wider than anchor.exact if findAllText returned context.
            -- We perform a new, precise search for anchor.exact on the identified page.
            local exact_search_res_ok, exact_search_res = pcall(doc.findText, doc, anchor.exact, 0, 0, case_insensitive,
                page)
            if exact_search_res_ok then exact_search_res = pruneGreedySearchResult(exact_search_res, doc) end
            if exact_search_res_ok and exact_search_res and #exact_search_res > 0 then
                -- Found exact match on the page. Use its boxes.
                local first_box = exact_search_res[1]
                local last_box = exact_search_res[#exact_search_res]
                local pos0 = { -- Используем центр первого слова
                    x = first_box.x + first_box.w / 2,
                    y = first_box.y + first_box.h / 2,
                    page = page,
                    zoom = view_state and view_state.zoom,
                    rotation = view_state and view_state.rotation
                }
                local pos1 = { -- Используем центр последнего слова
                    x = last_box.x + last_box.w / 2,
                    y = last_box.y + last_box.h / 2,
                    page = page,
                    zoom = view_state and view_state.zoom,
                    rotation = view_state and view_state.rotation
                }
                logger.dbg("bookmarks_sync: findAnchor: Refined PDF highlight to exact text on page", page)
                return pos0, pos1, page
            else
                -- Fallback: If exact re-search fails (e.g., due to text extraction differences),
                -- use the original (potentially wider) match.boxes from findAllText.
                -- This is less ideal but prevents losing the bookmark entirely.
                logger.warn(
                    "bookmarks_sync: findAnchor: Could not refine PDF highlight to exact text. Using wider match from findAllText.")
                if match.boxes and #match.boxes > 0 then
                    local first_box = match.boxes[1]
                    local last_box = match.boxes[#match.boxes]
                    -- Ensure the page is correct, as match.boxes might not always have it.
                    first_box.page = page
                    last_box.page = page

                    local pos0 = { -- Используем центр первого слова
                        x = first_box.x + first_box.w / 2,
                        y = first_box.y + first_box.h / 2,
                        page = page,
                        zoom = view_state and view_state.zoom,
                        rotation = view_state and view_state.rotation
                    }
                    local pos1 = { -- Используем центр последнего слова
                        x = last_box.x + last_box.w / 2,
                        y = last_box.y + last_box.h / 2,
                        page = page,
                        zoom = view_state and view_state.zoom,
                        rotation = view_state and view_state.rotation
                    }
                    return pos0, pos1, page
                end
            end
        end
    end

    logger.dbg("bookmarks_sync: findAnchor: no suitable match found.")
    return nil
end

return Anchoring
