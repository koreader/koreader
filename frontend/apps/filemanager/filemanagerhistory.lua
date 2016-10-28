local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local util = require("ffi/util")
local _ = require("gettext")
local KeyValuePage = require("ui/widget/keyvaluepage")
local DocSettings = require("docsettings")



local FileManagerHistory = InputContainer:extend{
    hist_menu_title = _("History"),
}

function FileManagerHistory:init()
    self.ui.menu:registerToMainMenu(self)
end

function FileManagerHistory:addToMainMenu(tab_item_table)
    -- insert table to info tab of filemanager menu
    table.insert(tab_item_table.info, {
        text = self.hist_menu_title,
        callback = function()
            self:onShowHist()
        end,
    })
end

function FileManagerHistory:updateItemTable()
    self.hist_menu:swithItemTable(self.hist_menu_title,
                                  require("readhistory").hist)
end

function FileManagerHistory:onSetDimensions(dimen)
    self.dimen = dimen
end

function FileManagerHistory:printFileInformation(book_props)
    if book_props.authors == "" then
        book_props.authors = _("N/A")
    end

    if book_props.title == "" then
        book_props.title = _("N/A")
    end

    if book_props.series == "" then
        book_props.series = _("N/A")
    end

    if book_props.pages == "" then
        book_props.pages = _("N/A")
    end

    if book_props.language == "" then
        book_props.language = _("N/A")
    end

    return {
        { _("Title") .. " : " .. book_props.title, "" },
        { _("Authors") .. " : " .. book_props.authors, "" },
        { _("Series") .. " : " .. book_props.series, "" },
        { _("Pages") .. " : " .. book_props.pages, "" },
        { _("Language") .. " : " .. string.upper(book_props.language), "" },
    }
end

function FileManagerHistory:fileInformation(file)
    local file_mode = lfs.attributes(file, "mode")
    if file_mode == "file" then
        local book_stats = DocSettings:open(file):readSetting('stats')
        if book_stats ~= nil then
            return self:printFileInformation(book_stats)
        else
            return false
        end
    else
        return false
    end  --if file_mode
end

function FileManagerHistory:onMenuHold(item)
    self.histfile_dialog = ButtonDialog:new{
        buttons = {
            {
                {
                    text = util.template(_("Remove \"%1\" from history"),
                                         item.text),
                    callback = function()
                        require("readhistory"):removeItem(item)
                        self._manager:updateItemTable()
                        UIManager:close(self.histfile_dialog)
                    end,
                },
            },
            {
                {
                    text = _("File information"),
                    enabled = FileManagerHistory:fileInformation(item.file) and true or false,
                    callback = function()
                        UIManager:show(KeyValuePage:new{
                            title = _("File information"),
                            kv_pairs = FileManagerHistory:fileInformation(item.file),
                        })
                        --UIManager:close(self.file_dialog)
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
