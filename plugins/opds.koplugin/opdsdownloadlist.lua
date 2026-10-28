local BookList = require("ui/widget/booklist")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local N_ = _.ngettext
local T = ffiUtil.template

local OPDSDownloadList = BookList:extend{
    title_bar_left_icon = "appbar.menu",
    opdsbrowser = nil,
}

function OPDSDownloadList:init()
    self.downloads = self.opdsbrowser.downloads
    self.close_callback = function()
        UIManager:close(self)
        self.item_table = nil
        if self.updated then
            self.updated = nil
            self.opdsbrowser._manager.updated = true
            if self.downloads_nb ~= #self.downloads then -- refresh root catalog list
                self.opdsbrowser.item_table[1].mandatory = #self.downloads
                self.opdsbrowser:updateItems(1, true)
            end
        end
    end
    self.onReturn = self.close_callback
    BookList.init(self)
    self.paths = { true } -- enable return arrow
end

function OPDSDownloadList:show()
    self.downloads_nb = #self.downloads
    self:updateItemTable()
    UIManager:show(self)
end

function OPDSDownloadList:updateItemTable(item_table)
    if item_table == nil then
        item_table = {}
        for i, item in ipairs(self.downloads) do
            item_table[i] = {
                text      = item.file:gsub(".*/", ""),
                mandatory = item.catalog,
            }
        end
    end
    local title = T(_("Downloads (%1)"), #item_table)
    self:switchItemTable(title, item_table)
end

function OPDSDownloadList:onMenuSelect(item)
    local dl_item = self.downloads[item.idx]
    local function item_path_func() -- folder without trailing slash, filename
        return ffiUtil.dirname(dl_item.file), item.text
    end
    local function download_buttons_func(close_parent_dialog)
        local function remove_item()
            close_parent_dialog()
            table.remove(self.downloads, item.idx)
            table.remove(self.item_table, item.idx)
            self:updateItemTable(self.item_table)
            self.updated = true
        end
        return {
            {
                {
                    text = _("Remove"),
                    callback = remove_item,
                },
                {
                    text = _("Download"),
                    callback = function()
                        local function file_downloaded_callback(local_path)
                            remove_item()
                            self.opdsbrowser.file_downloaded_callback(local_path)
                        end
                        local function file_read_now_callback(local_path)
                            -- file already exists, don't download and keep it in the download list
                            close_parent_dialog()
                            self.opdsbrowser.file_read_now_callback(local_path)
                        end
                        NetworkMgr:runWhenConnected(function()
                            self.opdsbrowser:checkDownloadFile(dl_item.file, dl_item.url, dl_item.username, dl_item.password,
                                file_downloaded_callback, file_read_now_callback)
                        end)
                    end,
                },
            },
        }
    end
    local function change_folder_func()
        return {
            default_path = self.opdsbrowser._manager.ui.folder_shortcuts:expandPath("%D%"),
            current_path = ffiUtil.dirname(dl_item.file),
            caller_callback = function(path_arg)
                dl_item.file = path_arg .. "/" .. ffiUtil.basename(dl_item.file)
                self.updated = true
            end,
        }
    end
    local function change_filename_func()
        local filename_without_suffix, filetype = filemanagerutil.splitFileNameType(dl_item.file)
        return {
            input = filename_without_suffix,
            caller_callback = function(filename_arg)
                if filename_arg ~= "" and filename_arg ~= filename_without_suffix then
                    item.text = filename_arg .. "." .. filetype
                    dl_item.file = ffiUtil.dirname(dl_item.file) .. "/" .. item.text
                    self:updateItems(1, true)
                    self.updated = true
                    return true
                end
            end,
        }
    end
    self.opdsbrowser:showDownloadDialog(dl_item, item_path_func,
        download_buttons_func, change_folder_func, change_filename_func)
    return true
end

function OPDSDownloadList:onLeftButtonTap()
    local dialog
    dialog = ButtonDialog:new{
        buttons = {
            {{
                    text = _("Download all"),
                    callback = function()
                        UIManager:close(dialog)
                        self:confirmDownloadList()
                    end,
                    align = "left",
            }},
            {{
                    text = _("Remove all"),
                    callback = function()
                        UIManager:close(dialog)
                        self:confirmClearList()
                    end,
                    align = "left",
            }},
        },
        shrink_unneeded_width = true,
        anchor = function()
            return self.title_bar.left_button.image.dimen
        end,
    }
    UIManager:show(dialog)
end

function OPDSDownloadList:confirmDownloadList()
    UIManager:show(ConfirmBox:new{
        text = _("Download all books?\nExisting files will be overwritten."),
        ok_text = _("Download"),
        ok_callback = function()
            NetworkMgr:runWhenConnected(function()
                Trapper:wrap(function()
                    self:downloadList()
                end)
            end)
        end,
    })
end

function OPDSDownloadList:confirmClearList()
    UIManager:show(ConfirmBox:new{
        text = _("Remove all downloads?"),
        ok_text = _("Remove"),
        ok_callback = function()
            for i in ipairs(self.downloads) do -- keep the reference to the table
                self.downloads[i] = nil
            end
            self.updated = true
            self:close_callback()
        end,
    })
end

function OPDSDownloadList:downloadList()
    local info = InfoMessage:new{ text = _("Downloading… (tap to cancel)") }
    UIManager:show(info)
    UIManager:forceRePaint()
    local completed, downloaded = Trapper:dismissableRunInSubprocess(function()
        local dl = {}
        for _, item in ipairs(self.downloads) do
            if self.opdsbrowser:downloadFile(item.file, item.url, item.username, item.password) then
                dl[item.file] = true
            end
        end
        return dl
    end, info)
    if completed then
        UIManager:close(info)
    end
    local dl_count = #self.downloads
    for i = dl_count, 1, -1 do
        local item = self.downloads[i]
        if downloaded and downloaded[item.file] then
            table.remove(self.downloads, i)
        else -- subprocess has been interrupted, check for the downloaded file
            local attr = lfs.attributes(item.file)
            if attr then
                if attr.size > 0 then
                    table.remove(self.downloads, i)
                else -- incomplete download
                    os.remove(item.file)
                end
            end
        end
    end
    dl_count = dl_count - #self.downloads
    if dl_count > 0 then
        self.updated = true
        if #self.downloads == 0 then
            self:close_callback()
        else
            self:updateItemTable()
        end
        UIManager:show(InfoMessage:new{ text = T(N_("1 book downloaded", "%1 books downloaded", dl_count), dl_count) })
    end
end

return OPDSDownloadList
