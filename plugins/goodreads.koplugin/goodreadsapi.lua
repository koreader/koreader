local InputContainer = require("ui/widget/container/inputcontainer")
local GoodReaderBook = require("goodreaderbook")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local url = require('socket.url')
local socket = require('socket')
local http = require('socket.http')
local https = require('ssl.https')
local ltn12 = require('ltn12')
local _ = require("gettext")

local GoodReadsApi = InputContainer:new {
    goodreadersKey = "",
    goodreadersSecret = "",
    total_result = 0,
}

function GoodReadsApi:init()
end

local function genSearchURL(text_search, userApi, search_type, npage)
    if (text_search) then
        text_search = string.gsub (text_search, "\n", "\r\n")
        text_search = string.gsub (text_search, "([^%w %-%_%.%~])",
            function (c) return string.format ("%%%02X", string.byte(c)) end)
        text_search = string.gsub (text_search, " ", "+")
    end
    return (string.format(
        "http://www.goodreads.com/search?q=%s&search[field]=%s&format=xml&key=%s&page=%s",
        text_search,
        search_type,
        userApi,
        npage
    ))
end

local function genIdUrl(id, userApi)
    return (string.format(
        "https://www.goodreads.com/book/show/%s?format=xml&key=%s",
        id,
        userApi
    ))
end

function GoodReadsApi:fetchXml(s_url)
    local request, sink = {}, {}
    local parsed = url.parse(s_url)
    request['url'] = s_url
    request['method'] = 'GET'
    request['sink'] = ltn12.sink.table(sink)
    http.TIMEOUT = 5
    https.TIMEOUT = 5
    local httpRequest = parsed.scheme == 'http' and http.request or https.request
    local headers = socket.skip(1, httpRequest(request))
    if headers == nil then
        return nil
    end
    local xml = table.concat(sink)
    if xml ~= "" then
        return xml
    end
end

function GoodReadsApi:showSearchTable(data)
    local books = {}
    if data == nil then
        UIManager:show(InfoMessage:new{text =_("Network problem.\nCheck connection.")})
        return {}
    end
    self.total_result = data:match("<total[-]results>(.*)</total[-]results>")

    for work in data:gmatch("<work>(.-)</work>") do
        local book = work:match("<best_book[^>]+>(.*)</best_book>")
        local id = book:match("<id[^>]+>([^<]+)</id>")
        local title = book:match("<title>([^<]+)</title>"):gsub(" %(.*, #%d+%)$", "")
        local author = book:match("<name>([^<]+)</name>")
        table.insert(books, {
            author = author,
            title = title,
            id = id,
        })
    end
    if #books == 0 then
        UIManager:show(InfoMessage:new{text =_("Search not found!")})
    end
    return books
end

function GoodReadsApi:getTotalResults()
    return self.total_result
end

local function showIdTable(data)
    if data == nil then
        UIManager:show(InfoMessage:new{text =_("Network problem.\nCheck connection.")})
        return {}
    end
    local data1 = data:match("<book>(.*)</reviews_widget>")
    local title_all = data1:match("<title>(.*)</title>"):gsub("<![[]CDATA[[]", ""):gsub("]]>$", "")
    local title = title_all:gsub(" %(.*, #%d+%)$", "")
    local average_rating = data1:match("<average_rating>([^<]+)</average_rating>")
    local series = title_all:match("%(.*, #%d+%)$")
    if series ~= nil then
        series = series:match("[(](.*)[)]")
    else
        series = _("N/A")
    end
    local num_pages = data1:match("<num_pages>(.*)</num_pages>"):gsub("<![[]CDATA[[]", ""):gsub("]]>$", "")
    if num_pages == nil or num_pages =="" then
        num_pages = _("N/A")
    end
    local id = data1:match("<id>([^<]+)</id>"):gsub("<![[]CDATA[[]", ""):gsub("]]>$", "")
    local author = data1:match("<name>([^<]+)</name>")
    local description = data1:match("<description>(.*)</description>")
    description = description:gsub("<![[]CDATA[[]", ""):gsub("]]>$", ""):gsub("<br>", "")
    --change format from medium to large
    local image = data1:match("<image_url>([^<]+)</image_url>"):gsub("([0-9]+)m/", "%1l/")
    local day = data1:match("<original_publication_day[^>]+>([^<]+)</original_publication_day>")
    local month = data1:match("<original_publication_month[^>]+>([^<]+)</original_publication_month>")
    local year = data1:match("<original_publication_year[^>]+>([^<]+)</original_publication_year>")

    local release = {}
    if(year) then
        table.insert(release, year)
    end
    if(month) then
        table.insert(release, string.format("%02d", month))
    end
    if(day) then
        table.insert(release, string.format("%02d", day))
    end
    release = table.concat(release, "-")
    if release == {} or release == nil or release == "" then
        release = _("N/A")
    end
    local book_info = {
        title = title,
        author = author,
        series = series,
        rating = average_rating,
        pages = num_pages,
        release = release,
        description = description,
        image = image,
        id = id,
    }
    if id == nil then
        UIManager:show(InfoMessage:new{text =_("Search not found!")})
    end
    return book_info
end

-- search_type = all - search all
-- search_type = author - serch book by author
-- search_type = title - search book by title
function GoodReadsApi:showData(search_text, search_type, page, goodreadersKey)
    local stats = {}
    local gen_url = genSearchURL(search_text, goodreadersKey, search_type, page)
    local gen_xml = self:fetchXml(gen_url)
    local tbl = self:showSearchTable(gen_xml)
    if #tbl == 0 then
        return nil
    end
    for _, v in pairs(tbl) do
        local author = v.author
        local title = v.title
        local id = v.id
        table.insert(stats, { author,
            title,
            callback = function()
                local dates = self:showIdData(id, goodreadersKey)
                if dates.id ~= nil then
                    UIManager:show(GoodReaderBook:new{
                        dates = dates,
                    })
                end
            end,
        })
    end
    return stats
end

function GoodReadsApi:showIdData(id, goodreadersKey)
    local gen_url = genIdUrl(id, goodreadersKey)
    local gen_xml = self:fetchXml(gen_url)
    local tbl = showIdTable(gen_xml)
    return tbl
end

return GoodReadsApi
