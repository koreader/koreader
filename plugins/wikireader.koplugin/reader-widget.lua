local Geom = require("ui/geometry")
local ConfirmBox = require("ui/widget/confirmbox")
local logger = require("logger")
local log = logger.dbg

local Device = require("device")
local UIManager = require("ui/uimanager")
local SQ3 = require("lua-ljsqlite3/init")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local TouchMenu = require("ui/widget/touchmenu")
local Screen = require("device").screen
local Menu = require("ui/widget/menu")

local zstd = require("ffi/zstd")
local ffi = require("ffi")

local DataStorage = require("datastorage")
local ReaderUI = require("apps/reader/readerui")
local FileConverter = require("apps/filemanager/filemanagerconverter")
local ReaderLink = require("apps/reader/modules/readerlink")
local ReadHistory = require("readhistory")
local BaseUtil = require("ffi/util")
local _ = require("gettext")

local WikiReaderWidget = {
    name = "wikireader-widget",
    db_conn = nil,
    input_dialog = nil,
    css = '',
    history = {},
}

function WikiReaderWidget:addCurrentTitleToFavorites()
    local currentTitle = self.history[#self.history]
    local favorites = G_reader_settings:readSetting("wikireader-favorites") or {}
    table.insert(favorites, currentTitle)
    G_reader_settings:saveSetting("wikireader-favorites", favorites)

    local newFavorites = G_reader_settings:readSetting("wikireader-favorites")
    log("saved favorites:", newFavorites)
end

function WikiReaderWidget:overrideLinkHandler()
    if ReaderUI.instance == nil then
        log("Got nil readerUI instance, canceling")
        return
    end
    ReaderUI.postInitCallback = {}  -- To make ReaderLink shut up
    local ui_link_module_instance = ReaderLink:new{
        dialog = ReaderUI.instance.dialog,
        view = ReaderUI.instance.view,
        ui = ReaderUI.instance,
        document = ReaderUI.instance.document,
    }

    ReaderLink.original_onGotoLink = ReaderLink.onGotoLink

    function ReaderLink:onGotoLink (link, neglect_current_location, allow_footnote_popup)
        local link_uri = link["xpointer"]
        if (link_uri:find("^WikiReader:") ~= nil) then
            -- This is a wiki reader URL, handle it here
            local article_title = link_uri:sub(12) -- Remove prefix
            WikiReaderWidget:gotoTitle(article_title)
            return true -- Don't propagate
        else
            log("Passing forward to original handler")
            self:original_onGotoLink(link, neglect_current_location, allow_footnote_popup)
        end
    end
 
    ReaderUI:registerModule("link", ui_link_module_instance)
    ReaderUI.postInitCallback = nil
end

function WikiReaderWidget:new(db_file, first_page_title)
    UIManager:show(InfoMessage:new{
        text = _("Opening db: ") .. db_file,
        timeout = 2 
    })
    
    self.db_conn = SQ3.open(db_file)
    -- Load css
    self:loadCSS()
    -- First load the first page
    self:gotoTitle(first_page_title)
    UIManager:scheduleIn(0.1, function()
        self:overrideLinkHandler()
    end)
    return self
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

function WikiReaderWidget:loadCSS()
    -- Curently not supported properly
    do return end
    local get_css_stmt = self.db_conn:prepare(
        "SELECT content_zstd FROM css LIMIT 1;"
    )
    local css_row = get_css_stmt:bind():step()
    local cssBlob = css_row[1]
    local css_data, css_size = zstd.zstd_uncompress(cssBlob[1], cssBlob[2])
    local css = ffi.string(css_data, css_size)
    self.css = css
end

function WikiReaderWidget:gotoTitle(new_title)
    local new_title = new_title:gsub("_", " ")

    UIManager:show(InfoMessage:new{
        text = _("Searching for title: ") .. new_title,
        timeout = 1
    })

    local get_title_stmt = self.db_conn:prepare(
        "SELECT id FROM title_2_id WHERE title_lower_case = ?;"
    )
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
        local get_page_content_stmt = self.db_conn:prepare("SELECT id, title, page_content_zstd FROM articles WHERE id = ?;")
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
            local actual_previous_title = self.history[#self.history - 1]
            if actual_previous_title then
                local go_back_anchor = "<h3><a href=\"" .. actual_previous_title .. _("\">Go back to ") .. actual_previous_title:gsub("_", " ") .. "</a></h3>"
                html = html:gsub("</h1>", "</h1>" .. go_back_anchor, 1)
            end

            log("replacing href's")
            html = html:gsub('<a%s+href="', '<a href="WikiReader:')
            html = html:gsub('<a%s+href=\'', '<a href=\'WikiReader:')
            -- Now add css to html, if any
            local head_index = html:find("</head>")
            if head_index ~= nil and self.css ~= nil and false then
                html = html:sub(1, head_index - 1) .. "<style>" .. self.css .. "</style>" .. html:sub(head_index)
            end
            
            self:showArticle(id, html)
            log("History after load ", self.history)
        end
    end
end


function WikiReaderWidget:createInputDialog(title, buttons)
    self.input_dialog = InputDialog:new{
        title = title,
        input = "",
        input_hint = "",
        input_type = "text",
        buttons = {
            buttons,
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.input_dialog)
                    end,
                },
            },
        }
    }
end

function WikiReaderWidget:showSearchResultsMenu(search_results)
    local menu_items = {}

    for i = 1, #search_results do
        local search_result = search_results[i]
        local new_table_item = {
            text = search_result.title,
            callback = function ()
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
        height = Screen:getHeight(),
    }
    UIManager:show(self.searchResultMenu)
end



function WikiReaderWidget:exhaustiveSearch(title, max_num_search_results)
    local title = title:gsub("_", " ")
    local lowercase_title = title:lower()
    max_num_search_results = max_num_search_results or 50

    local full_db_search_sql = [[
        SELECT id, title_lower_case FROM title_2_id WHERE title_lower_case LIKE "%" || ? || "%"
        LIMIT ?;
    ]]

    log("Got title:", lowercase_title)

    local get_title_stmt = self.db_conn:prepare(full_db_search_sql)
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
        if self.input_dialog:getInputText() == "" then return end

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

    local buttons = {
        {
            text = _("Search"),
            callback = function() search_callback(false) end
        },
        {
            text = _("Exhaustive Search (slow)"),
            callback = function() search_callback(true) end
        }
    }

    self:createInputDialog(_("Search Wikipedia"), buttons)
    
    UIManager:show(self.input_dialog)
    self.input_dialog:onShowKeyboard()
end

return WikiReaderWidget