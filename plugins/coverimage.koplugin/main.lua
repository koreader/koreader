local Device = require("device")

if not Device.isAndroid() and not Device.isEmulator() then
    return { disabled = true }
end

local DocSettings = require("docsettings")
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

-- check if settings of lastfile prohibits creation of cover image
function CoverImage:excluded()
    local lastfile = G_reader_settings:readSetting("lastfile")
    local exclude_ss = false -- consider it not excluded if there's no docsetting
    if DocSettings:hasSidecarFile(lastfile) then
        if self and self.ui then
            exclude_ss = self.ui.doc_settings:readSetting("exclude_cover_image")
        else
            local doc_settings = DocSettings:open(lastfile)
            exclude_ss = doc_settings:readSetting("exclude_cover_image")
        end
    end
    return exclude_ss or false
end

function CoverImage:init()
    self.cover_image_path = G_reader_settings:readSetting("cover_image_path") or "Cover.png"
    self.enabled = G_reader_settings:isTrue("cover_image_enabled")
    self.restore = G_reader_settings:isTrue("cover_image_restore") and self.enabled
    self.ui.menu:registerToMainMenu(self)
end

function CoverImage:onCloseDocument()
    logger.dbg("CoverImage: onCloseDocument")
    local lfs = require("libs/libkoreader-lfs")
    -- Try to restore the state before start of KOReader.
    -- If KOReader gets updated during operation (at least on Android) the backup survives.
    -- Under normal conditions this should not happen.
    if self.restore and not self.excluded() then
        -- Delete image unconditionally, so if no backup exists, there will be no cover file.
        -- This is useful on Tolino to use the system sleep image after KOReader exit.
        if lfs.attributes(self.cover_image_path) then
            os.remove(self.cover_image_path)
        end
        -- Restore backup if it exists, so we can use the last image.
        -- On Tolino a user defined /sdcard/tolino_others.jgp can be used as screensaver on system sleep.
        if lfs.attributes(self.cover_image_path ..".bak") then
            os.rename(self.cover_image_path .. ".bak", self.cover_image_path)
        end
    end
end

function CoverImage:onReaderReady(doc_settings)
   logger.dbg("CoverImage: onReaderReady")
   if self.enabled and self.ui and self.ui.document and not self.excluded() then
        local lfs = require("libs/libkoreader-lfs")
        local image = self.ui.document:getCoverPageImage()
        if image then
            -- Do not override an existing backup, as this only exists on a crash or abnormal update of KOReader.
            -- This is very usefull, if an image shall be used as a system screensaver (e.g. on Tolino as /sdcard/suspend_other.jpg)
            if not lfs.attributes(self.cover_image_path ..".bak") then
                os.rename(self.cover_image_path, self.cover_image_path .. ".bak" )
            end
            image:writePNG(self.cover_image_path, false)
        end
    end
end

function CoverImage:addToMainMenu(menu_items)
    menu_items.coverimage = {
--        sorting_hint = "device", -- maybe this plugin is better situated in device?
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
                                        self.cover_image_path = sample_input:getInputText()
                                        G_reader_settings:saveSetting("cover_image_path", self.cover_image_path)
                                        self.enabled = true
                                        G_reader_settings:saveSetting("cover_image_enabled", true)
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
                    return _("Save cover on book opening")
                end,
                checked_func = function()
                    return self:_enabled()
                end,
                callback = function()
                    self.enabled = not self.enabled
                    G_reader_settings:saveSetting("cover_image_restore", self.enabled)
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
            },
            -- menu entry: exclude this cover
            {
                text_func = function()
                    return _("Exclude this cover image")
                end,
                checked_func = function()
                    return self.ui and self.ui.doc_settings and self.ui.doc_settings:readSetting("exclude_cover_image") == true
                end,
                callback = function()
                    if CoverImage:excluded() then
                        self.ui.doc_settings:saveSetting("exclude_cover_image", false)
                        self.ui:saveSettings() -- save here, because self:onReaderReady needs it
                        self:onReaderReady(self.ui.doc_settings)
                    else
                        self:onCloseDocument() -- do this before self.ui:saveSettings()
                        self.ui.doc_settings:saveSetting("exclude_cover_image", true)
                        self.ui:saveSettings()
                    end
                end,
                added_by_readermenu_flag = true,
            }
        },
    }
end

return CoverImage
