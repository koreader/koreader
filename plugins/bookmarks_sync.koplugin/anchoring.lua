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
-- Новая реализация, использующая getTextFromPositions
function Anchoring.getAnchorContext(doc, item, context_char_len)
    context_char_len = context_char_len or 40 -- Длина контекста в символах
    local exact, prefix, suffix = "", "", ""

    if not item or not doc then return "", "", "" end

    exact = item.text or item.notes or ""

    -- Если это просто закладка на страницу без выделения, у нас нет координат.
    -- В этом случае, как и раньше, просто вернем текст самого item.
    if not item.drawer or not item.pos0 or not item.pos1 then
        logger.dbg("bookmarks_sync: getAnchorContext: no drawer or pos for item, returning exact text only.")
        return exact, "", ""
    end

    -- === Новая логика для получения префикса и суффикса ===
    local page = item.pos0.page
    local page_width = doc:getPageSize(page).w
    local line_height = 25 -- Приблизительная высота строки, нужна для смещения

    -- ПОЛУЧАЕМ ПРЕФИКС
    local prefix_start_pos = {
        x = item.pos0.x - context_char_len * 12, -- Смещаемся влево (12 - примерная ширина символа)
        y = item.pos0.y - line_height,
        page = page,
    }
    -- Корректируем, если ушли за пределы страницы
    if prefix_start_pos.x < 0 then prefix_start_pos.x = 0 end
    if prefix_start_pos.y < 0 then prefix_start_pos.y = 0 end

    local ok_prefix, res_prefix = pcall(doc.getTextFromPositions, doc, prefix_start_pos, item.pos0)
    if ok_prefix and res_prefix and res_prefix.text then
        prefix = res_prefix.text:gsub("%s+$", "") -- Убираем пробелы в конце
    else
        logger.warn("bookmarks_sync: getAnchorContext: failed to get prefix text.", res_prefix)
    end

    -- ПОЛУЧАЕМ СУФФИКС
    local suffix_end_pos = {
        x = item.pos1.x + context_char_len * 12, -- Смещаемся вправо
        y = item.pos1.y + line_height,
        page = page,
    }
    -- Корректируем, если ушли за пределы страницы
    if suffix_end_pos.x > page_width then suffix_end_pos.x = page_width end

    local ok_suffix, res_suffix = pcall(doc.getTextFromPositions, doc, item.pos1, suffix_end_pos)
    if ok_suffix and res_suffix and res_suffix.text then
        suffix = res_suffix.text:gsub("^%s+", "") -- Убираем пробелы в начале
    else
        logger.warn("bookmarks_sync: getAnchorContext: failed to get suffix text.", res_suffix)
    end

    logger.info("bookmarks_sync: getAnchorContext result:", {exact=exact, prefix=prefix, suffix=suffix})
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

        if target_prefix_norm ~= "" and actual_prefix_norm ~= "" then
            if actual_prefix_norm:sub(-#target_prefix_norm) == target_prefix_norm or
               target_prefix_norm:sub(-#actual_prefix_norm) == actual_prefix_norm then
                score = score + 50
            end
        end

        if target_suffix_norm ~= "" and actual_suffix_norm ~= "" then
            if actual_suffix_norm:sub(1, #target_suffix_norm) == target_suffix_norm or
               target_suffix_norm:sub(1, #actual_suffix_norm) == actual_suffix_norm then
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
