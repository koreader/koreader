local function categoryFreq(t)
    local freq = {}
    for _, font in ipairs(t) do
        local category = font.category
        freq[category] = (freq[category] or 0) + 1
    end
    return freq
end

local function categoryMatch(t, query)
    local fonts = {}
    for _, font in ipairs(t) do
        if font.category == query then
            table.insert(fonts, #fonts + 1, font)
        end
    end
    return fonts
end

local function elapsedDays(date)
    local Y, M, D = date:match("(%d+)-(%d+)-(%d+)")
    local modified = os.time({year = Y, month = M, day = D})
    return math.floor(os.difftime(os.time(), modified) / (24 * 60 * 60))
end

local function elapsedMatch(elapsed, cat)
    if cat == "last_week" and elapsed >= 0 and elapsed <= 7 then
        return true
    elseif cat == "last_month" and elapsed > 7 and elapsed <= 31 then
        return true
    elseif cat == "last_year" and elapsed > 31 and elapsed <= 365 then
        return true
    elseif cat == "older" and elapsed > 365 then
        return true
    else
        return false
    end
end

local function dateFreq(t)
    local freq = {}
    for _, font in ipairs(t) do
        local days = elapsedDays(font.lastModified)
        if elapsedMatch(days, "last_year") then
            freq["last_year"] = (freq["last_year"] or 0) + 1
        elseif elapsedMatch(days, "last_month") then
            freq["last_month"] = (freq["last_month"] or 0) + 1
        elseif elapsedMatch(days, "last_week") then
            freq["last_week"] = (freq["last_week"] or 0) + 1
        elseif elapsedMatch(days, "older") then
            freq["older"] = (freq["older"] or 0) + 1
        end
    end
    return freq
end

local function dateMatch(t, query)
    local fonts = {}
    for _, font in ipairs(t) do
        if elapsedMatch(elapsedDays(font.lastModified), query) then
            table.insert(fonts, #fonts + 1, font)
        end
    end
    return fonts
end

local function langFreq(t)
    local freq = {}
    for _, font in ipairs(t) do
        for __, lang in ipairs(font.subsets) do
            freq[lang] = (freq[lang] or 0) + 1
        end
    end
    return freq
end

local function langMatch(t, query)
    local fonts = {}
    for _, font in ipairs(t) do
        for __, lang in ipairs(font.subsets) do
            if lang == query then
                table.insert(fonts, #fonts + 1, font)
            end
        end
    end
    return fonts
end

local FontSearch = {}

function FontSearch:sortBy(key, t)
    local result = {}
    if key == "category" then
        result = categoryFreq(t)
    elseif key == "last" then
        result = dateFreq(t)
    elseif key == "language" then
        result = langFreq(t)
    end
    return result
end

function FontSearch:fontsBy(key, query, t)
    local result = {}
    if key == "category" then
        result = categoryMatch(t, query)
    elseif key == "last" then
        result = dateMatch(t, query)
    elseif key == "language" then
        result = langMatch(t, query)
    end
    return result
end

function FontSearch:category(t)
    local freq = {}
    for _, font in ipairs(t) do
        local category = font.category
        freq[category] = (freq[category] or 0) + 1
    end
    return freq
end

function FontSearch:language(t)
    local freq = {}
    for _, font in ipairs(t) do
        for __, lang in ipairs(font.subsets) do
            freq[lang] = (freq[lang] or 0) + 1
        end
    end
    return freq
end

function FontSearch:date(t)
    local freq = {}
    for _, font in ipairs(t) do
        local Y, M, D = font.lastModified:match("(%d+)-(%d+)-(%d+)")
        local modified = os.time({year = Y, month = M, day = D})
        local elapsed_days = math.floor(os.difftime(os.time(), modified / (24 * 60 * 60)))
        if elapsed_days <= 365 and elapsed_days > 30 then
            freq["last_year"] = (freq["last_year"] or 0) + 1
        elseif elapsed_days <= 30 and elapsed_days > 7 then
            freq["last_month"] = (freq["last_month"] or 0) + 1
        elseif elapsed_days <= 7 and elapsed_days >= 0 then
            freq["last_week"] = (freq["last_week"] or 0) + 1
        end
    end
    return freq
end

return FontSearch
