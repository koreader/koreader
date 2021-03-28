-- plugin for saving a cover image to a file and scale it to fit the screen

local Device = require("device")

if not (Device.isAndroid() or Device.isEmulator() or Device.isRemarkable() or Device.isPocketBook()) then
    return { disabled = true }
end

local Blitbuffer = require("ffi/blitbuffer")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local RenderImage = require("ui/renderimage")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local function pathOk(filename)
    local path, name = util.splitFilePathName(filename)
    if not Device:isValidPath(path) then -- isValidPath expects a trailing slash
        return false, T(_("Path \"%1\" isn't in a writable location."), path)
    elseif not util.pathExists(path:gsub("/$", "")) then -- pathExists expects no trailing slash
        return false, T(_("The path \"%1\" doesn't exist."), path)
    elseif name == "" then
        return false, _("Please enter a filename at the end of the path.")
    elseif lfs.attributes(filename, "mode") == "directory" then
        return false, T(_("The path \"%1\" must point to a file, but it points to a folder."), filename)
    end

    return true
end

local function getExtension(filename)
    local _, name = util.splitFilePathName(filename)
    return util.getFileNameSuffix(name):lower()
end

local CoverImage = WidgetContainer:new{
    name = "coverimage",
    is_doc_only = true,
}

function CoverImage:init()
    self.cover_image_path = G_reader_settings:readSetting("cover_image_path") or "cover.jpg"
    self.cover_image_format = G_reader_settings:readSetting("cover_image_format") or "auto"
    self.cover_image_extension = getExtension(self.cover_image_path)
    self.cover_image_quality = G_reader_settings:readSetting("cover_image_quality") or 75
    self.cover_image_stretch_limit = G_reader_settings:readSetting("cover_image_stretch_limit") or 5
    self.cover_image_background = G_reader_settings:readSetting("cover_image_background") or "black"
    self.cover_image_fallback_path = G_reader_settings:readSetting("cover_image_fallback_path") or "cover_fallback.png"
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

function CoverImage:cleanUpImage()
    if self.cover_image_fallback_path == "" or not self.fallback then
        os.remove(self.cover_image_path)
    elseif lfs.attributes(self.cover_image_fallback_path, "mode") ~= "file" then
        UIManager:show(InfoMessage:new{
            text = T(_("\"%1\" \nis not a valid image file!\nA valid fallback image is required in Cover-Image."), self.cover_image_fallback_path),
            show_icon = true,
            timeout = 10,
        })
        os.remove(self.cover_image_path)
    elseif pathOk(self.cover_image_path) then
        ffiutil.copyFile(self.cover_image_fallback_path, self.cover_image_path)
    end
end

function CoverImage:createCoverImage(doc_settings)
    if self.enabled and doc_settings:nilOrFalse("exclude_cover_image") then
        local cover_image = self.ui.document:getCoverPageImage()
        if cover_image then
            local s_w, s_h = Device.screen:getWidth(), Device.screen:getHeight()
            local i_w, i_h = cover_image:getWidth(), cover_image:getHeight()
            local scale_factor = math.min(s_w / i_w, s_h / i_h)

            if self.cover_image_background == "none" or scale_factor == 1 then
                local act_format = self.cover_image_format == "auto" and self.cover_image_extension or self.cover_image_format
                if not cover_image:writeToFile(self.cover_image_path, act_format, self.cover_image_quality) then
                    UIManager:show(InfoMessage:new{
                        text = _("Error writing file") .. "\n" .. self.cover_image_path,
                        show_icon = true,
                    })
                end
                cover_image:free()
                return
            end

            local screen_ratio = s_w / s_h
            local image_ratio = i_w / i_h
            local ratio_divergence_percent = math.abs(100 - image_ratio / screen_ratio * 100)

            logger.dbg("CoverImage: geometries screen=" .. screen_ratio .. ", image=" .. image_ratio .. "; ratio=" .. ratio_divergence_percent)

            local image
            if ratio_divergence_percent < self.cover_image_stretch_limit then -- stretch
                logger.dbg("CoverImage: stretch to fullscreen")
                image = RenderImage:scaleBlitBuffer(cover_image, s_w, s_h)
            else -- scale
                local scaled_w, scaled_h = math.floor(i_w * scale_factor), math.floor(i_h * scale_factor)
                logger.dbg("CoverImage: scale to fullscreen, fill background")

                cover_image = RenderImage:scaleBlitBuffer(cover_image, scaled_w, scaled_h)
                -- new buffer with screen dimensions,
                image = Blitbuffer.new(s_w, s_h, cover_image:getType()) -- new buffer, filled with black
                if self.cover_image_background == "white" then
                    image:fill(Blitbuffer.COLOR_WHITE)
                elseif self.cover_image_background == "gray" then
                    image:fill(Blitbuffer.COLOR_GRAY)
                end
                -- copy scaled image to buffer
                if s_w > scaled_w then -- move right
                    image:blitFrom(cover_image, math.floor((s_w - scaled_w) / 2), 0, 0, 0, scaled_w, scaled_h)
                else -- move down
                    image:blitFrom(cover_image, 0, math.floor((s_h - scaled_h) / 2), 0, 0, scaled_w, scaled_h)
                end
            end

            cover_image:free()

            local act_format = self.cover_image_format == "auto" and self.cover_image_extension or self.cover_image_format
            if not image:writeToFile(self.cover_image_path, act_format, self.cover_image_quality) then
                UIManager:show(InfoMessage:new{
                    text = _("Error writing file") .. "\n" .. self.cover_image_path,
                    show_icon = true,
                    })
            end

            image:free()
            logger.dbg("CoverImage: image written to " .. self.cover_image_path)
        end
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
    self:createCoverImage(doc_settings)
end

local about_text = _([[
This plugin saves the current book cover to a file. That file can be used as a screensaver on certain Android devices, such as Tolinos.

If enabled, the cover image of the actual file is stored in the selected screensaver file. Books can be excluded if desired.

If fallback is activated, the fallback file will be copied to the screensaver file on book closing.
If the filename is empty or the file doesn't exist, the cover file will be deleted and the system screensaver will be used instead.

If the fallback image isn't activated, the screensaver image will stay in place after closing a book.]])

function CoverImage:addToMainMenu(menu_items)
    menu_items.coverimage = {
        sorting_hint = "screen",
        text = _("Cover image"),
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
                text = _("Set image path"),
                checked_func = function()
                    return self.cover_image_path ~= "" and pathOk(self.cover_image_path)
                end,
                help_text = _("The cover of the current book will be stored in this file."),
                keep_menu_open = true,
                callback = function(menu)
                    local InputDialog = require("ui/widget/inputdialog")
                    local sample_input
                    sample_input = InputDialog:new{
                        title = _("Screensaver image filename"),
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
                                            local is_path_ok, is_path_ok_message = pathOk(self.cover_image_path)
                                            if self.cover_image_path ~= "" and is_path_ok then
                                                self:createCoverImage(self.ui.doc_settings) -- with new filename
                                            else
                                                self.enabled = false
                                                UIManager:show(InfoMessage:new{
                                                    text = is_path_ok_message,
                                                    show_icon = true,
                                                })
                                            end
                                        end
                                        self.cover_image_extension = getExtension(self.cover_image_path)
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
                text = _("Save cover image"),
                checked_func = function()
                    return self:_enabled() and pathOk(self.cover_image_path)
                end,
                enabled_func = function()
                    return self.cover_image_path ~= "" and pathOk(self.cover_image_path)
                end,
                callback = function()
                    if self.cover_image_path ~= "" then
                        self.enabled = not self.enabled
                        G_reader_settings:saveSetting("cover_image_enabled", self.enabled)
                        if self.enabled then
                            self:createCoverImage(self.ui.doc_settings)
                        else
                            self:cleanUpImage()
                        end
                    end
                end,
            },
            -- menu entry: scale book cover
            {
                text = _("Size, background and format"),
                enabled_func = function()
                    return self.enabled
                end,
                sub_item_table = {
                    {
                        text_func = function()
                            return T(_("Aspect ratio stretch threshold (%1%)"), self.cover_image_stretch_limit )
                        end,
                        help_text_func = function()
                            return T(_("If the image and the screen have a similar aspect ratio (±%1%), stretch the image instead of keeping its aspect ratio."), self.cover_image_stretch_limit )
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            local old_stretch_limit = self.cover_image_stretch_limit
                            local SpinWidget = require("ui/widget/spinwidget")
                            local size_spinner = SpinWidget:new{
                                width = math.floor(Device.screen:getWidth() * 0.6),
                                value = old_stretch_limit,
                                value_min = 0,
                                value_max = 25,
                                default_value = 5,
                                title_text =  _("Set stretch threshold"),
                                ok_text = _("Set"),
                                callback = function(spin)
                                    if self.enabled and spin.value ~= old_stretch_limit then
                                        self.cover_image_stretch_limit = spin.value
                                        G_reader_settings:saveSetting("cover_image_stretch_limit", self.cover_image_stretch_limit)
                                        self:createCoverImage(self.ui.doc_settings)
                                    end
                                    if touchmenu_instance then touchmenu_instance:updateItems() end
                                end
                            }
                            UIManager:show(size_spinner)
                            if self.enabled and old_stretch_limit ~= self.cover_image_stretch_limit then
                                self:createCoverImage(self.ui.doc_settings)
                            end
                        end,
                    },
                    {
                        text = _("Fit to screen, black background"),
                        checked_func = function()
                            return self.cover_image_background == "black"
                        end,
                        callback = function()
                            local old_background = self.cover_image_background
                            self.cover_image_background = "black"
                            G_reader_settings:saveSetting("cover_image_background", self.cover_image_background)
                            if self.enabled and old_background ~= self.cover_image_background then
                                self:createCoverImage(self.ui.doc_settings)
                            end
                        end,
                    },
                    {
                        text = _("Fit to screen, white background"),
                        checked_func = function()
                            return self.cover_image_background == "white"
                        end,
                        callback = function()
                            local old_background = self.cover_image_background
                            self.cover_image_background = "white"
                            G_reader_settings:saveSetting("cover_image_background", self.cover_image_background)
                            if self.enabled and old_background ~= self.cover_image_background then
                                self:createCoverImage(self.ui.doc_settings)
                            end
                        end,
                    },
                    {
                        text = _("Fit to screen, gray background"),
                        checked_func = function()
                            return self.cover_image_background == "gray"
                        end,
                        callback = function()
                            local old_background = self.cover_image_background
                            self.cover_image_background = "gray"
                            G_reader_settings:saveSetting("cover_image_background", self.cover_image_background)
                            if self.enabled and old_background ~= self.cover_image_background then
                                self:createCoverImage(self.ui.doc_settings)
                            end
                        end,
                    },
                    {
                        text = _("Original image"),
                        checked_func = function()
                            return self.cover_image_background == "none"
                        end,
                        callback = function()
                            local old_background = self.cover_image_background
                            self.cover_image_background = "none"
                            G_reader_settings:saveSetting("cover_image_background", self.cover_image_background)
                            if self.enabled and old_background ~= self.cover_image_background then
                                self:createCoverImage(self.ui.doc_settings)
                            end
                        end,
                        separator = true,
                    },
                    -- menu entries: File format
                    {
                        text = _("File format derived from filename"),
                        help_text = _("If the file format is not supported, then JPG will be used."),
                        checked_func = function()
                            return self.cover_image_format == "auto"
                        end,
                        callback = function()
                            local old_cover_image_format = self.cover_image_format
                            self.cover_image_format = "auto"
                            G_reader_settings:saveSetting("cover_image_format", self.cover_image_format)
                            if self.enabled and old_cover_image_format ~= self.cover_image_format then
                                self:createCoverImage(self.ui.doc_settings)
                            end
                        end,
                    },
                    {
                        text = _("JPG file format"),
                        checked_func = function()
                            return self.cover_image_format == "jpg"
                        end,
                        callback = function()
                            local old_cover_image_format = self.cover_image_format
                            self.cover_image_format = "jpg"
                            G_reader_settings:saveSetting("cover_image_format", self.cover_image_format)
                            if self.enabled and old_cover_image_format ~= self.cover_image_format then
                                self:createCoverImage(self.ui.doc_settings)
                            end
                        end,
                    },
                    {
                        text = _("PNG file format"),
                        checked_func = function()
                            return self.cover_image_format == "png"
                        end,
                        callback = function()
                            local old_cover_image_format = self.cover_image_format
                            self.cover_image_format = "png"
                            G_reader_settings:saveSetting("cover_image_format", self.cover_image_format)
                            if self.enabled and old_cover_image_format ~= self.cover_image_format then
                                self:createCoverImage(self.ui.doc_settings)
                            end
                        end,
                    },
                    {
                        text = _("BMP file format"),
                        checked_func = function()
                            return self.cover_image_format == "bmp"
                        end,
                        callback = function()
                            local old_cover_image_format = self.cover_image_format
                            self.cover_image_format = "bmp"
                            G_reader_settings:saveSetting("cover_image_format", self.cover_image_format)
                            if self.enabled and old_cover_image_format ~= self.cover_image_format then
                                self:createCoverImage(self.ui.doc_settings)
                            end
                        end,
                    },
                }
            },
            -- menu entry: exclude this cover
            {
                text = _("Exclude this book cover"),
                checked_func = function()
                    return self.ui and self.ui.doc_settings and self.ui.doc_settings:isTrue("exclude_cover_image")
                end,
                callback = function()
                    if self.ui.doc_settings:isTrue("exclude_cover_image") then
                        self.ui.doc_settings:makeFalse("exclude_cover_image")
                        self:createCoverImage(self.ui.doc_settings)
                    else
                        self.ui.doc_settings:makeTrue("exclude_cover_image")
                        self:cleanUpImage()
                    end
                    self.ui:saveSettings()
                end,
                separator = true,
            },
            -- menu entry: set fallback image
            {
                text = _("Set fallback image path"),
                checked_func = function()
                    return lfs.attributes(self.cover_image_fallback_path, "mode") == "file"
                end,
                keep_menu_open = true,
                callback = function(menu)
                    local InputDialog = require("ui/widget/inputdialog")
                    local sample_input
                    sample_input = InputDialog:new{
                        title = _("Fallback image filename"),
                        input = self.cover_image_fallback_path,
                        input_type = "string",
                        description = _("Leave this empty to remove the cover when the document is closed."),
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
                                        if lfs.attributes(self.cover_image_fallback_path, "mode") ~= "file"
                                            and self.cover_image_fallback_path ~= "" then
                                            UIManager:show(InfoMessage:new{
                                                text = T(_("\"%1\" \nis not a valid image file!\nA valid fallback image is required in Cover-Image"),
                                                    self.cover_image_fallback_path),
                                                show_icon = true,
                                                timeout = 10,
                                            })
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
                text = _("Turn on fallback image"),
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
