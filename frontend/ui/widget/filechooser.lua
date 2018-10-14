local Device = require("device")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local OpenWithDialog = require("ui/widget/openwithdialog")
local ConfirmBox = require("ui/widget/confirmbox")
local Font = require("ui/font")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local ffi = require("ffi")
local lfs = require("libs/libkoreader-lfs")
local ffiUtil = require("ffi/util")
local T = ffiUtil.template
local C = ffi.C
local _ = require("gettext")
local Screen = Device.screen
local util = require("util")
local getFileNameSuffix = util.getFileNameSuffix
local getFriendlySize = util.getFriendlySize

ffi.cdef[[
int strcoll (const char *str1, const char *str2);
]]

-- string sort function respecting LC_COLLATE
local function strcoll(str1, str2)
    return C.strcoll(str1, str2) < 0
end

local function kobostrcoll(str1, str2)
    return str1 < str2
end

local FileChooser = Menu:extend{
    cface = Font:getFace("smallinfofont"),
    no_title = true,
    path = lfs.currentdir(),
    show_path = true,
    parent = nil,
    show_hidden = nil,
    exclude_dirs = {"%.sdr$"},
    collate = "strcoll", -- or collate = "access",
    reverse_collate = false,
    path_items = {}, -- store last browsed location(item index) for each path
    perpage = G_reader_settings:readSetting("items_per_page"),
    goto_letter = true,
}

function FileChooser:init()
    self.width = Screen:getWidth()
    -- common dir filter
    self.dir_filter = function(dirname)
        for _, pattern in ipairs(self.exclude_dirs) do
            if dirname:match(pattern) then return false end
        end
        return true
    end
    self.list = function(path, dirs, files)
        -- lfs.dir directory without permission will give error
        local ok, iter, dir_obj = pcall(lfs.dir, path)
        if ok then
            for f in iter, dir_obj do
                if self.show_hidden or not string.match(f, "^%.[^.]") then
                    local filename = path.."/"..f
                    local attributes = lfs.attributes(filename)
                    if attributes ~= nil then
                        if attributes.mode == "directory" and f ~= "." and f~=".." then
                            if self.dir_filter(filename) then
                                table.insert(dirs, {name = f,
                                                    suffix = getFileNameSuffix(f),
                                                    fullpath = filename,
                                                    attr = attributes})
                            end
                        elseif attributes.mode == "file" then
                            if self.file_filter == nil or self.file_filter(filename) then
                                local percent_finished = 0
                                if self.collate == "percent_unopened_first" or self.collate == "percent_unopened_last" then
                                    if DocSettings:hasSidecarFile(filename) then
                                        local docinfo = DocSettings:open(filename)
                                        percent_finished = docinfo.data.percent_finished
                                        if percent_finished == nil then
                                            percent_finished = 0
                                        end
                                    end
                                end
                                table.insert(files, {name = f,
                                                     suffix = getFileNameSuffix(f),
                                                     fullpath = filename,
                                                     attr = attributes,
                                                     percent_finished = percent_finished })
                            end
                        end
                    end
                end
            end
        end
    end

    local strcoll_func = strcoll
    -- circumvent string collating in Kobo devices. See issue koreader/koreader#686
    if Device:isKobo() then
        strcoll_func = kobostrcoll
    end
    self.strcoll = function(a, b)
        if a == nil and b == nil then
            return false
        elseif a == nil then
            return true
        elseif b == nil then
            return false
        elseif DALPHA_SORT_CASE_INSENSITIVE then
            return strcoll_func(string.lower(a), string.lower(b))
        else
            return strcoll_func(a, b)
        end
    end
    self.item_table = self:genItemTableFromPath(self.path)
    Menu.init(self) -- call parent's init()
end

function FileChooser:genItemTableFromPath(path)
    local dirs = {}
    local files = {}
    local up_folder_arrow = "⬆ ../"

    self.list(path, dirs, files)

    local sorting
    if self.collate == "strcoll" then
        sorting = function(a, b)
            return self.strcoll(a.name, b.name)
        end
    elseif self.collate == "access" then
        sorting = function(a, b)
            return a.attr.access > b.attr.access
        end
    elseif self.collate == "modification" then
        sorting = function(a, b)
            return a.attr.modification > b.attr.modification
        end
    elseif self.collate == "change" then
        sorting = function(a, b)
            if DocSettings:hasSidecarFile(a.fullpath) and not DocSettings:hasSidecarFile(b.fullpath) then
                return false
            end
            if not DocSettings:hasSidecarFile(a.fullpath) and DocSettings:hasSidecarFile(b.fullpath) then
                return true
            end
            return a.attr.change > b.attr.change
        end
    elseif self.collate == "size" then
        sorting = function(a, b)
            return a.attr.size < b.attr.size
        end
    elseif self.collate == "type" then
        sorting = function(a, b)
            if a.suffix == nil and b.suffix == nil then
                return self.strcoll(a.name, b.name)
            else
                return self.strcoll(a.suffix, b.suffix)
            end
        end
    elseif self.collate == "percent_unopened_first" or self.collate == "percent_unopened_last" then
        sorting = function(a, b)
            if DocSettings:hasSidecarFile(a.fullpath) and not DocSettings:hasSidecarFile(b.fullpath) then
                if self.collate == "percent_unopened_first" then
                    return false
                else
                    return true
                end
            end
            if not DocSettings:hasSidecarFile(a.fullpath) and DocSettings:hasSidecarFile(b.fullpath) then
                if self.collate == "percent_unopened_first" then
                    return true
                else
                    return false
                end
            end
            if not DocSettings:hasSidecarFile(a.fullpath) and not DocSettings:hasSidecarFile(b.fullpath) then
                return a.name < b.name
            end

            if a.attr.mode == "directory" then return a.name < b.name end
            if b.attr.mode == "directory" then return a.name < b.name end

            return a.percent_finished < b.percent_finished
        end
    else
        sorting = function(a, b)
            return a.name < b.name
        end
    end

    if self.reverse_collate then
        local sorting_unreversed = sorting
        sorting = function(a, b) return sorting_unreversed(b, a) end
    end

    if self.collate ~= "strcoll_mixed" then
        table.sort(dirs, sorting)
        table.sort(files, sorting)
    end
    if path ~= "/" then table.insert(dirs, 1, {name = ".."}) end
    if self.show_current_dir_for_hold then table.insert(dirs, 1, {name = "."}) end

    local item_table = {}
    for i, dir in ipairs(dirs) do
        -- count sume of directories and files inside dir
        local sub_dirs = {}
        local dir_files = {}
        local subdir_path = self.path.."/"..dir.name
        self.list(subdir_path, sub_dirs, dir_files)
        local num_items = #sub_dirs + #dir_files
        local istr
        if num_items == 1 then
            istr = _("1 item")
        else
            istr = ffiUtil.template(_("%1 items"), num_items)
        end
        local text
        if dir.name == ".." then
            text = up_folder_arrow
        elseif dir.name == "." then -- possible with show_current_dir_for_hold
            text = _("Long-press to select current directory")
        else
            text = dir.name.."/"
        end
        table.insert(item_table, {
            text = text,
            mandatory = istr,
            path = subdir_path,
            is_go_up = dir.name == ".."
        })
    end

    -- set to false to show all files in regular font
    -- set to "opened" to show opened files in bold
    -- otherwise, show new files in bold
    local show_file_in_bold = G_reader_settings:readSetting("show_file_in_bold")

    for _, file in ipairs(files) do
        local full_path = self.path.."/"..file.name
        local file_size = lfs.attributes(full_path, "size") or 0
        local sstr = getFriendlySize(file_size)
        local file_item = {
            text = file.name,
            mandatory = sstr,
            path = full_path
        }
        if show_file_in_bold ~= false then
            file_item.bold = DocSettings:hasSidecarFile(full_path)
            if show_file_in_bold ~= "opened" then
                file_item.bold = not file_item.bold
            end
        end
        table.insert(item_table, file_item)
    end

    if self.collate == "strcoll_mixed" then
        sorting = function(a, b)
            if b.text == up_folder_arrow then return false end
            return self.strcoll(a.text, b.text)
        end
        if self.reverse_collate then
            local sorting_unreversed = sorting
            sorting = function(a, b) return sorting_unreversed(b, a) end
        end
        table.sort(item_table, sorting)
    end
    -- lfs.dir iterated node string may be encoded with some weird codepage on
    -- Windows we need to encode them to utf-8
    if ffi.os == "Windows" then
        for k, v in pairs(item_table) do
            if v.text then
                v.text = ffiUtil.multiByteToUTF8(v.text) or ""
            end
        end
    end

    return item_table
end

function FileChooser:updateItems(select_number)
    Menu.updateItems(self, select_number) -- call parent's updateItems()
    self.path_items[self.path] = (self.page - 1) * self.perpage + (select_number or 1)
end

function FileChooser:refreshPath()
    local itemmatch = nil

    local _, folder_name = util.splitFilePathName(self.path)
    Screen:setWindowTitle(folder_name)

    if self.focused_path then
        itemmatch = {path = self.focused_path}
        -- We use focused_path only once, but remember it
        -- for CoverBrower to re-apply it on startup if needed
        self.prev_focused_path = self.focused_path
        self.focused_path = nil
    end

    self:switchItemTable(nil, self:genItemTableFromPath(self.path), self.path_items[self.path], itemmatch)
end

function FileChooser:changeToPath(path, focused_path)
    path = ffiUtil.realpath(path)
    self.path = path

    if focused_path then
        self.focused_path = focused_path
    end

    self:refreshPath()
    self:onPathChanged(path)
end

function FileChooser:changePageToPath(path)
    if not path then return end
    for num, item in ipairs(self.item_table) do
        if item.path == path then
            local page = math.floor((num-1) / self.perpage) + 1
            if page ~= self.page then
                self:onGotoPage(page)
            end
            break
        end
    end
end

function FileChooser:toggleHiddenFiles()
    self.show_hidden = not self.show_hidden
    self:refreshPath()
end

function FileChooser:setCollate(collate)
    self.collate = collate
    self:refreshPath()
end

function FileChooser:toggleReverseCollate()
    self.reverse_collate = not self.reverse_collate
    self:refreshPath()
end

function FileChooser:onMenuSelect(item)
    -- parent directory of dir without permission get nil mode
    -- we need to change to parent path in this case
    if lfs.attributes(item.path, "mode") == "file" then
        self:onFileSelect(item.path)
    else
        self:changeToPath(item.path, item.is_go_up and self.path)
    end
    return true
end

function FileChooser:onMenuHold(item)
    self:onFileHold(item.path)
    return true
end

function FileChooser:onFileSelect(file)
    UIManager:close(self)
    return true
end

function FileChooser:onFileHold(file)
    return true
end

function FileChooser:onPathChanged(path)
    return true
end

function FileChooser:getNextFile(curr_file)
    local next_file
    for index, data in pairs(self.item_table) do
        if data.path == curr_file then
            if index+1 <= #self.item_table then
                next_file = self.item_table[index+1].path
                if lfs.attributes(next_file, "mode") == "file" and DocumentRegistry:hasProvider(next_file) then
                    break
                else
                    next_file = nil
                end
            end
        end
    end
    return next_file
end

function FileChooser:showSetProviderButtons(file, filemanager_instance, reader_ui)
    local __, filename_pure = util.splitFilePathName(file)
    local filename_suffix = util.getFileNameSuffix(file)

    local buttons = {}
    local radio_buttons = {}
    local providers = DocumentRegistry:getProviders(file)

    for ___, provider in ipairs(providers) do
        -- we have no need for extension, mimetype, weights, etc. here
        provider = provider.provider
        table.insert(radio_buttons, {
            {
                text = provider.provider_name,
                checked = DocumentRegistry:getProvider(file) == provider,
                provider = provider,
            },
        })
    end

    table.insert(buttons, {
        {
            text = _("Cancel"),
            callback = function()
                UIManager:close(self.set_provider_dialog)
            end,
        },
        {
            text = _("Open"),
            is_enter_default = true,
            callback = function()
                local provider = self.set_provider_dialog.radio_button_table.checked_button.provider

                -- always for this file
                if self.set_provider_dialog._check_file_button.checked then
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Always open '%2' with %1?"),
                                   provider.provider_name, filename_pure),
                        ok_text = _("Always"),
                        ok_callback = function()
                            DocumentRegistry:setProvider(file, provider, false)

                            filemanager_instance:onClose()
                            reader_ui:showReader(file, provider)
                            UIManager:close(self.set_provider_dialog)
                        end,
                    })
                -- always for all files of this file type
                elseif self.set_provider_dialog._check_global_button.checked then
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Always open %2 files with %1?"),
                                 provider.provider_name, filename_suffix),
                        ok_text = _("Always"),
                        ok_callback = function()
                            DocumentRegistry:setProvider(file, provider, true)

                            filemanager_instance:onClose()
                            reader_ui:showReader(file, provider)
                            UIManager:close(self.set_provider_dialog)
                        end,
                    })
                else
                    -- just once
                    filemanager_instance:onClose()
                    reader_ui:showReader(file, provider)
                    UIManager:close(self.set_provider_dialog)
                end
            end,
        },
    })

    self.set_provider_dialog = OpenWithDialog:new{
        title = T(_("Open %1 with:"), filename_pure),
        radio_buttons = radio_buttons,
        buttons = buttons,
    }
    UIManager:show(self.set_provider_dialog)
end

return FileChooser
