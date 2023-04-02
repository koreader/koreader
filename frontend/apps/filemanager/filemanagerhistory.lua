local BD = require("ui/bidi")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local ConfirmBox = require("ui/widget/confirmbox")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local _ = require("gettext")
local C_ = _.pgettext
local T = require("ffi/util").template

local FileManagerHistory = WidgetContainer:extend{
    hist_menu_title = _("History"),
}

local filter_text = {
    all = C_("Book status filter", "All"),
    reading = C_("Book status filter", "Reading"),
    abandoned = C_("Book status filter", "On hold"),
    complete = C_("Book status filter", "Finished"),
    deleted = C_("Book status filter", "Deleted"),
    new = C_("Book status filter", "New"),
}

function FileManagerHistory:init()
    self.ui.menu:registerToMainMenu(self)
end

function FileManagerHistory:addToMainMenu(menu_items)
    menu_items.history = {
        text = self.hist_menu_title,
        callback = function()
            self:onShowHist()
        end,
    }
end

function FileManagerHistory:fetchStatuses(count)
    for _, v in ipairs(require("readhistory").hist) do
        v.status = v.dim and "deleted" or filemanagerutil.getStatus(v.file)
        if v.status == "new" and v.file == (self.ui.document and self.ui.document.file) then
            v.status = "reading" -- file currently opened for the first time
        end
        if count then
            self.count[v.status] = self.count[v.status] + 1
        end
    end
    self.statuses_fetched = true
end

function FileManagerHistory:updateItemTable()
    -- try to stay on current page
    local select_number = nil
    if self.hist_menu.page and self.hist_menu.perpage and self.hist_menu.page > 0 then
        select_number = (self.hist_menu.page - 1) * self.hist_menu.perpage + 1
    end
    self.count = { all = #require("readhistory").hist,
        reading = 0, abandoned = 0, complete = 0, deleted = 0, new = 0, }
    local item_table = {}
    for _, v in ipairs(require("readhistory").hist) do
        if self.filter == "all" or v.status == self.filter then
            table.insert(item_table, v)
        end
        if self.statuses_fetched then
            self.count[v.status] = self.count[v.status] + 1
        end
    end
    local title = self.hist_menu_title
    if self.filter ~= "all" then
        title = title .. " (" .. filter_text[self.filter] .. ": " .. self.count[self.filter] .. ")"
    end
    self.hist_menu:switchItemTable(title, item_table, select_number)
end

function FileManagerHistory:onSetDimensions(dimen)
    self.dimen = dimen
end

function FileManagerHistory:onMenuChoice(item)
    require("apps/reader/readerui"):showReader(item.file)
end

function FileManagerHistory:onMenuHold(item)
    self.histfile_dialog = nil
    local function close_dialog_callback()
        UIManager:close(self.histfile_dialog)
    end
    local function status_button_callback()
        UIManager:close(self.histfile_dialog)
        if self._manager.filter ~= "all" then
            self._manager:fetchStatuses(false)
        else
            self._manager.statuses_fetched = false
        end
        self._manager:updateItemTable()
        self._manager.files_updated = true -- sidecar folder may be created/deleted
    end
    local is_currently_opened = item.file == (self.ui.document and self.ui.document.file)

    local buttons = {}
    if not (item.dim or is_currently_opened) then
        table.insert(buttons, filemanagerutil.genStatusButtonsRow(item.file, status_button_callback))
        table.insert(buttons, {}) -- separator
    end
    table.insert(buttons, {
        filemanagerutil.genResetSettingsButton(item.file, status_button_callback, is_currently_opened),
        {
            text = _("Remove from history"),
            callback = function()
                UIManager:close(self.histfile_dialog)
                require("readhistory"):removeItem(item)
                self._manager:updateItemTable()
            end,
        },
    })
    table.insert(buttons, {
        {
            text = _("Delete"),
            enabled = not (item.dim or is_currently_opened),
            callback = function()
                local function post_delete_callback()
                    UIManager:close(self.histfile_dialog)
                    self._manager:updateItemTable()
                    self._manager.files_updated = true
                end
                local FileManager = require("apps/filemanager/filemanager")
                FileManager:showDeleteFileDialog(item.file, post_delete_callback)
            end,
        },
        filemanagerutil.genBookInformationButton(item.file, close_dialog_callback, item.dim),
    })
    table.insert(buttons, {
        filemanagerutil.genBookCoverButton(item.file, close_dialog_callback, item.dim),
        filemanagerutil.genBookDescriptionButton(item.file, close_dialog_callback, item.dim),
    })

    self.histfile_dialog = ButtonDialogTitle:new{
        title = BD.filename(item.text:match("([^/]+)$")),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.histfile_dialog)
    return true
end

-- Can't *actually* name it onSetRotationMode, or it also fires in FM itself ;).
function FileManagerHistory:MenuSetRotationModeHandler(rotation)
    if rotation ~= nil and rotation ~= Screen:getRotationMode() then
        UIManager:close(self._manager.hist_menu)
        -- Also re-layout ReaderView or FileManager itself
        if self._manager.ui.view and self._manager.ui.view.onSetRotationMode then
            self._manager.ui.view:onSetRotationMode(rotation)
        elseif self._manager.ui.onSetRotationMode then
            self._manager.ui:onSetRotationMode(rotation)
        else
            Screen:setRotationMode(rotation)
        end
        self._manager:onShowHist()
    end
    return true
end

function FileManagerHistory:onShowHist()
    self.hist_menu = Menu:new{
        ui = self.ui,
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        is_borderless = true,
        is_popout = false,
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function() self:showHistDialog() end,
        onMenuChoice = self.onMenuChoice,
        onMenuHold = self.onMenuHold,
        onSetRotationMode = self.MenuSetRotationModeHandler,
        _manager = self,
    }

    self.filter = G_reader_settings:readSetting("history_filter", "all")
    if self.filter ~= "all" then
        self:fetchStatuses(false)
    end
    self:updateItemTable()
    self.hist_menu.close_callback = function()
        if self.files_updated then -- refresh Filemanager list of files
            local FileManager = require("apps/filemanager/filemanager")
            if FileManager.instance then
                FileManager.instance:onRefresh()
            end
            self.files_updated = nil
        end
        self.statuses_fetched = nil
        UIManager:close(self.hist_menu)
        G_reader_settings:saveSetting("history_filter", self.filter)
    end
    UIManager:show(self.hist_menu)
    return true
end

function FileManagerHistory:showHistDialog()
    if not self.statuses_fetched then
        self:fetchStatuses(true)
    end

    local hist_dialog
    local buttons = {}
    local function genFilterButton(filter)
        return {
            text = T(_("%1 (%2)"), filter_text[filter], self.count[filter]),
            callback = function()
                UIManager:close(hist_dialog)
                self.filter = filter
                self:updateItemTable()
            end,
        }
    end
    table.insert(buttons, {
        genFilterButton("reading"),
        genFilterButton("abandoned"),
        genFilterButton("complete"),
    })
    table.insert(buttons, {
        genFilterButton("all"),
        genFilterButton("new"),
        genFilterButton("deleted"),
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
    hist_dialog = ButtonDialogTitle:new{
        title = _("Filter by book status"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(hist_dialog)
end

return FileManagerHistory
