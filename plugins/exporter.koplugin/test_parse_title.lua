local extensions = {
    [".pdf"] = true,
    [".djvu"] = true,
    [".epub"] = true,
    [".fb2"] = true,
    [".mobi"] = true,
    [".txt"] = true,
    [".html"] = true,
    [".doc"] = true,
}

local function isEmpty(s)
    return s == nil or s == ""
end

local function parseTitleFromPath(line)
    line = line:match("^%s*(.-)%s*$") or ""

    if extensions[line:sub(-4):lower()] then
        line = line:sub(1, -5)
    elseif extensions[line:sub(-5):lower()] then
        line = line:sub(1, -6)
    end

    local author = line:match("%s*%-?%s*%(([^()]*)%)%s*$")
    local title
    if author then
        title = line:gsub("%s*%-?%s*%([^()]*%)%s*$", "")
    else
        local t, a = line:match("^(.-)%s*%-%s*(.+)%s*$")
        if t and a then
            title = t
            author = a
        else
            title = line:match("^%s*(.-)[%s%-]*$")
        end
    end

    return isEmpty(title) and "Unknown Book" or title,
           isEmpty(author) and "Unknown Author" or author
end

-- Test cases
local test_cases = {
    "My Book (John Doe)",
    "My Book (2025) (John Doe)",
    "My Book - John Doe",
    "My Book (2025) - John Doe",
    "  My Book  (John Doe)  ",
    "My Book (John Doe).pdf",
    "My Book (test) Author",
    "My Book (test)))) () ) - Author",
    "My Book (test)))) () ) - (Author)",
    "My Book",
    " My Book   ",
    " My Book  - ",
    "My Book ()",
    "My Book -",
    "(Author Random)",
    "-Author Random",
    "",
}

-- Run the test cases
for _, line in ipairs(test_cases) do
    local title, author = parseTitleFromPath(line)
    print(string.format("Input: '%s'\n  Title: '%s'\n  Author: '%s'\n", line, title, author))
end
