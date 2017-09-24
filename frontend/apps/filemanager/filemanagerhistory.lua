local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local DocSettings = require("docsettings")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local InputContainer = require("ui/widget/container/inputcontainer")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local util = require("ffi/util")
local _ = require("gettext")

local FileManagerHistory = InputContainer:extend{
    hist_menu_title = _("History"),
}

function FileManagerHistory:init()
    self.ui.menu:registerToMainMenu(self)
end

function FileManagerHistory:addToMainMenu(menu_items)
    -- insert table to main tab of filemanager menu
    menu_items.history = {
        text = self.hist_menu_title,
        callback = function()
            self:onShowHist()
        end,
    }
end

function FileManagerHistory:updateItemTable()
    -- try to stay on current page
    local select_number = nil
    if self.hist_menu.page and self.hist_menu.perpage then
        select_number = (self.hist_menu.page - 1) * self.hist_menu.perpage + 1
    end
    self.hist_menu:switchItemTable(self.hist_menu_title,
                                  require("readhistory").hist, select_number)
end

function FileManagerHistory:onSetDimensions(dimen)
    self.dimen = dimen
end

function FileManagerHistory:onMenuHold(item)
    self.histfile_dialog = nil
    local buttons = {
        {
            {
                text = _("Purge .sdr"),
                enabled = DocSettings:hasSidecarFile(util.realpath(item.file)),
                callback = function()
                    local ConfirmBox = require("ui/widget/confirmbox")
                    UIManager:show(ConfirmBox:new{
                        text = util.template(_("Purge .sdr to reset settings for this document?\n\n%1"), item.text),
                        ok_text = _("Purge"),
                        ok_callback = function()
                            filemanagerutil.purgeSettings(item.file)
                            filemanagerutil.removeFileFromHistoryIfWanted(item.file)
                            self._manager:updateItemTable()
                            UIManager:close(self.histfile_dialog)
                        end,
                    })
                end,
            },
            {
                text = _("Remove from history"),
                callback = function()
                    require("readhistory"):removeItem(item)
                    self._manager:updateItemTable()
                    UIManager:close(self.histfile_dialog)
                end,
            },
        },
        {
            {
                text = _("Delete"),
                enabled = lfs.attributes(item.file, "mode") and true or false,
                callback = function()
                    local ConfirmBox = require("ui/widget/confirmbox")
                    UIManager:show(ConfirmBox:new{
                        text = _("Are you sure that you want to delete this file?\n") .. item.file .. ("\n") .. _("If you delete a file, it is permanently lost."),
                        ok_text = _("Delete"),
                        ok_callback = function()
                            local FileManager = require("apps/filemanager/filemanager")
                            FileManager:deleteFile(item.file)
                            filemanagerutil.removeFileFromHistoryIfWanted(item.file)
                            require("readhistory"):setDeleted(item)
                            self._manager:updateItemTable()
                            UIManager:close(self.histfile_dialog)
                        end,
                    })
                end,
            },
            {
                text = _("Book information"),
                enabled = FileManagerBookInfo:isSupported(item.file),
                callback = function()
                    FileManagerBookInfo:show(item.file)
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
    }
    self.histfile_dialog = ButtonDialogTitle:new{
        title = item.text:match("([^/]+)$"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.histfile_dialog)
    return true
end

function FileManagerHistory:onShowHist()
    self.hist_menu = Menu:new{
        ui = self.ui,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        is_borderless = true,
        is_popout = false,
        onMenuHold = self.onMenuHold,
        _manager = self,
    }
    self:updateItemTable()
    self.hist_menu.close_callback = function()
        -- Close it at next tick so it stays displayed
        -- while a book is opening (avoids a transient
        -- display of the underlying File Browser)
        UIManager:nextTick(function()
            UIManager:close(self.hist_menu)
        end)
    end
    UIManager:show(self.hist_menu)
    return true
end

return FileManagerHistory
