--[[--
@module koplugin.coverimage

Plugin for saving a cover image to a file and scaling it to fit the screen.
]]

local Device = require("device")

if not (Device.isAndroid() or Device.isEmulator() or Device.isRemarkable() or Device.isPocketBook()) then
    return { disabled = true }
end

local A, android = pcall(require, "android")  -- luacheck: ignore
local Blitbuffer = require("ffi/blitbuffer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local RenderImage = require("ui/renderimage")
local Screen = require("device").screen
local T = require("ffi/util").template
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local md5 = require("ffi/sha2").md5
local util = require("util")
local _ = require("gettext")

-- todo: please check the default paths directly on the depending Device:getDefaultCoverPath()


local function isPathAllowed(path)
    -- don't allow a path that interferes with frontent cache-framework; quick and dirty check

    if not Device:isValidPath(path) then -- isValidPath expects a trailing slash
        return false
    elseif not util.pathExists(path:gsub("/$", "")) then -- pathExists expects no trailing slash
        return false
    elseif Device.isAndroid() then
        return path ~= "/sdcard/koreader/cache/"
            and ffiutil.realpath(path) ~= ffiutil.realpath(android.getExternalStoragePath() .. "/koreader/cache/")
    else
        return path ~= "./cache/" and ffiutil.realpath(path) ~= ffiutil.realpath("./cache/")
    end
end

local function isFileOk(filename)
    local path, name = util.splitFilePathName(filename)

    if not isPathAllowed(path) then
        return false
    end

    return name ~="" and lfs.attributes(filename, "mode") ~= "directory"
end

local function getExtension(filename)
    local _, name = util.splitFilePathName(filename)
    return util.getFileNameSuffix(name):lower()
end

local CoverImage = WidgetContainer:new{
    name = "coverimage",
    is_doc_only = true,
}

local default_cache_path = DataStorage:getDataDir() .. "/cache/cover_image.cache/"
local default_fallback_path = DataStorage:getDataDir() .. "/"

function CoverImage:init()
    self.cover_image_path = G_reader_settings:readSetting("cover_image_path") or Device:getDefaultCoverPath()
    self.cover_image_format = G_reader_settings:readSetting("cover_image_format") or "auto"
    self.cover_image_quality = G_reader_settings:readSetting("cover_image_quality") or 75
    self.cover_image_stretch_limit = G_reader_settings:readSetting("cover_image_stretch_limit") or 8
    self.cover_image_background = G_reader_settings:readSetting("cover_image_background") or "black"
    self.cover_image_fallback_path = G_reader_settings:readSetting("cover_image_fallback_path") or default_fallback_path
    self.cover_image_cache_path = G_reader_settings:readSetting("cover_image_cache_path") or default_cache_path
    self.cover_image_cache_maxfiles = G_reader_settings:readSetting("cover_image_cache_maxfiles") or 36
    self.cover_image_cache_maxsize = G_reader_settings:readSetting("cover_image_cache_maxsize") or 5 -- MB
    self.cover_image_cache_prefix = "cover_"
    self.cover = G_reader_settings:isTrue("cover_image_enabled")
    self.fallback = G_reader_settings:isTrue("cover_image_fallback")

    lfs.mkdir(self.cover_image_cache_path)

    self.ui.menu:registerToMainMenu(self)
end

function CoverImage:cleanUpImage()
    if self.cover_image_fallback_path == "" or not self:fallbackEnabled() then
        os.remove(self.cover_image_path)
    elseif lfs.attributes(self.cover_image_fallback_path, "mode") ~= "file" then
        UIManager:show(InfoMessage:new{
            text = T(_("\"%1\"\nis not a valid image file!\nA valid fallback image is required in Cover-Image."), self.cover_image_fallback_path),
            show_icon = true,
            timeout = 10,
        })
        os.remove(self.cover_image_path)
    elseif isFileOk(self.cover_image_path) then
        ffiutil.copyFile(self.cover_image_fallback_path, self.cover_image_path)
    end
end

function CoverImage:createCoverImage(doc_settings)
    if self:coverEnabled() and doc_settings:nilOrFalse("exclude_cover_image") then
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
                local act_format = self.cover_image_format == "auto" and getExtension(self.cover_image_path) or self.cover_image_format
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

            local act_format = self.cover_image_format == "auto" and getExtension(self.cover_image_path) or self.cover_image_format
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
    if self:fallbackEnabled() then
        self:cleanUpImage()
    end
end

function CoverImage:onReaderReady(doc_settings)
    logger.dbg("CoverImage: onReaderReady")
    self:createCoverImage(doc_settings)
end

function CoverImage:fallbackEnabled()
    return self.fallback and isFileOk(self.cover_image_fallback_path)
end

function CoverImage:coverEnabled()
    return self.cover and isFileOk(self.cover_image_path)
end

---------------------------
-- cache handling functions
---------------------------

function CoverImage:getCacheFile()
    local dummy, document_name = util.splitFilePathName(self.ui.document.file)
    -- use document_name here. Title may contain characters not allowed on every filesystem (esp. vfat on /sdcard)
    local key = document_name .. "_" .. self.cover_image_quality .. "_" .. self.cover_image_stretch_limit .. "_"
        .. self.cover_image_background .. "_" .. self.cover_image_format

    return self.cover_image_cache_path .. self.cover_image_cache_prefix .. md5(key) .. "." .. getExtension(self.cover_image_path)
end

function CoverImage:emptyCache()
    for entry in lfs.dir(self.cover_image_cache_path) do
        if entry ~= "." and entry ~= ".." then
            local file = self.cover_image_cache_path .. entry
            if entry:sub(1, self.cover_image_cache_prefix:len()) == self.cover_image_cache_prefix
                and lfs.attributes(file, "mode") == "file" then
                    os.remove(file)
            end
        end
    end
end

function CoverImage:getCacheFiles(cache_path, cache_prefix)
    local cache_count = 0
    local cache_size = 0
    local files = {}
    for entry in lfs.dir(self.cover_image_cache_path) do
        if entry ~= "." and entry ~= ".." then
            local file = cache_path .. entry
            if entry:sub(1, self.cover_image_cache_prefix:len()) == cache_prefix
                and lfs.attributes(file, "mode") == "file" then
                cache_count = cache_count + 1
                local blocksize = lfs.attributes(file).blksize or 4096
                files[cache_count] = {
                    name = file,
                    size = math.floor(((lfs.attributes(file).size) + blocksize - 1)/ blocksize) * blocksize,
                    mod = lfs.attributes(file).modification,
                }
                cache_size = cache_size + files[cache_count].size
            end
        end
    end
    logger.dbg("CoverImage: start - cache size: ".. cache_size .. " Bytes, cached files: " .. cache_count)
    return cache_count, cache_size, files
end

function CoverImage:cleanCache()
    if not self:isCacheEnabled() then
        self:emptyCache()
        return
    end

    local cache_count, cache_size, files = self:getCacheFiles(self.cover_image_cache_path, self.cover_image_cache_prefix)

    -- delete the oldest files first
    table.sort(files, function(a, b) return a.mod < b.mod end)
    local index = 1
    while (cache_count > self.cover_image_cache_maxfiles and self.cover_image_cache_maxfiles ~= 0)
        or (cache_size > self.cover_image_cache_maxsize * 1000 * 1000 and self.cover_image_cache_maxsize ~= 0)
        and index <= #files do
        os.remove(files[index].name)
        cache_count = cache_count - 1
        cache_size = cache_size - files[index].size
        index = index + 1
    end
    logger.dbg("CoverImage: clean - cache size: ".. cache_size .. " Bytes, cached files: " .. cache_count)
end

function CoverImage:isCacheEnabled(path)
    if not path then
        path = self.cover_image_cache_path
    end

    return self.cover_image_cache_maxfiles >= 0 and self.cover_image_cache_maxsize >= 0
        and lfs.attributes(path, "mode") == "directory" and isPathAllowed(path)
end

-- callback for choosePathFile()
function CoverImage:migrateCache(old_path, new_path)
    if old_path == new_path or not self:isCacheEnabled(new_path) then
        return
    end
    for entry in lfs.dir(old_path) do
        if entry ~= "." and entry ~= ".."   then
            local old_file = old_path .. entry
            if lfs.attributes(old_file, "mode") == "file" and entry:sub(1, self.cover_image_cache_prefix:len()) == self.cover_image_cache_prefix then
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
@string key is the G_reader_setting key which is used and changed
@boolean folder_only just selects a path, no file handling
@boolean new_file allows to enter a new filename, or use just an existing file
@function migrate(a,b) callback to a function to mangle old folder/file with new folder/file.
    Can be used for migrating the contents of the old path to the new one
]]
function CoverImage:choosePathFile(touchmenu_instance, key, folder_only, new_file, migrate)
    local old_path, dummy = util.splitFilePathName(self[key])
    UIManager:show(PathChooser:new{
        select_directory = folder_only or new_file,
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
                    migrate(self, self[key], dir_path)
                end
                self[key] = dir_path
                G_reader_settings:saveSetting(key, dir_path)
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
                            callback = function()
                                UIManager:close(file_input)
                            end,
                        },
                        {
                            text = _("Save"),
                            callback = function()
                                local file = file_input:getInputText()
                                if migrate and self[key] and self[key] ~= "" then
                                    migrate(self, self[key], file)
                                end
                                self[key] = file
                                G_reader_settings:saveSetting(key, file)
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
                    migrate(self, self[key], dir_path)
                end
                self[key] = dir_path
                G_reader_settings:saveSetting(key, dir_path)
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
            end
        end,
    })
end

--[[--
Update a specific G_reader_setting's value via a Spinner

@touchmenu_instance used for updating the menu
@string setting is the G_reader_setting key which is used and changed
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
            if self:coverEnabled() and spin.value ~= old_val then
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
This plugin saves a book cover to a file. That file can then be used as a screensaver on certain devices.

If enabled, the cover image of the current file is stored in the set path on book opening. Books can be excluded if desired.

If disabled, the cover file will be deleted.

If fallback is enabled, the fallback file will be copied to the screensaver file on book closing.
If the filename is empty or the file doesn't exist, the cover file will be deleted.

If fallback is disabled, the screensaver image will stay in place after closing a book.]])

local set_image_text = _([[
You can either choose an existing file:
- Select a file

or specify a new file:
- First select a folder
- Then add the name of the new file

or delete the path:
- First select a folder
- Clear the name of the file]])

-- menu entry: Cache settings
function CoverImage:menuEntryCache()
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
                        number = util.getFriendlySize(self.cover_image_cache_maxsize * 1e6)
                    elseif self.cover_image_cache_maxsize == 0 then
                        number = _("unlimited")
                    else
                        number = _("off")
                    end
                    return T(_("Maximum size of cached covers (%1)"), number)
                end,
                help_text = _("If set to zero the cache size is unlimited.\nIf set to -1 the cache is disabled."),
                checked_func = function()
                    return self.cover_image_cache_maxsize >= 0
                end,
                callback = function(touchmenu_instance)
                    self:sizeSpinner(touchmenu_instance, "cover_image_cache_maxsize", _("Cache size"), -1, 100, 5, self.cleanCache)
                end,
            },
            self:menuEntrySetPath("cover_image_cache_path", _("Cover cache folder"), _("Current cache path:\n%1"),
                ("Select a cache folder. The contents of the old folder will be migrated."), default_cache_path, true, false, self.migrateCache),
            {
                text = _("Clear cached covers"),
                help_text_func = function()
                    local cache_count, cache_size
                        = self:getCacheFiles(self.cover_image_cache_path, self.cover_image_cache_prefix)
                    return T(_("The cache contains %1 files and uses %2."), cache_count, util.getFriendlySize(cache_size))
                end,
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text =  _("Clear the cover image cache?"),
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

--[[--
Menu entry for setting an specific G_reader_setting key for a path/file

@string key is the G_reader_setting key which is used and changed
@string title shown in the menu
@string help shown in the menu
@string info shown in the menu (if containing %1, the value of the key is shown)
@string the default value
@bool folder_only sets if only folders can be selected
@bool new_file sets if a new filename can be entered
@function migrate a callback for example moving the folder contents
]]
function CoverImage:menuEntrySetPath(key, title, help, info, default, folder_only, new_file, migrate)
    return {
        text = title,
        help_text_func = function()
            local text = self[key]
            text = text ~= "" and text or _("not set")
            return T(help, text)
        end,
        checked_func = function()
            return isFileOk(self[key]) or (isPathAllowed(self[key]) and folder_only)
        end,
        callback = function(touchmenu_instance)
            UIManager:show(ConfirmBox:new{
                text = info,
                ok_callback = function()
                    self:choosePathFile(touchmenu_instance, key, folder_only, new_file, migrate)
                end,
                other_buttons = {{
                {
                    text = _("Default"),
                    callback = function()
                        if migrate then
                            migrate(self, self[key],default)
                        end
                        self[key] = default
                        G_reader_settings:saveSetting(key, default)
                        if touchmenu_instance then
                            touchmenu_instance:updateItems()
                        end
                    end

                }
            }},
            })
        end,
    }
end

function CoverImage:menuEntryFormat(title, format)
    return {
        text = title,
        checked_func = function()
            return self.cover_image_format == format
        end,
        callback = function()
            local old_cover_image_format = self.cover_image_format
            self.cover_image_format = format
            G_reader_settings:saveSetting("cover_image_format", format)
            if self:coverEnabled() and old_cover_image_format ~= format then
                self:createCoverImage(self.ui.doc_settings)
            end
        end,
    }
end

function CoverImage:menuEntryBackground(color, color_translatable)
    return {
        text = T(_("Fit to screen, %1 background"), _(color_translatable)),
        checked_func = function()
            return self.cover_image_background == color
        end,
        callback = function()
            local old_background = self.cover_image_background
            self.cover_image_background = color
            G_reader_settings:saveSetting("cover_image_background", self.cover_image_background)
            if self:coverEnabled() and old_background ~= self.cover_image_background then
                self:createCoverImage(self.ui.doc_settings)
            end
        end,
    }
end

-- menu entry: scale, background, format
function CoverImage:menuEntrySBF()
    return {
        text = _("Size, background and format"),
        enabled_func = function()
            return self:coverEnabled()
        end,
        sub_item_table = {
            {
                text_func = function()
                    return T(_("Aspect ratio stretch threshold (%1)"),
                        self.cover_image_stretch_limit ~= 0 and self.cover_image_stretch_limit .. "%" or _("off"))
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
            self:menuEntryBackground("black", _("black")),
            self:menuEntryBackground("white", _("white")),
            self:menuEntryBackground("gray", _("gray")),
            {
                text = _("Original image"),
                checked_func = function()
                    return self.cover_image_background == "none"
                end,
                callback = function()
                    local old_background = self.cover_image_background
                    self.cover_image_background = "none"
                    G_reader_settings:saveSetting("cover_image_background", self.cover_image_background)
                    if self:coverEnabled() and old_background ~= self.cover_image_background then
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
                    if self:coverEnabled() and old_cover_image_format ~= self.cover_image_format then
                        self:createCoverImage(self.ui.doc_settings)
                    end
                end,
            },
            self:menuEntryFormat(_("JPG file format"), "jpg"),
            self:menuEntryFormat(_("PNG file format"), "png"),
            self:menuEntryFormat(_("BMP file format"), "bmp"),
        },
    }
end

-- CoverImage main menu
function CoverImage:addToMainMenu(menu_items)
    menu_items.coverimage = {
        sorting_hint = "screen",
        text = _("Cover image"),
        checked_func = function()
            return self:coverEnabled() or self:fallbackEnabled()
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
            self:menuEntrySetPath("cover_image_path", _("Set image path"), _("Current Cover image path:\n%1"), set_image_text,
                 Device:getDefaultCoverPath(), false, true, self.migrateCover),
            -- menu entry: enable
            {
                text = _("Save cover image"),
                checked_func = function()
                    return self:coverEnabled()
                end,
                enabled_func = function()
                    return self.cover_image_path ~= "" and isFileOk(self.cover_image_path)
                end,
                callback = function()
                    if self.cover_image_path ~= "" then
                        self.cover = not self.cover
                        self.cover = self.cover and self:coverEnabled()
                        G_reader_settings:saveSetting("cover_image_enabled", self.cover)
                        if self:coverEnabled() then
                            self:createCoverImage(self.ui.doc_settings)
                        else
                            self:cleanUpImage()
                        end
                    end
                end,
            },
            -- menu entry: scale, background, format
            self:menuEntrySBF(),
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
            self:menuEntrySetPath("cover_image_fallback_path", _("Set fallback path"),
                _("The fallback image used on document close is:\n%1"), _("You can select a fallback image."), default_fallback_path, false, false),
            -- menu entry: fallback
            {
                text = _("Turn on fallback image"),
                checked_func = function()
                    return self:fallbackEnabled()
                end,
                enabled_func = function()
                    return lfs.attributes(self.cover_image_fallback_path, "mode") == "file"
                end,
                callback = function()
                    self.fallback = not self.fallback
                    self.fallback = self.fallback and self:fallbackEnabled()
                    G_reader_settings:saveSetting("cover_image_fallback", self.fallback)
                    if not self:coverEnabled() then
                        self:cleanUpImage()
                    end
                end,
                separator = true,
            },
            -- menu entry: Cache settings
            self:menuEntryCache(),
        },
    }
end

return CoverImage
