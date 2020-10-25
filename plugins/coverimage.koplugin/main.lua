local Device = require("device")

if not Device.isAndroid() and not Device.isEmulator() then
    return { disabled = true }
end

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local CoverImage = WidgetContainer:new{
    name = 'coverimage',
    is_doc_only = true,
}

function CoverImage:_enabled()
    return self.enabled
end

function CoverImage:_fallback()
    return self.fallback
end

function CoverImage:init()
    self.cover_image_path = G_reader_settings:readSetting("cover_image_path") or "Cover.png"
    self.cover_image_fallback_path = G_reader_settings:readSetting("cover_image_fallback_path") or "Cover_fallback.png"
    self.enabled = G_reader_settings:isTrue("cover_image_enabled")
    self.fallback = G_reader_settings:isTrue("cover_image_fallback")
    self.ui.menu:registerToMainMenu(self)
end

function CoverImage:cleanUpImage()
    if self.cover_image_fallback_path == "" or not self.fallback then
        os.remove(self.cover_image_path)
    elseif lfs.attributes(self.cover_image_fallback_path, "mode") ~= "file" then
        UIManager:show(InfoMessage:new{
            text = T(_("\"%1\" \nis not a valid image file!\nPlease correct fallback image in Cover-Image"), self.cover_image_fallback_path),
            show_icon = true,
            timeout = 10,
        })
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

function CoverImage:showWrongPath( path )
    UIManager:show(InfoMessage:new{
        text = T(_("Path \"%1\" is not accessible."), path),
        show_icon = true,
    })
end

function CoverImage:addToMainMenu(menu_items)
    menu_items.coverimage = {
        sorting_hint = "document",
        text_func = function()
            return _("Cover Image")
        end,
        checked_func = function()
            return self.enabled or self.fallback
        end,
        sub_item_table = {
            -- menu entry: filename dialog
            {
                text_func = function()
                    return self.cover_image_path and _("Set system screensaver image")
                end,
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
                                            if self.cover_image_path ~= "" or Device.isValidPath
                                                and not Device.isValidPath(self.cover_image_path) then
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
                end
            },
            -- menu entry: enable
            {
                text_func = function()
                    return _("Save current book cover as screensaver image")
                end,
                checked_func = function()
                    return self:_enabled()
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
                end
            },
            -- menu entry: exclude this cover
            {
                text_func = function()
                    return _("Exclude this book cover")
                end,
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
                text_func = function()
                    return self.cover_image_path and _("Set fallback image when no cover or excl. book")
                end,
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
            -- menu entry: fallback
            {
                text_func = function()
                    return _("Use fallback image when leaving book")
                end,
                checked_func = function()
                    return self:_fallback()
                end,
                callback = function()
                    self.fallback = not self.fallback
                    G_reader_settings:saveSetting("cover_image_fallback", self.fallback)
                    self:cleanUpImage()
                    self:onReaderReady(self.ui.doc_settings)
                end,
                separator = true,
            },
        },
    }
end

return CoverImage
