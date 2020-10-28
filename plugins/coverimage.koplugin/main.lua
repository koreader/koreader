local Device = require("device")

if not Device.isAndroid() and not Device.isEmulator() then
    return { disabled = true }
end

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local CoverImage = WidgetContainer:new{
    name = 'coverimage',
    is_doc_only = true,
}

function CoverImage:init()
    self.cover_image_path = G_reader_settings:readSetting("cover_image_path") or "Cover.png"
    self.cover_image_fallback_path = G_reader_settings:readSetting("cover_image_fallback_path") or "Cover_fallback.png"
    self.enabled = G_reader_settings:isTrue("cover_image_enabled")
    self.fallback = G_reader_settings:isTrue("cover_image_fallback")
    self.ui.menu:registerToMainMenu(self)
end

function CoverImage:_enabled()
    return self.enabled
end

function CoverImage:_fallback()
    return self.fallback
end

function CoverImage:dubiousFallbackImage()
    UIManager:show(InfoMessage:new{
        text = T(_("\"%1\" \nis not a valid image file!\nPlease correct fallback image in Cover-Image"), self.cover_image_fallback_path),
        show_icon = true,
        timeout = 10,
    })
end

function CoverImage:showWrongPath( path )
    UIManager:show(InfoMessage:new{
        text = T(_("Path of \"%1\" is not accessible.\nPlease correct it."), path),
        show_icon = true,
    })
end

function CoverImage:cleanUpImage()
    if self.cover_image_fallback_path == "" or not self.fallback then
        os.remove(self.cover_image_path)
    elseif lfs.attributes(self.cover_image_fallback_path, "mode") ~= "file" then
        self:dubiousFallbackImage()
        os.remove(self.cover_image_path)
    else
        os.execute("cp " ..self.cover_image_fallback_path .. " " .. self.cover_image_path)
    end
end

function CoverImage:onCloseDocument()
    logger.dbg("CoverImage: onCloseDocument")
    if self.fallback then
        self:cleanUpImage()
    end
end

function CoverImage:onReaderReady(doc_settings)
   logger.dbg("CoverImage: onReaderReady")
   if self.enabled and not doc_settings:readSetting("exclude_cover_image") == true then
        local image = self.ui.document:getCoverPageImage()
        if image then
            image:writePNG(self.cover_image_path, false)
        end
    end
end

local about_text = _([[
This plugin saves the current book cover to a file, so it can be used as a screensaver, if your android version and firmware supports it (e.g: Tolinos).

If enabled the cover image of the actual file is stored to the selected screensaver file. Certain books can be excluded.

If fallback is activated, the fallback file will be copied to the screensaver file on book closing.
If the filename is empty or the file does not exist, the cover file will be deleted and system screensaver is used.

If fallback is not activated the screensaver image remains after closing a book.]])

function CoverImage:addToMainMenu(menu_items)
    menu_items.coverimage = {
--        sorting_hint = "document",
        sorting_hint = "screen",
        text = _("Cover Image"),
        checked_func = function()
            return self.enabled or self.fallback
        end,
        sub_item_table = {
            -- menu entry: about cover image
            {
                text = _("About cover image"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = about_text,
                    })
                end,
                separator = true,
            },
            -- menu entry: filename dialog
            {
                text = _("Set system screensaver image"),
                checked_func = function()
                    return self.cover_image_path ~= "" and Device:isValidPath(self.cover_image_path)
                end,
                help_text = _("This is the filename, where the cover of the actual book is stored to."),
                keep_menu_open = true,
                callback = function(menu)
                    local InputDialog = require("ui/widget/inputdialog")
                    local sample_input
                    sample_input = InputDialog:new{
                        title = _("Set system screensaver image path"),
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
                                            if self.cover_image_path ~= "" and Device:isValidPath(self.cover_image_path) then
                                                self:onReaderReady(self.ui.doc_settings) -- with new filename
                                            else
                                                self.enabled = false
                                                CoverImage:showWrongPath(self.cover_image_path)
                                            end
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
                end,
            },
            -- menu entry: enable
            {
                text = _("Save current book cover as screensaver image"),
                checked_func = function()
                    return self:_enabled() and Device:isValidPath(self.cover_image_path)
                end,
                enabled_func = function()
                    return self.cover_image_path ~= "" and Device:isValidPath(self.cover_image_path)
                end,
                callback = function()
                    if self.cover_image_path ~= "" then
                        self.enabled = not self.enabled
                        G_reader_settings:saveSetting("cover_image_enabled", self.enabled)
                        if self.enabled then
                            self:onReaderReady(self.ui.doc_settings)
                        else
                            self:cleanUpImage()
                        end
                    end
                end,
            },
            -- menu entry: exclude this cover
            {
                text = _("Exclude this book cover"),
                checked_func = function()
                    return self.ui and self.ui.doc_settings and self.ui.doc_settings:readSetting("exclude_cover_image") == true
                end,
                callback = function()
                    if self.ui.doc_settings:readSetting("exclude_cover_image") == true then
                        self.ui.doc_settings:saveSetting("exclude_cover_image", false)
                        self:onReaderReady(self.ui.doc_settings)
                    else
                        self.ui.doc_settings:saveSetting("exclude_cover_image", true)
                        self:cleanUpImage()
                    end
                    self.ui:saveSettings()
                end,
                separator = true,
            },
            -- menu entry: set fallback image
            {
                text = _("Set fallback image when no cover or excl. book"),
                checked_func = function()
                    return lfs.attributes(self.cover_image_fallback_path, "mode") == "file"
                end,
                help_text =  _("File to use as cover image, when no cover is wanted or book is excluded.\nLeave it blank to use nothing."),
                keep_menu_open = true,
                callback = function(menu)
                    local InputDialog = require("ui/widget/inputdialog")
                    local sample_input
                    sample_input = InputDialog:new{
                        title = _("Filename of fallback image"),
                        input = self.cover_image_fallback_path,
                        input_type = "string",
                        description = _("You can enter the filename of the fallback image here.\n" ..
                            "Leave it empty to clean up on close."),
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
                                        self.cover_image_fallback_path = sample_input:getInputText()
                                        G_reader_settings:saveSetting("cover_image_fallback_path", self.cover_image_fallback_path)
                                        if lfs.attributes(self.cover_image_fallback_path, "mode") ~= "file" then
                                            self:dubiousFallbackImage()
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
                end,
            },
            -- menu entry: fallback
            {
                text = _("Use fallback image when leaving book"),
                checked_func = function()
                    return self:_fallback()
                end,
                callback = function()
                    self.fallback = not self.fallback
                    G_reader_settings:saveSetting("cover_image_fallback", self.fallback)
                end,
                separator = true,
            },
        },
    }
end

return CoverImage
