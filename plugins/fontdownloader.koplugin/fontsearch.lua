-- modification time in days
local mtime = {
    ["last_week"] = function(time) return time >= 0 and time <= 7 end,
    ["last_month"] = function(time) return time > 7 and time <= 31 end,
    ["last_year"] = function(time) return time > 31 and time <= 365 end,
    ["older"] = function(time) return time > 365 end,
}

-- elapsed days since a YYMMDD date
local function elapsedDays(date)
    local Y, M, D = date:match("(%d+)-(%d+)-(%d+)")
    local modified = os.time({year = Y, month = M, day = D})
    return math.floor(os.difftime(os.time(), modified) / (24 * 60 * 60))
end

-- elapsed days into categories
local function elapsedMatch(elapsed, cat)
    for category, match in pairs(mtime) do
        if category == cat and match(elapsed) then
            return true
        end
    end
    return false
end

-- get number of ocurrences of each lapse of time
local function dateFreq(t)
    local freq = {}
    for _, font in ipairs(t) do
        for category, match in pairs(mtime) do
            local ok = elapsedMatch(elapsedDays(font.lastModified), category)
            if ok then
                freq[category] = (freq[category] or 0) + 1
            end
        end
    end
    return freq
end

-- get fonts that match a lapse of time
local function dateMatch(t, query)
    local fonts = {}
    for _, font in ipairs(t) do
        if elapsedMatch(elapsedDays(font.lastModified), query) then
            table.insert(fonts, #fonts + 1, font)
        end
    end
    return fonts
end

-- get number of ocurrences of each category
local function categoryFreq(t)
    local freq = {}
    for _, font in ipairs(t) do
        local category = font.category
        freq[category] = (freq[category] or 0) + 1
    end
    return freq
end


-- get fonts that match a category
local function categoryMatch(t, query)
    local fonts = {}
    for _, font in ipairs(t) do
        if font.category == query then
            table.insert(fonts, #fonts + 1, font)
        end
    end
    return fonts
end

-- get number of ocurrences of each language
local function langFreq(t)
    local freq = {}
    for _, font in ipairs(t) do
        for __, lang in ipairs(font.subsets) do
            -- do not include extended variants
            if not lang:match("-ext$") then
                freq[lang] = (freq[lang] or 0) + 1
            end
        end
    end
    return freq
end

-- get fonts that match a language
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

-- get fonts that partially match a family
local function familyMatch(t, query)
    local fonts = {}
    for _, font in ipairs(t) do
        if not query or font.family:lower():match(query:lower()) then
            table.insert(fonts, #fonts + 1, font)
        end
    end
    return fonts
end

local M = {}

function M.timestampOk(date)
    return mtime.last_week(elapsedDays(date))
end

function M.frequenceOf(key, t)
    if key == "language" then
        return langFreq(t)
    elseif key == "category" then
        return categoryFreq(t)
    elseif key == "last" then
        return dateFreq(t)
    else
        return nil, "invalid key: " .. key
    end
end

function M.fontsByMatch(key, t, query)
    if key == "language" then
        return langMatch(t, query)
    elseif key == "category" then
        return categoryMatch(t, query)
    elseif key == "last" then
        return dateMatch(t, query)
    elseif key == "family" then
        return familyMatch(t, query)
    else
        return nil, "invalid key: " .. key
    end
end

return M
