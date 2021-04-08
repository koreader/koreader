-- plugin for saving a cover image to a file and scale it to fit the screen

local Device = require("device")

if not (Device.isAndroid() or Device.isEmulator() or Device.isRemarkable() or Device.isPocketBook()) then
    return { disabled = true }
end

local ConfirmBox = require("ui/widget/confirmbox")
local Blitbuffer = require("ffi/blitbuffer")
local InfoMessage = require("ui/widget/infomessage")
local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local RenderImage = require("ui/renderimage")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local PathChooser = require("ui/widget/pathchooser")
local Screen = require("device").screen
local InputDialog = require("ui/widget/inputdialog")

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
    self.cover_image_path = G_reader_settings:readSetting("cover_image_path") or ""
    self.cover_image_format = G_reader_settings:readSetting("cover_image_format") or "auto"
    self.cover_image_quality = G_reader_settings:readSetting("cover_image_quality") or 75
    self.cover_image_stretch_limit = G_reader_settings:readSetting("cover_image_stretch_limit") or 8
    self.cover_image_background = G_reader_settings:readSetting("cover_image_background") or "black"
    self.cover_image_fallback_path = G_reader_settings:readSetting("cover_image_fallback_path") or ""
    self.cover_image_cache_path = G_reader_settings:readSetting("cover_image_cache_path") or DataStorage:getDataDir() .. "/cache/"
    self.cover_image_cache_maxfiles = G_reader_settings:readSetting("cover_image_cache_maxfiles") or 36
    self.cover_image_cache_maxsize = G_reader_settings:readSetting("cover_image_cache_maxsize") or 5 -- MiB
    self.cover_image_cache_prefix = "CI_CACHE_"
    self.enabled = G_reader_settings:isTrue("cover_image_enabled")
    self.fallback = G_reader_settings:isTrue("cover_image_fallback")
    self.ui.menu:registerToMainMenu(self)
end

function CoverImage:cleanUpImage()
    if self.cover_image_fallback_path == "" or not self.fallback then
        os.remove(self.cover_image_path)
    elseif lfs.attributes(self.cover_image_fallback_path, "mode") ~= "file" then
        UIManager:show(InfoMessage:new{
            text = T(_("\"%1\"\nis not a valid image file!\nA valid fallback image is required in Cover-Image."), self.cover_image_fallback_path),
            show_icon = true,
            timeout = 10,
        })
        os.remove(self.cover_image_path)
    elseif pathOk(self.cover_image_path) then
        ffiutil.copyFile(self.cover_image_fallback_path, self.cover_image_path)
    end
end

function CoverImage:getCacheFile()
    local cache_file = self.cover_image_cache_path .. self.cover_image_cache_prefix .. self.ui.document:getProps().title
        .. "_" .. self.cover_image_quality .. "_" .. self.cover_image_stretch_limit .. "_" .. self.cover_image_background

    local act_format = self.cover_image_format
    if act_format == "auto" then
        cache_file = cache_file .. ".jpg"
    else
        cache_file = cache_file .. "." .. act_format
    end
    return cache_file
end

function CoverImage:createCoverImage(doc_settings)
    if self.enabled and doc_settings:nilOrFalse("exclude_cover_image") then
        local cover_image = self.ui.document:getCoverPageImage()
        if cover_image then
            local cache_file = self:getCacheFile()
            if lfs.attributes(cache_file, "mode") == "file" then
                ffiutil.copyFile(cache_file, self.cover_image_path)
                lfs.touch(cache_file) -- update date
                return
            end

            local s_w, s_h = Device.screen:getWidth(), Device.screen:getHeight()
            local i_w, i_h = cover_image:getWidth(), cover_image:getHeight()
            local scale_factor = math.min(s_w / i_w, s_h / i_h)

            if self.cover_image_background == "none" or scale_factor == 1 then
                local act_format = self.cover_image_format == "auto" and "jpg" or self.cover_image_format
                if not cover_image:writeToFile(self.cover_image_path, act_format, self.cover_image_quality) then
                    UIManager:show(InfoMessage:new{
                        text = _("Error writing file") .. "\n" .. self.cover_image_path,
                        show_icon = true,
                    })
                end
                cover_image:free()
                ffiutil.copyFile(self.cover_image_path, cache_file)
                self:cleanCache()
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

            local act_format = self.cover_image_format == "auto" and "jpg" or self.cover_image_format
            if not image:writeToFile(self.cover_image_path, act_format, self.cover_image_quality) then
                UIManager:show(InfoMessage:new{
                    text = _("Error writing file") .. "\n" .. self.cover_image_path,
                    show_icon = true,
                    })
            end

            image:free()
            logger.dbg("CoverImage: image written to " .. self.cover_image_path)

            ffiutil.copyFile(self.cover_image_path, cache_file)
            self:cleanCache()
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

---------------------------
-- cache handling functions
---------------------------

function CoverImage:emptyCache()
    for entry in lfs.dir(self.cover_image_cache_path) do
        if entry ~= "." and entry ~= ".." then
            local file = self.cover_image_cache_path .. entry
            if entry:sub(1,self.cover_image_cache_prefix:len()) == self.cover_image_cache_prefix
                and lfs.attributes(file, "mode") == "file" then
                    os.remove(file)
            end
        end
    end
end

function CoverImage:getCacheFiles(cache_path, cache_prefix)
    local cache_count = 0
    local cache_size_KiB = 0
    local files = {}
    for entry in lfs.dir(self.cover_image_cache_path) do
        if entry ~= "." and entry ~= ".." then
            local file = cache_path .. entry
            if entry:sub(1,self.cover_image_cache_prefix:len()) == cache_prefix
                and lfs.attributes(file, "mode") == "file" then
                cache_count = cache_count + 1
                files[cache_count] = {
                    name = file,
                    size = math.floor((lfs.attributes(file).size + 1023) / 1024), -- round up to KiB
                    mod = lfs.attributes(file).modification,
                }
                cache_size_KiB = cache_size_KiB + files[cache_count].size -- size in KiB
            end
        end
    end
    logger.dbg("CoverImage: start - cache size: "..cache_size_KiB .. " KiB, cached files: " .. cache_count)
    return cache_count, cache_size_KiB, files
end

function CoverImage:cleanCache()
    if not self:isCacheEnabled() then
        self:emptyCache()
        return
    end

    local cache_count, cache_size_KiB, files = self:getCacheFiles(self.cover_image_cache_path, self.cover_image_cache_prefix)

    -- delete the oldest files first
    table.sort(files, function(a, b) return a.mod < b.mod end)
    local index = 1
    while (cache_count > self.cover_image_cache_maxfiles and self.cover_image_cache_maxfiles ~= 0)
        or (cache_size_KiB > self.cover_image_cache_maxsize * 1024 and self.cover_image_cache_maxsize ~= 0)
        and index <= #files do
        os.remove(files[index].name)
        cache_count = cache_count - 1
        cache_size_KiB = cache_size_KiB - files[index].size
        index = index + 1
    end
    logger.dbg("CoverImage: clean - cache size: "..cache_size_KiB .. " KiB, cached files: " .. cache_count)
end

function CoverImage:isCacheEnabled()
    return self.cover_image_cache_maxfiles >= 0 and self.cover_image_cache_maxsize >= 0
        and lfs.attributes(self.cover_image_cache_path, "mode") == "directory"
end

-- callback for choosePathFile()
function CoverImage:migrateCache(old_path, new_path)
    if old_path == new_path then
        return
    end
    for entry in lfs.dir(old_path) do
        if entry ~= "." and entry ~= ".."   then
            local old_file = old_path .. entry
            if lfs.attributes(old_file, "mode") == "file" and entry:sub(1,self.cover_image_cache_prefix:len()) == self.cover_image_cache_prefix then
                local old_access_time = lfs.attributes(old_file, "access")
                local new_file = new_path .. entry
                os.rename(old_file, new_file)
                lfs.touch(new_file, old_access_time) -- restore original time
            end
        end
    end
end

-- callback for choosePathFile()
function CoverImage:migrateCover(old_file, new_file)
    if old_file ~= new_file then
        os.rename(old_file, new_file)
    end
end

--[[--
chooses a path or (an existing) file

@touchmenu_instance for updating of the menu
@string setting is the G_reader_setting which is used and changed
@boolean folder_only just selects a path, no file handling
@boolean new_file allows to enter a new filename, or use just an existing file
@function migrate(a,b) callback to a function to mangle old folder/file with new folder/file.
    Can used for migrating the contents of the old path to the new one
]]
function CoverImage:choosePathFile(touchmenu_instance, setting, folder_only, new_file, migrate)
    local old_path, old_name = util.splitFilePathName(self[setting]) -- luacheck: no unused
    UIManager:show(PathChooser:new{
        select_directory = true,
        select_file = not folder_only,
        height = Screen:getHeight(),
        path = old_path,
        onConfirm = function(dir_path)
            local mode = lfs.attributes(dir_path, "mode")
            if folder_only then -- just select a folder
                if not dir_path:find("/$") then
                    dir_path = dir_path .. "/"
                end
                if migrate then
                    migrate(self, self[setting], dir_path)
                end
                self[setting] = dir_path
                G_reader_settings:saveSetting(setting, dir_path)
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
            elseif new_file and mode == "directory" then -- new filename should be entered or a file could be selected
                local file_input
                file_input = InputDialog:new{
                    title =  _("Append filename"),
                    input = dir_path .. "/",
                    buttons = {{
                        {
                            text = _("Cancel"),
                        },
                        {
                            text = _("Save"),
                            callback = function()
                                local file = file_input:getInputText()
                                if migrate and self[setting] and self[setting] ~= "" then
                                    migrate(self, self[setting], file)
                                end
                                self[setting] = file
                                G_reader_settings:saveSetting(setting, file)
                                if touchmenu_instance then
                                    touchmenu_instance:updateItems()
                                end
                                UIManager:close(file_input)
                            end,
                        },
                    }},
                }
                UIManager:show(file_input)
                file_input:onShowKeyboard()
            elseif mode == "file" then   -- just select an existing file
                if migrate then
                    migrate(self, self[setting], dir_path)
                end
                self[setting] = dir_path
                G_reader_settings:saveSetting(setting, dir_path)
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
            end
        end,
    })
end

--[[--
changes a G_reader_setting with a size spinner

@touchmenu_instance used for updating the menu
@string setting is the G_reader_setting which is used and changed
@string title shown in the spinner
@int min minimum value of the spinner
@int max maximum value of the spinner
@int default default value of the spinner
@function callback to call, when spinner changed the value
]]
function CoverImage:sizeSpinner(touchmenu_instance, setting, title, min, max, default, callback)
    local SpinWidget = require("ui/widget/spinwidget")
    local old_val = self[setting]
    UIManager:show(SpinWidget:new{
        width = math.floor(Device.screen:getWidth() * 0.6),
        value = old_val,
        value_min = min,
        value_max = max,
        default_value = default,
        title_text = title,
        ok_text = _("Set"),
        callback = function(spin)
            if self.enabled and spin.value ~= old_val then
                self[setting] = spin.value
                G_reader_settings:saveSetting(setting, self[setting])
                if callback then
                    callback(self)
                end
            end
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end
    })
end

-------------- menus and longer texts -----------

local about_text = _([[
This plugin saves the current book cover to a file. That file can be used as a screensaver on certain Android devices, such as Tolinos.

If enabled, the cover image of the actual file is stored in the selected screensaver file. Books can be excluded if desired.

If fallback is activated, the fallback file will be copied to the screensaver file on book closing.
If the filename is empty or the file doesn't exist, the cover file will be deleted and the system screensaver will be used instead.

If the fallback image isn't activated, the screensaver image will stay in place after closing a book.]])

local set_image_text = _([[The cover of the current book or the fallback image will be stored in this file.

You can either choose an existing file:
- Select a file

or specify a new file:
- First select a directory
- Then add the name of the new file]])

-- menu entry: Cache settings
function CoverImage:menu_entry_cache()
    return {
        text = _("Cache settings"),
        checked_func = function()
            return self:isCacheEnabled()
        end,
        sub_item_table = {
            {
                text_func = function()
                    local number
                    if self.cover_image_cache_maxfiles > 0 then
                        number = self.cover_image_cache_maxfiles
                    elseif self.cover_image_cache_maxfiles == 0 then
                        number = _("unlimited")
                    else
                        number = _("off")
                    end
                    return T(_("Maximum number of cached covers (%1)"), number)
                end,
                help_text = _("If set to zero the number of cache files is unlimited.\nIf set to -1 the cache is disabled."),
                checked_func = function()
                    return self.cover_image_cache_maxfiles >= 0
                end,
                callback = function(touchmenu_instance)
                    self:sizeSpinner(touchmenu_instance, "cover_image_cache_maxfiles", _("Number of covers"), -1, 100, 36, self.cleanCache)
                end,
            },
            {
                text_func = function()
                    local number
                    if self.cover_image_cache_maxsize > 0 then
                        number = self.cover_image_cache_maxsize
                    elseif self.cover_image_cache_maxsize == 0 then
                        number = _("unlimited")
                    else
                        number = _("off")
                    end
                    return T(_("Maximum size of cached covers (%1MiB)"), number)
                end,
                help_text = _("If set to zero the cache size is unlimited.\nIf set to -1 the cache is disabled."),
                checked_func = function()
                    return self.cover_image_cache_maxsize >= 0
                end,
                callback = function(touchmenu_instance)
                    self:sizeSpinner(touchmenu_instance, "cover_image_cache_maxsize", _("Cache size"), -1, 100, 5, self.cleanCache)
                end,
            },
            {
            text = _("Cover cache folder"),
            checked_func = function()
                return lfs.attributes(self.cover_image_cache_path, "mode") == "directory"
            end,
            help_text_func = function()
                return T(_("The actual cache path is:\n%1"), self.cover_image_cache_path)
            end,
            callback = function(touchmenu_instance)
                UIManager:show(ConfirmBox:new{
                    text = _("Select a cache folder. The contents of the old folder will be migrated."),
                    ok_text = _("Yes"),
                    cancel_text = _("No"),
                    ok_callback = function()
                        self:choosePathFile(touchmenu_instance, "cover_image_cache_path", true, false, self.migrateCache)
                    end,
                })
            end,
            },
            {
                text = _("Clear cached covers"),
                callback = function()
                    local cache_count, cache_size_KiB
                        = self:getCacheFiles(self.cover_image_cache_path, self.cover_image_cache_prefix)
                    UIManager:show(ConfirmBox:new{
                        text =  T(_("Do you really want to clear the cover image cache?\nThe cache contains %1 files and uses %2 MiB."),
                            cache_count, math.floor((cache_size_KiB + 1023) / 1024)),
                        ok_text = _("Clear"),
                        ok_callback = function()
                            self:emptyCache()
                        end,
                    })
                end,
                keep_menu_open = true,
            },
        },
    }
end

function CoverImage:menu_entry_format(title, format)
    return {
        text = title,
        checked_func = function()
            return self.cover_image_format == format
        end,
        callback = function()
            local old_cover_image_format = self.cover_image_format
            self.cover_image_format = format
            G_reader_settings:saveSetting("cover_image_format", format)
            if self.enabled and old_cover_image_format ~= format then
                self:createCoverImage(self.ui.doc_settings)
            end
        end,
    }
end

function CoverImage:menu_entry_background(color)
    return {
        text = _("Fit to screen, " .. color .. " background"),
        checked_func = function()
            return self.cover_image_background == color
        end,
        callback = function()
            local old_background = self.cover_image_background
            self.cover_image_background = color
            G_reader_settings:saveSetting("cover_image_background", self.cover_image_background)
            if self.enabled and old_background ~= self.cover_image_background then
                self:createCoverImage(self.ui.doc_settings)
            end
        end,
    }
end

-- menu entry: scale, background, format
function CoverImage:menu_entry_sbf()
    return {
        text = _("Size, background and format"),
        enabled_func = function()
            return self.enabled
        end,
        sub_item_table = {
            {
                text_func = function()
                    return T(_("Aspect ratio stretch threshold (%1)"),
                        self.cover_image_stretch_limit ~= 0 and self.cover_image_stretch_limit .."%" or "off")
                end,
                keep_menu_open = true,
                help_text_func = function()
                    return T(_("If the image and the screen have a similar aspect ratio (±%1%), stretch the image instead of keeping its aspect ratio."), self.cover_image_stretch_limit )
                end,
                callback = function(touchmenu_instance)
                    local function createCover()
                        self:createCoverImage(self.ui.doc_settings)
                    end
                    self:sizeSpinner(touchmenu_instance, "cover_image_stretch_limit", _("Set strech threshold"), 0, 20, 8, createCover)
                end,
            },
            self:menu_entry_background("black"),
            self:menu_entry_background("white"),
            self:menu_entry_background("gray"),
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
            self:menu_entry_format(_("JPG file format"), "jpg"),
            self:menu_entry_format(_("PNG file format"), "png"),
            self:menu_entry_format(_("BMP file format"), "bmp"),
        },
    }
end

-- CoverImage main menu
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
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = about_text,
                    })
                end,
                keep_menu_open = true,
                separator = true,
            },
            -- menu entry: filename dialog
            {
                text = _("Set image path"),
                help_text_func = function()
                    local text = self.cover_image_path
                    text = text ~= "" and text or _("not set")
                    return T(_("The actual cover image path is:\n%1"), text)
                end,
                checked_func = function()
                    return self.cover_image_path ~= "" and pathOk(self.cover_image_path)
                end,
                callback = function(touchmenu_instance)
                    UIManager:show(ConfirmBox:new{
                        text = set_image_text,
                        ok_text = _("Yes"),
                        cancel_text = _("No"),
                        ok_callback = function()
                            self:choosePathFile(touchmenu_instance, "cover_image_path", false, true, self.migrateCover)
                        end,
                    })
                end,
            },
            -- menu entry: enable
            {
                text = _("Save cover image"),
                checked_func = function()
                    return self.enabled and pathOk(self.cover_image_path)
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
            -- menu entry: scale, background, format
            self:menu_entry_sbf(),
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
                text = _("Select fallback image"),
                help_text_func = function()
                    local text = self.cover_image_fallback_path
                    text = text ~= "" and text or _("not set")
                    return T(_("The fallback image used on document close is:\n%1"), text)
                end,
                checked_func = function()
                    return lfs.attributes(self.cover_image_fallback_path, "mode") == "file"
                end,
                callback = function(touchmenu_instance)
                    self:choosePathFile(touchmenu_instance, "cover_image_fallback_path", false, false)
                end,
            },
            -- menu entry: fallback
            {
                text = _("Turn on fallback image"),
                checked_func = function()
                    return self.fallback
                end,
                enabled_func = function()
                    return lfs.attributes(self.cover_image_fallback_path, "mode") == "file"
                end,
                callback = function()
                    self.fallback = not self.fallback
                    G_reader_settings:saveSetting("cover_image_fallback", self.fallback)
                end,
                separator = true,
            },
            -- menu entry: Cache settings
            self:menu_entry_cache(),
        },
    }
end

return CoverImage
