local BD = require("ui/bidi")
local BookList = require("ui/widget/booklist")
local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local InputDialog = require("ui/widget/inputdialog")
local ReadCollection = require("readcollection")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Utf8Proc = require("ffi/utf8proc")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local FileManagerHistory = WidgetContainer:extend{
    title = _("History"),
}

function FileManagerHistory:init()
    self.ui.menu:registerToMainMenu(self)
end

function FileManagerHistory:addToMainMenu(menu_items)
    menu_items.history = {
        text = self.title,
        callback = function()
            self:onShowHist()
        end,
    }
end

function FileManagerHistory:fetchStatuses(count)
    for _, v in ipairs(require("readhistory").hist) do
        local status
        if v.dim then -- deleted file
            status = "deleted"
        elseif v.file == (self.ui.document and self.ui.document.file) then -- currently opened file
            status = self.ui.doc_settings:readSetting("summary").status
        else
            status = BookList.getBookStatus(v.file)
        end
        if count then
            self.count[status] = self.count[status] + 1
        end
        v.status = status
    end
    self.statuses_fetched = true
end

function FileManagerHistory:refreshFileManager()
    if self.files_updated then
        if self.ui.file_chooser then
            self.ui.file_chooser:refreshPath()
        end
        self.files_updated = nil
    end
end

function FileManagerHistory:onShowHist(search_info)
    -- This may be hijacked by CoverBrowser plugin and needs to be known as booklist_menu.
    self.booklist_menu = BookList:new{
        name = "history",
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function() self:showHistDialog() end,
        onMenuChoice = self.onMenuChoice,
        onMenuHold = self.onMenuHold,
        ui = self.ui,
        _manager = self,
        _recreate_func = function() self:onShowHist(search_info) end,
        search_callback = function(search_string)
            self.search_string = search_string
            self:onSearchHistory()
        end,
    }
    self.booklist_menu.close_callback = function()
        self:refreshFileManager()
        UIManager:close(self.booklist_menu)
        self.booklist_menu = nil
        self.statuses_fetched = nil
        G_reader_settings:saveSetting("history_filter", self.filter)
    end

    if search_info then
        self.search_string = search_info.search_string
        self.case_sensitive = search_info.case_sensitive
    else
        self.search_string = nil
        self.selected_collections = nil
    end
    self.filter = G_reader_settings:readSetting("history_filter", "all")
    self.is_frozen = G_reader_settings:isTrue("history_freeze_finished_books")
    if self.filter ~= "all" or self.is_frozen then
        self:fetchStatuses(false)
    end
    self:updateItemTable()
    UIManager:show(self.booklist_menu)
    return true
end

function FileManagerHistory:updateItemTable()
    self.count = { all = #require("readhistory").hist,
        reading = 0, abandoned = 0, complete = 0, deleted = 0, new = 0, }
    local item_table = {}
    for _, v in ipairs(require("readhistory").hist) do
        if self:isItemMatch(v) then
            local item = util.tableDeepCopy(v)
            if item.select_enabled and ReadCollection:isFileInCollections(item.file) then
                item.mandatory = "☆ " .. item.mandatory
            end
            if self.is_frozen and item.status == "complete" then
                item.mandatory_dim = true
            end
            table.insert(item_table, item)
        end
        if self.statuses_fetched then
            self.count[v.status] = self.count[v.status] + 1
        end
    end
    local title, subtitle = self:getBookListTitle(item_table)
    self.booklist_menu:switchItemTable(title, item_table, -1, nil, subtitle)
end

function FileManagerHistory:isItemMatch(item)
    if self.search_string then
        local filename = self.case_sensitive and item.text or Utf8Proc.lowercase(util.fixUtf8(item.text, "?"))
        if not filename:find(self.search_string) then
            local book_props = self.ui.bookinfo:getDocProps(item.file, nil, true) -- do not open the document
            if not self.ui.bookinfo:findInProps(book_props, self.search_string, self.case_sensitive) then
                return false
            end
        end
    end
    if self.selected_collections then
        for name in pairs(self.selected_collections) do
            if not ReadCollection:isFileInCollection(item.file, name) then
                return false
            end
        end
    end
    return self.filter == "all" or item.status == self.filter
end

function FileManagerHistory:getBookListTitle(item_table)
    local title = T(_("History (%1)"), #item_table)
    local subtitle = ""
    if self.search_string then
        subtitle = T(_("Query: %1"), self.search_string)
    elseif self.selected_collections then
        local collections = {}
        for collection in pairs(self.selected_collections) do
            table.insert(collections, self.ui.collections:getCollectionTitle(collection))
        end
        if #collections == 1 then
            collections = collections[1]
        else
            table.sort(collections)
            collections = table.concat(collections, ", ")
        end
        subtitle = T(_("Collections: %1"), collections)
    elseif self.filter ~= "all" then
        subtitle = BookList.getBookStatusString(self.filter, true)
    end
    return title, subtitle
end

function FileManagerHistory:onSetDimensions(dimen)
    self.dimen = dimen
end

function FileManagerHistory:onMenuChoice(item)
    if self.ui.document then
        if self.ui.document.file ~= item.file then
            self.ui:switchDocument(item.file)
        end
    else
        self.ui:openFile(item.file)
    end
end

function FileManagerHistory:onMenuHold(item)
    local file = item.file
    self.file_dialog = nil
    local book_props = self.ui.coverbrowser and self.ui.coverbrowser:getBookInfo(file)

    local function close_dialog_callback()
        UIManager:close(self.file_dialog)
    end
    local function close_dialog_menu_callback()
        UIManager:close(self.file_dialog)
        self.close_callback()
    end
    local function close_dialog_update_callback()
        UIManager:close(self.file_dialog)
        if self._manager.filter ~= "all" or self._manager.is_frozen then
            self._manager:fetchStatuses(false)
        else
            self._manager.statuses_fetched = false
        end
        self._manager:updateItemTable()
        self._manager.files_updated = true
    end
    local function update_callback()
        self._manager:updateItemTable()
    end
    local is_currently_opened = file == (self.ui.document and self.ui.document.file)

    local buttons = {}
    local doc_settings_or_file
    if is_currently_opened then
        doc_settings_or_file = self.ui.doc_settings
        if not book_props then
            book_props = self.ui.doc_props
            book_props.has_cover = true
        end
    else
        if BookList.hasBookBeenOpened(file) then
            doc_settings_or_file = BookList.getDocSettings(file)
            if not book_props then
                local props = doc_settings_or_file:readSetting("doc_props")
                book_props = self.ui.bookinfo.extendProps(props, file)
                book_props.has_cover = true
            end
        else
            doc_settings_or_file = file
        end
    end
    if not item.dim then
        table.insert(buttons, filemanagerutil.genStatusButtonsRow(doc_settings_or_file, close_dialog_update_callback))
        table.insert(buttons, {}) -- separator
    end
    table.insert(buttons, {
        filemanagerutil.genResetSettingsButton(doc_settings_or_file, close_dialog_update_callback, is_currently_opened),
        self._manager.ui.collections:genAddToCollectionButton(file, close_dialog_callback, update_callback, item.dim),
    })
    table.insert(buttons, {
        {
            text = _("Delete"),
            enabled = not (item.dim or is_currently_opened),
            callback = function()
                local FileManager = require("apps/filemanager/filemanager")
                FileManager:showDeleteFileDialog(file, close_dialog_update_callback)
            end,
        },
        {
            text = _("Remove from history"),
            callback = function()
                UIManager:close(self.file_dialog)
                -- The item's idx field is tied to the current *view*, so we can only pass it as-is when there's no filtering *at all* involved.
                local index = item.idx
                if self._manager.search_string or self._manager.selected_collections or self._manager.filter ~= "all" then
                    index = nil
                end
                require("readhistory"):removeItem(item, index)
                self._manager:updateItemTable()
            end,
        },
    })
    table.insert(buttons, {
        filemanagerutil.genShowFolderButton(file, close_dialog_menu_callback, item.dim),
        filemanagerutil.genBookInformationButton(doc_settings_or_file, book_props, close_dialog_callback, item.dim),
    })
    table.insert(buttons, {
        filemanagerutil.genBookCoverButton(file, book_props, close_dialog_callback, item.dim),
        filemanagerutil.genBookDescriptionButton(file, book_props, close_dialog_callback, item.dim),
    })

    if self._manager.file_dialog_added_buttons ~= nil then
        for _, row_func in ipairs(self._manager.file_dialog_added_buttons) do
            local row = row_func(file, true, book_props)
            if row ~= nil then
                table.insert(buttons, row)
            end
        end
    end

    self.file_dialog = ButtonDialog:new{
        title = BD.filename(item.text),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.file_dialog)
    return true
end

function FileManagerHistory.getMenuInstance()
    local ui = require("apps/filemanager/filemanager").instance or require("apps/reader/readerui").instance
    return ui.history.booklist_menu
end

function FileManagerHistory:showHistDialog()
    if not self.statuses_fetched then
        self:fetchStatuses(true)
    end

    local hist_dialog
    local buttons = {}
    local function genFilterButton(filter)
        return {
            text = T(_("%1 (%2)"), BookList.getBookStatusString(filter), self.count[filter]),
            callback = function()
                UIManager:close(hist_dialog)
                self.filter = filter
                if filter == "all" then -- reset all filters
                    self.search_string = nil
                    self.selected_collections = nil
                end
                self:updateItemTable()
            end,
        }
    end
    table.insert(buttons, {
        genFilterButton("all"),
        genFilterButton("new"),
        genFilterButton("deleted"),
    })
    table.insert(buttons, {
        genFilterButton("reading"),
        genFilterButton("abandoned"),
        genFilterButton("complete"),
    })
    table.insert(buttons, {
        {
            text = _("Filter by collections"),
            callback = function()
                UIManager:close(hist_dialog)
                local caller_callback = function(selected_collections)
                    self.selected_collections = selected_collections
                    self:updateItemTable()
                end
                self.ui.collections:onShowCollList(self.selected_collections or {}, caller_callback, true) -- no dialog to apply
            end,
        },
    })
    table.insert(buttons, {
        {
            text = _("Search in filename and book metadata"),
            callback = function()
                UIManager:close(hist_dialog)
                self:onSearchHistory()
            end,
        },
    })
    if self.count.deleted > 0 then
        table.insert(buttons, {}) -- separator
        table.insert(buttons, {
            {
                text = _("Clear history of deleted files"),
                callback = function()
                    local confirmbox = ConfirmBox:new{
                        text = _("Clear history of deleted files?"),
                        ok_text = _("Clear"),
                        ok_callback = function()
                            UIManager:close(hist_dialog)
                            require("readhistory"):clearMissing()
                            self:updateItemTable()
                        end,
                    }
                    UIManager:show(confirmbox)
                end,
            },
        })
    end
    hist_dialog = ButtonDialog:new{
        title = _("Filter by book status"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(hist_dialog)
end

function FileManagerHistory:onSearchHistory()
    local search_dialog, check_button_case
    search_dialog = InputDialog:new{
        title = _("Enter text to search history for"),
        input = self.search_string,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(search_dialog)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local search_string = search_dialog:getInputText()
                        if search_string ~= "" then
                            UIManager:close(search_dialog)
                            self.search_string = self.case_sensitive and search_string or search_string:lower()
                            if self.booklist_menu then -- called from History
                                self:updateItemTable()
                            else -- called by Dispatcher
                                local search_info = {
                                    search_string = self.search_string,
                                    case_sensitive = self.case_sensitive,
                                }
                                self:onShowHist(search_info)
                            end
                        end
                    end,
                },
            },
        },
    }
    check_button_case = CheckButton:new{
        text = _("Case sensitive"),
        checked = self.case_sensitive,
        parent = search_dialog,
        callback = function()
            self.case_sensitive = check_button_case.checked
        end,
    }
    search_dialog:addWidget(check_button_case)
    UIManager:show(search_dialog)
    search_dialog:onShowKeyboard()
    return true
end

function FileManagerHistory:onBookMetadataChanged()
    if self.booklist_menu then
        self.booklist_menu:updateItems()
    end
end

return FileManagerHistory
