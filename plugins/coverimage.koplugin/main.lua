local Device = require("device")

if not Device.isAndroid() and not Device.isEmulator() then
    return { disabled = true }
end

local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local CoverImage = WidgetContainer:new{
    name = 'coverimage',
    is_doc_only = true,
    settings_id = 0,
}

function CoverImage:_enabled()
    return self.enabled
end

function CoverImage:_restore()
    return self.enabled and self.restore
end

function CoverImage:init()
    self.cover_image_path = G_reader_settings:readSetting("cover_image_path") or "Cover.png"
    self.enabled = G_reader_settings:isTrue("cover_image_enabled")
    self.restore = G_reader_settings:isTrue("cover_image_restore") and self.enabled
    self.ui.menu:registerToMainMenu(self)
end

function CoverImage:cleanUpImage()
    if not self.ui.doc_settings:readSetting("exclude_cover_image") == true then
        local lfs = require("libs/libkoreader-lfs")
        -- Delete image the backup (if it exits) will contain a user defined sleep image
        if lfs.attributes(self.cover_image_path) then
            os.remove(self.cover_image_path)
        end
        -- On Tolino a user defined /sdcard/suspend_others.jgp can be used as screensaver on system sleep.
        -- Restore backup if it exists, so we can use it as sleep image
        -- If no backup exists, there is no file and the native sleep image is used
        local bak_file_name = self.cover_image_path .. ".bak"
        if lfs.attributes(bak_file_name) then
            os.rename(bak_file_name, self.cover_image_path)
        end
    end
end

function CoverImage:onCloseDocument()
    logger.dbg("CoverImage: onCloseDocument")
    -- Try to restore the state before opening of a document.
    if self.restore then
        self:cleanUpImage()
    end
end

function CoverImage:onReaderReady(doc_settings)
   logger.dbg("CoverImage: onReaderReady")
   if self.enabled and not doc_settings:readSetting("exclude_cover_image") == true then
        local lfs = require("libs/libkoreader-lfs")
        local image = self.ui.document:getCoverPageImage()
        if image then
            -- Do not override an existing backup, as this only exists on a crash or abnormal update of KOReader.
            -- This is very usefull, if an image shall be used as a system screensaver (e.g. on Tolino as /sdcard/suspend_other.jpg)
            if not lfs.attributes(self.cover_image_path .. ".bak") then
                os.rename(self.cover_image_path, self.cover_image_path .. ".bak" )
            end
            image:writePNG(self.cover_image_path, false)
        end
    end
end

function CoverImage:addToMainMenu(menu_items)
    menu_items.coverimage = {
        sorting_hint = "document",
        text_func = function()
            return _("Cover Image")
        end,
        checked_func = function()
            return self:_enabled()
        end,
        sub_item_table = {
            -- menu entry: filename dialog
            {
                text_func = function()
                    return self.cover_image_path and T(_("Cover Image (%1)"), self.cover_image_path)
                        or _("Cover Image (none)")
                end,
                keep_menu_open = true,
                callback = function(menu)
                    local InputDialog = require("ui/widget/inputdialog")
                    local sample_input
                    sample_input = InputDialog:new{
                        title = _("Filename for Cover-Image"),
                        input = self.cover_image_path,
                        input_type = "string",
                        description = _("You can enter the filename of the cover image here."),
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    callback = function()
                                        UIManager:close(sample_input)
                                    end,
                                },
                                {
                                    text = _("Save"),
                                    is_enter_default = true,
                                    callback = function()
                                        local new_cover_image_path = sample_input:getInputText()
                                        if new_cover_image_path ~= self.cover_image_path then
                                            self:cleanUpImage() -- with old filename
                                            self.cover_image_path = new_cover_image_path -- update filename
                                            G_reader_settings:saveSetting("cover_image_path", self.cover_image_path)
                                            self:onReaderReady(self.ui.doc_settings) -- with new filename
                                        end
                                        UIManager:close(sample_input)
                                        menu:updateItems()
                                    end,
                                },
                            }
                        },
                    }
                    UIManager:show(sample_input)
                    sample_input:onShowKeyboard()
                end
            },
            -- menu entry: enable
            {
                text_func = function()
                    return _("Save book cover")
                end,
                checked_func = function()
                    return self:_enabled()
                end,
                callback = function()
                    self.enabled = not self.enabled
                    G_reader_settings:saveSetting("cover_image_enabled", self.enabled)
                    if self.enabled then
                        self.restore = true
                        self:onReaderReady(self.ui.doc_settings)
                    else
                        self.restore = false
                        self:cleanUpImage()
                    end
                    G_reader_settings:saveSetting("cover_image_restore", self.restore)
                end,
            },
            -- menu entry: restore
            {
                text_func = function()
                    return _("Restore image on book closing")
                end,
                checked_func = function()
                    return self:_restore()
                end,
                callback = function()
                    self.restore = not self.restore and self.enabled
                    G_reader_settings:saveSetting("cover_image_restore", self.restore)
                end,
                separator = true,
            },
            -- menu entry: exclude this cover
            {
                text_func = function()
                    return _("Exclude cover image of this document")
                end,
                checked_func = function()
                    return self.ui and self.ui.doc_settings and self.ui.doc_settings:readSetting("exclude_cover_image") == true
                end,
                callback = function()
                    if self.ui.doc_settings:readSetting("exclude_cover_image") == true then
                        self.ui.doc_settings:saveSetting("exclude_cover_image", false)
                        self:onReaderReady(self.ui.doc_settings)
                    else
                        if self.enabled then
                            self:cleanUpImage()
                        end
                        self.ui.doc_settings:saveSetting("exclude_cover_image", true)
                    end
                    self.ui:saveSettings()
                end,
            }
        },
    }
end

return CoverImage
