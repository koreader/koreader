local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local _ = require("gettext")
local KeyValuePage = require("ui/widget/keyvaluepage")
local DocSettings = require("docsettings")
local InfoMessage = require("ui/widget/infomessage")
local T = require("ffi/util").template
local RenderText = require("ui/rendertext")
local Font = require("ui/font")
local FileManagerHistory = InputContainer:extend{
    hist_menu_title = _("History"),
}

function FileManagerHistory:init()
    self.ui.menu:registerToMainMenu(self)
end

function FileManagerHistory:addToMainMenu(tab_item_table)
    -- insert table to main tab of filemanager menu
    table.insert(tab_item_table.main, {
        text = self.hist_menu_title,
        callback = function()
            self:onShowHist()
        end,
    })
end

function FileManagerHistory:updateItemTable()
    self.hist_menu:switchItemTable(self.hist_menu_title,
                                  require("readhistory").hist)
end

function FileManagerHistory:onSetDimensions(dimen)
    self.dimen = dimen
end

function FileManagerHistory:buildBookInformationTable(book_props)
    if book_props == nil then
        return false
    end

    if book_props.authors == "" or book_props.authors == nil then
        book_props.authors = _("N/A")
    end

    if book_props.title == "" or book_props.title == nil then
        book_props.title = _("N/A")
    end

    if book_props.series == "" or book_props.series == nil then
        book_props.series = _("N/A")
    end

    if book_props.pages == "" or book_props.pages == nil then
        book_props.pages = _("N/A")
    end

    if book_props.language == "" or book_props.language == nil then
        book_props.language = _("N/A")
    end

    return {
        { T(_("Title: %1"), book_props.title), "" },
        { T(_("Authors: %1"), book_props.authors), "" },
        { T(_("Series: %1"), book_props.series), "" },
        { T(_("Pages: %1"), book_props.pages), "" },
        { T(_("Language: %1"), string.upper(book_props.language)), "" },
    }
end

function FileManagerHistory:bookInformation(file)
    local file_mode = lfs.attributes(file, "mode")
    if file_mode ~= "file" then return false end
    local book_stats = DocSettings:open(file):readSetting('stats')
    if book_stats == nil then return false end
    return self:buildBookInformationTable(book_stats)
end

function FileManagerHistory:onMenuHold(item)
    local font_size = Font:getFace("tfont")
    local text_remove_hist = _("Remove \"%1\" from history")
    local text_remove_without_item = T(text_remove_hist, "")
    local text_remove_hist_width = (RenderText:sizeUtf8Text(
        0, self.width, font_size, text_remove_without_item).x )
    local text_item_width = (RenderText:sizeUtf8Text(
        0, self.width , font_size, item.text).x )

    local item_trun
    if self.width < text_remove_hist_width + text_item_width then
        item_trun = RenderText:truncateTextByWidth(item.text, font_size, 1.2 * self.width - text_remove_hist_width)
    else
        item_trun = item.text
    end
    local text_remove = T(text_remove_hist, item_trun)

    self.histfile_dialog = ButtonDialog:new{
        buttons = {
            {
                {
                    text = text_remove,
                    callback = function()
                        require("readhistory"):removeItem(item)
                        self._manager:updateItemTable()
                        UIManager:close(self.histfile_dialog)
                    end,
                },
            },
            {
                {
                    text = _("Book information"),
                    callback = function()
                        local book_info_metadata = FileManagerHistory:bookInformation(item.file)
                        if  book_info_metadata then
                            UIManager:show(KeyValuePage:new{
                                title = _("Book information"),
                                kv_pairs = book_info_metadata,
                            })
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("Cannot fetch information for a selected book"),
                            })
                        end
                        UIManager:close(self.histfile_dialog)
                    end,
                 },
            },
            {},
            {
                {
                    text = _("Clear history of deleted files"),
                    callback = function()
                        require("readhistory"):clearMissing()
                        self._manager:updateItemTable()
                        UIManager:close(self.histfile_dialog)
                    end,
                 },
            },
        },
    }
    UIManager:show(self.histfile_dialog)
    return true
end

function FileManagerHistory:onShowHist()
    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
    }

    self.hist_menu = Menu:new{
        ui = self.ui,
        width = Screen:getWidth()-50,
        height = Screen:getHeight()-50,
        show_parent = menu_container,
        onMenuHold = self.onMenuHold,
        _manager = self,
    }
    self:updateItemTable()

    table.insert(menu_container, self.hist_menu)

    self.hist_menu.close_callback = function()
        UIManager:close(menu_container)
    end

    UIManager:show(menu_container)
    return true
end

return FileManagerHistory
