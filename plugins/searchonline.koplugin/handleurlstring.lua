local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local url = require("socket.url")
local util = require("util")
local _ = require("gettext")

local HandleUrlString = {}

-- Message box to inform the user about a misformatted URL
function HandleUrlString:urlError(text_explaining_error)
    UIManager:show(InfoMessage:new{
        text = _(text_explaining_error),
        timeout = 3
    })
end

-- Check if the URL is valid and show an error if not
function HandleUrlString:isValidUrl(url_string)
    local parsed_url = url.parse(url_string)

    if not parsed_url then
        self.urlError("Could not parse URL. It may be misformatted: " .. url_string)
        return false
    end

    if not parsed_url.scheme then
        self.urlError("The URL is missing http:/https: " .. url_string)
        return false
    end

    if not parsed_url.host then
        self.urlError("Missing or invalid host: " .. url_string)
        return false
    end

    return true
end

function HandleUrlString:getDomainName(engine_url)
    -- Pre-set names for the defaults
    local defaultEngineNames = {
        ["https://html.duckduckgo.com/html?q={q}"] = "DuckDuckGo",
        ["https://google.com/search?q={q}"] = "Google",
        ["https://en.m.wiktionary.org/wiki/{q}"] = "Wiktionary",
        ["https://www.vocabulary.com/dictionary/{q}"] = "Vocabulary.com",
        ["https://www.merriam-webster.com/dictionary/{q}"] = "Merriam-Webster",
        ["https://www.dictionary.com/browse/{q}"] = "Dictionary.com"
    }
    local preset_name = defaultEngineNames[engine_url]
    if preset_name then
        return preset_name
    end

    -- Replace {q} placeholder with a dummy query string
    local clean_url = engine_url:gsub("{q}", "query")

    -- Attempt to parse the URL
    local parsed = url.parse(clean_url)
    -- Ensure parsed is a table and contains a host
    if type(parsed) ~= "table" or not parsed.host then
        return engine_url -- If parsing fails, return the raw string
    end

    local domain = parsed.host:gsub("^www%.", "") -- Remove 'www.'
    local path = parsed.path or ""

    -- Split domain into parts
    local domain_parts = {}
    for part in util.gsplit(domain, "%.") do
        table.insert(domain_parts, part)
    end

    -- Remove unwanted parts like www./.m. and the last part which is the .com/.org
    local cleaned_parts = {}
    for i = 1, #domain_parts - 1 do  -- Stop before the last part
        local part = domain_parts[i]:lower()
        if part ~= "www" and part ~= "m" and part ~= "html" then
            table.insert(cleaned_parts, domain_parts[i])
        end
    end

    -- Ensure at least one part remains
    if #cleaned_parts == 0 then
        return engine_url
    end

    -- Extract meaningful path component
    local path_part = ""
    if path and path ~= "" and path ~= "/" then
        -- Split path and process each component
        local path_components = {}
        for component in path:gmatch("([^/]+)") do
            -- Skip common non-descriptive components, file extensions, and single-character parts
            if #component > 1 and
                component ~= "search" and
                component ~= "browse" and
                component ~= "html" and
                component ~= "query" and
                not component:match("%.php$") and
                not component:match("%.html$") then
                table.insert(path_components, component)
            end
        end
        if #path_components > 0 then
            path_part = " " .. table.concat(path_components, " ")
        end
    end

    -- Combine parts and capitalise first letter of each word
    local display_name = (table.concat(cleaned_parts, " ") .. path_part)
        :gsub("(%w)([%w%-]*)", function(first, rest)
            return first:upper() .. rest:lower()
        end)

    return display_name
end

function HandleUrlString:validateUserAddedURL(url_string)
    -- Guard against nil input
    if url_string == nil then
        self:urlError("URL cannot be nil")
        return false
    end

    -- Ensure url_string is actually a string
    if type(url_string) ~= "string" then
        self:urlError("URL must be a string")
        return false
    end

    -- Trim whitespace from the beginning and end of the string
    url_string = url_string:gsub("^%s*(.-)%s*$", "%1")

    -- Check for empty string after trimming
    if url_string == "" then
        self:urlError("URL cannot be empty")
        return false
    end

    -- Check for {q} placeholder
    if not url_string:find("{q}") then
        self:urlError("The URL is misformatted, put {q} where the search term should go")
        return false
    end

    -- Ensure the URL starts with a valid scheme
    if not url_string:match("^https?://") then
        -- Prepend https:// if no scheme is present
        url_string = "https://" .. url_string
    end

    -- Clean up the URL (assuming util.cleanupSelectedText is a valid function)
    local cleaned_url = util.cleanupSelectedText(url_string)
    if not cleaned_url then
        self:urlError("Failed to clean URL")
        return false
    end

    -- Replace http:// with https:// for security
    cleaned_url = cleaned_url:gsub("^http://", "https://")

    -- Validate the cleaned URL with a pattern or a dedicated function
    if not self:isValidUrl(cleaned_url) then
        self:urlError("The URL is not valid")
        return false
    end

    return true
end

return HandleUrlString
