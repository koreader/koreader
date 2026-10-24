local logger = require("logger")
local log = logger.dbg

local UIManager = require("ui/uimanager")
local SQ3 = require("lua-ljsqlite3/init")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Screen = require("device").screen
local Menu = require("ui/widget/menu")

local zstd = require("ffi/zstd")
local ffi = require("ffi")
local escape = require("turbo.escape")

local DataStorage = require("datastorage")
local ReaderUI = require("apps/reader/readerui")
local FileConverter = require("apps/filemanager/filemanagerconverter")
local ReadHistory = require("readhistory")
local BaseUtil = require("ffi/util")
local _ = require("gettext")

local WikiReaderWidget = {
    name = "wikireader-widget",
    db_conn = nil,
    input_dialog = nil,
    db_path = nil,
    history = {}
}

local function replace(haystack, needle, replacement)
    local escapedReplacement = replacement:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", function(c) return "%" .. c end)
    return haystack:gsub(needle, escapedReplacement)
end

function WikiReaderWidget:addCurrentTitleToFavorites()
    local currentTitle = self.history[#self.history]
    local favorites = G_reader_settings:readSetting("wikireader-favorites") or {}
    table.insert(favorites, currentTitle)
    G_reader_settings:saveSetting("wikireader-favorites", favorites)

    local newFavorites = G_reader_settings:readSetting("wikireader-favorites")
    log("saved favorites:", newFavorites)
end

function WikiReaderWidget:new(db_file, first_page_title)
    UIManager:show(InfoMessage:new{
        text = _("Opening db: ") .. db_file,
        timeout = 2
    })
    self.db_path = db_file
    -- First load the first page
    if first_page_title ~= nil then
        self:gotoTitle(first_page_title)
    end

    return self
end

function WikiReaderWidget:getDBconn(db_path)
    if self.db_conn then
        return self.db_conn
    end
    if self.db_path == nil and db_path == nil then
        log("No db specified")
    end
    if db_path ~= nil then
        self.db_path = db_path
    end
    self.db_conn = SQ3.open(self.db_path)
    return self.db_conn
end

function WikiReaderWidget:showArticle(id, html)
    local html_dir = DataStorage:getDataDir() .. "/cache/"
    local article_filename = ("%s/wikireader-%s.html"):format(html_dir, id)
    FileConverter:writeStringToFile(html, article_filename)

    ReaderUI:showReader(article_filename)
    UIManager:scheduleIn(1, function()
        local absolute_article_path = BaseUtil.realpath(article_filename)
        ReadHistory:removeItemByPath(absolute_article_path) -- Remove from history again
    end)
    ReadHistory:removeItemByPath(article_filename)
end

function WikiReaderWidget:gotoTitle(new_title, db_path)
    new_title = new_title:gsub("_", " ")

    UIManager:show(InfoMessage:new{
        text = _("Searching for title: ") .. new_title,
        timeout = 1
    })
    local db_conn = self:getDBconn(db_path)
    local get_title_stmt = db_conn:prepare("SELECT id FROM title_2_id WHERE title_lower_case = ?;")
    local title_row = get_title_stmt:bind(new_title:lower()):step()

    log("Got title row ", title_row)
    if title_row == nil then
        UIManager:show(InfoMessage:new{
            text = "Page: " .. new_title .. " not indexed",
            timeout = 2
        })
    else
        local id = title_row[1]
        -- Try to get the html from the row using the id
        local get_page_content_stmt = db_conn:prepare(
            "SELECT id, title, page_content_zstd FROM articles WHERE id = ?;")
        local article_row = get_page_content_stmt:bind(id):step()
        log("Got article_row row ", article_row)
        if article_row == nil then
            UIManager:show(InfoMessage:new{
                text = _("Page: ") .. new_title .. _(" not found"),
                timeout = 2
            })
        else
            UIManager:show(InfoMessage:new{
                text = _("Loading page: ") .. new_title,
                timeout = 1
            })
            local htmlBlob = article_row[3]
            local html_data, html_size = zstd.zstd_uncompress(htmlBlob[1], htmlBlob[2])
            local html = ffi.string(html_data, html_size)

            log("History before load ", self.history)
            local current_title = self.history[#self.history]
            local previous_title = self.history[#self.history - 1]

            if current_title ~= nil then
                if new_title ~= previous_title then
                    -- Add new title to the history
                    table.insert(self.history, new_title)
                else
                    -- We are going to the last page, so remove the title from the history
                    table.remove(self.history, #self.history)
                end
            else
                table.insert(self.history, new_title)
            end
            if new_title == current_title then
                -- Not sure how, but we are going to the same page. remove the same title from history
                table.remove(self.history, #self.history)
            end

            html = self:transformHTML(html)
            self:showArticle(id, html)
            log("History after load ", self.history)
        end
    end
end

function WikiReaderWidget:transformHTML(html)
    local actual_previous_title = self.history[#self.history - 1]
    if actual_previous_title then
        local go_back_anchor = "<h3><a href=\"" .. actual_previous_title .. _("\">Go back to ") ..
                                   actual_previous_title:gsub("_", " ") .. "</a></h3>"
        html = html:gsub("</h1>", "</h1>" .. go_back_anchor, 1)
    end

    -- Encode the db path in the URL, URL escaping doesn't work for some reason, so use base64
    local prefix = "kolocalwiki://" .. escape.base64_encode(self.db_path) .. "#" -- Title will be after the hashtag
    log("replacing href's", prefix)
    html = replace(html, '<a%s+href="', '<a href="' .. prefix)
    html = replace(html, '<a%s+href=\'', '<a href=\'' .. prefix)
    return html
end


function WikiReaderWidget:createInputDialog(title, buttons)
    self.input_dialog = InputDialog:new{
        title = title,
        input = "",
        input_hint = "",
        input_type = "text",
        buttons = {buttons, {{
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self.input_dialog)
            end
        }}}
    }
end

function WikiReaderWidget:showSearchResultsMenu(search_results)
    local menu_items = {}

    for i = 1, #search_results do
        local search_result = search_results[i]
        local new_table_item = {
            text = search_result.title,
            callback = function()
                if self.searchResultMenu ~= nil then
                    self.searchResultMenu:onClose()
                    self.searchResultMenu = nil
                end
                self:gotoTitle(search_result.title)
            end
        }

        table.insert(menu_items, new_table_item)
    end

    self.searchResultMenu = Menu:new{
        title = _("Search Results"),
        item_table = menu_items,
        is_enable_shortcut = false,
        width = Screen:getWidth(),
        height = Screen:getHeight()
    }
    UIManager:show(self.searchResultMenu)
end

function WikiReaderWidget:exhaustiveSearch(title, max_num_search_results, db_path)
    title = title:gsub("_", " ")
    local lowercase_title = title:lower()
    max_num_search_results = max_num_search_results or 50

    local full_db_search_sql = [[
        SELECT id, title_lower_case FROM title_2_id WHERE title_lower_case LIKE "%" || ? || "%"
        LIMIT ?;
    ]]

    log("Got title:", lowercase_title)

    local db_conn = self:getDBconn(db_path)
    local get_title_stmt = db_conn:prepare(full_db_search_sql)
    local get_title_binding = get_title_stmt:bind(lowercase_title, max_num_search_results)

    local search_results = {}
    for i = 1, max_num_search_results do
        local title_row = get_title_binding:step()
        if title_row then
            table.insert(search_results, {
                id = title_row[1],
                title = title_row[2]
            })
        end
    end
    self:showSearchResultsMenu(search_results)
end

function WikiReaderWidget:showSearchBox()
    local search_callback = function(is_exhaustive)
        if self.input_dialog:getInputText() == "" then
            return
        end

        UIManager:close(self.input_dialog)
        local title = self.input_dialog:getInputText()
        if title and title ~= "" then
            if is_exhaustive then
                self:exhaustiveSearch(title)
            else
                self:gotoTitle(title)
            end
        end
    end

    local buttons = {{
        text = _("Search"),
        callback = function()
            search_callback(false)
        end
    }, {
        text = _("Exhaustive Search (slow)"),
        callback = function()
            search_callback(true)
        end
    }}

    self:createInputDialog(_("Search Wikipedia"), buttons)

    UIManager:show(self.input_dialog)
    self.input_dialog:onShowKeyboard()
end

return WikiReaderWidget