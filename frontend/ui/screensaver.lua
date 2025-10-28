local Blitbuffer = require("ffi/blitbuffer")
local BookList = require("ui/widget/booklist")
local BookStatusWidget = require("ui/widget/bookstatuswidget")
local CustomPositionContainer = require("ui/widget/container/custompositioncontainer")
local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local ImageWidget = require("ui/widget/imagewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RenderImage = require("ui/renderimage")
local ScreenSaverWidget = require("ui/widget/screensaverwidget")
local ScreenSaverLockWidget = require("ui/widget/screensaverlockwidget")
local SpinWidget = require("ui/widget/spinwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local time = require("ui/time")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen

-- Default settings
if G_reader_settings:hasNot("screensaver_show_message") then
    G_reader_settings:makeFalse("screensaver_show_message")
end
if G_reader_settings:hasNot("screensaver_type") then
    G_reader_settings:saveSetting("screensaver_type", "disable")
    G_reader_settings:makeTrue("screensaver_show_message")
end
if G_reader_settings:hasNot("screensaver_img_background") then
    G_reader_settings:saveSetting("screensaver_img_background", "black")
end
if G_reader_settings:hasNot("screensaver_msg_background") then
    G_reader_settings:saveSetting("screensaver_msg_background", "none")
end
if G_reader_settings:hasNot("screensaver_message_container") then
    G_reader_settings:saveSetting("screensaver_message_container", "box")
end
if G_reader_settings:hasNot("screensaver_message_vertical_position") then
    G_reader_settings:saveSetting("screensaver_message_vertical_position", 50)
end
if G_reader_settings:hasNot("screensaver_message_alpha") then
    G_reader_settings:saveSetting("screensaver_message_alpha", 100)
end
if G_reader_settings:hasNot("screensaver_stretch_images") then
    G_reader_settings:makeFalse("screensaver_stretch_images")
end
if G_reader_settings:hasNot("screensaver_rotate_auto_for_best_fit") then
    G_reader_settings:makeFalse("screensaver_rotate_auto_for_best_fit")
end
if G_reader_settings:hasNot("screensaver_delay") then
    G_reader_settings:saveSetting("screensaver_delay", "disable")
end
if G_reader_settings:hasNot("screensaver_hide_fallback_msg") then
    G_reader_settings:makeFalse("screensaver_hide_fallback_msg")
end

local Screensaver = {
    default_screensaver_message = _("Sleeping"),

    -- State values
    show_message = nil,
    screensaver_type = nil,
    prefix = nil,
    event_message = nil,
    overlay_message = nil,
    screensaver_background = nil,
    image = nil,
    image_file = nil,
    delayed_close = nil,
    screensaver_widget = nil,
}

-- Remind emulator users that Power is bound to F2
if Device:isEmulator() then
    Screensaver.default_screensaver_message = Screensaver.default_screensaver_message .. "\n" .. _("(Press F2 to resume)")
end

local function _getRandomImage(dir)
    if not dir then return end
    local match_func = function(file) -- images, ignore macOS resource forks
        return not util.stringStartsWith(ffiUtil.basename(file), "._") and DocumentRegistry:isImageFile(file)
    end
    -- Slippery slope ahead! Ensure the number of files does not become unmanageable, otherwise we'll have performance issues.
    -- Power users can increase this cap if needed. Beware though, this grows at O(n * c) where c increases with the number of files.
    -- NOTE: empirically, a kindle 4 found and sorted 128 files in 0.274828 seconds.
    local max_files = G_reader_settings:readSetting("screensaver_max_files") or 256
    -- If the user has set the option to cycle images alphabetically, we sort the files instead of picking a random one.
    if G_reader_settings:isTrue("screensaver_cycle_images_alphabetically") then
        local start_time = time.now()
        local files = {}
        util.findFiles(dir, function(file)
            if match_func(file) then
                table.insert(files, file)
            end
        end, false, max_files)
        if #files == 0 then return end
        -- we have files, sort them in natural order, i.e z2 < z11 < z20
        local sort = require("sort")
        local natsort = sort.natsort_cmp()
        table.sort(files, function(a, b)
            return natsort(a, b)
        end)
        local elapsed_time = time.to_s(time.since(start_time))
        logger.info("Screensaver: found and sorted", #files, "files in", elapsed_time, "seconds")
        local index = G_reader_settings:readSetting("screensaver_cycle_index", 0) + 1
        if index > #files then -- wrap around
            index = 1
        end
        G_reader_settings:saveSetting("screensaver_cycle_index", index)
        return files[index]
    else -- Pick a random file (default behavior)
        return filemanagerutil.getRandomFile(dir, match_func, max_files)
    end
end

local function addOverlayMessage(widget, widget_height, text)
    local FrameContainer = require("ui/widget/container/framecontainer")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local Size = require("ui/size")
    local TextWidget = require("ui/widget/textwidget")

    local face = Font:getFace("infofont")
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()

    local textw = TextWidget:new{
        text = text,
        face = face,
    }
    -- Don't make our message reach full screen width
    if textw:getWidth() > screen_w * 0.9 then
        -- Text too wide: use TextBoxWidget for multi lines display
        textw = TextBoxWidget:new{
            text = text,
            face = face,
            width = math.floor(screen_w * 0.9)
        }
    end
    textw = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.default,
        margin = 0,
        textw,
    }
    -- If our host widget is already at the top, we'll position ourselves below it.
    if widget_height then
        textw = VerticalGroup:new{
            VerticalSpan:new{
                width = widget_height,
            },
            textw,
        }
    end
    textw = RightContainer:new{
        dimen = {
            w = screen_w,
            h = textw:getSize().h,
        },
        textw,
    }
    widget = OverlapGroup:new{
        dimen = {
            h = screen_w,
            w = screen_h,
        },
        widget,
        textw,
    }
    return widget
end

function Screensaver.chooseFolder()
    local title_header = _("Current random image folder:")
    local current_path = G_reader_settings:readSetting("screensaver_dir")
    local caller_callback = function(path)
        G_reader_settings:saveSetting("screensaver_dir", path)
    end
    filemanagerutil.showChooseDialog(title_header, caller_callback, current_path)
end

function Screensaver.chooseFile()
    local title_header, current_path, file_filter, caller_callback
    title_header = _("Current image or document cover:")
    current_path = G_reader_settings:readSetting("screensaver_document_cover")
    file_filter = function(filename)
        return DocumentRegistry:hasProvider(filename)
    end
    caller_callback = function(path)
        G_reader_settings:saveSetting("screensaver_document_cover", path)
    end
    filemanagerutil.showChooseDialog(title_header, caller_callback, current_path, nil, file_filter)
end

function Screensaver.isExcluded(ui)
    if ui.document then
        return ui.doc_settings:isTrue("exclude_screensaver")
    else
        local lastfile = G_reader_settings:readSetting("lastfile") or false
        return lastfile and BookList.hasBookBeenOpened(lastfile)
                        and BookList.getDocSettings(lastfile):isTrue("exclude_screensaver")
    end
end

function Screensaver:setMessage()
    local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
    local InputDialog = require("ui/widget/inputdialog")
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Sleep screen message"),
        input = G_reader_settings:readSetting("screensaver_message") or self.default_screensaver_message,
        allow_newline = true,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Info"),
                    callback = FileManagerBookInfo.expandString,
                },
                {
                    text = _("Set message"),
                    callback = function()
                        G_reader_settings:saveSetting("screensaver_message", input_dialog:getInputText())
                        UIManager:close(input_dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function Screensaver:setStretchLimit(touchmenu_instance)
    UIManager:show(SpinWidget:new{
        value = G_reader_settings:readSetting("screensaver_stretch_limit_percentage", 8),
        value_min = 0,
        value_max = 25,
        default_value = 8,
        unit = "%",
        title_text = _("Set maximum stretch limit"),
        ok_text = _("Set"),
        ok_always_enabled = true,
        callback = function(spin)
            G_reader_settings:saveSetting("screensaver_stretch_limit_percentage", spin.value)
            G_reader_settings:makeTrue("screensaver_stretch_images")
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
        extra_text = _("Disable stretch"),
        extra_callback = function()
            G_reader_settings:makeFalse("screensaver_stretch_images")
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
        option_text = _("Full stretch"),
        option_callback = function()
            G_reader_settings:makeTrue("screensaver_stretch_images")
            G_reader_settings:delSetting("screensaver_stretch_limit_percentage")
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
end

function Screensaver:setCustomPosition(touchmenu_instance)
    UIManager:show(SpinWidget:new{
        title_text = _("Adjust message position"),
        info_text = _("Set the message's position as a percentage from the bottom of the screen.\n\n100% = top\n50% = middle\n0% = bottom"),
        value = G_reader_settings:readSetting("screensaver_message_vertical_position", 50),
        value_min = 0,
        value_max = 100,
        value_step = 5,
        value_hold_step = 1,
        default_value = 50,
        precision = "%.1f",
        unit = "%",
        ok_text = _("Set position"),
        callback = function(spin)
            G_reader_settings:saveSetting("screensaver_message_vertical_position", spin.value)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
end

function Screensaver:setMessageOpacity(touchmenu_instance)
    UIManager:show(SpinWidget:new{
        title_text = _("Container opacity"),
        info_text = _("Set the opacity level of the sleep screen message."),
        value = G_reader_settings:readSetting("screensaver_message_alpha", 100),
        value_min = 0,
        value_max = 100,
        value_step = 5,
        value_hold_step = 1,
        default_value = 100,
        unit = "%",
        ok_text = _("Set opacity"),
        callback = function(spin)
            G_reader_settings:saveSetting("screensaver_message_alpha", spin.value)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
end

-- When called after setup(), may not match the saved settings, because it accounts for fallbacks that might have kicked in.
function Screensaver:getMode()
   return self.screensaver_type
end

function Screensaver:modeExpectsPortrait()
    return self.screensaver_type ~= "message"
       and self.screensaver_type ~= "disable"
       and self.screensaver_type ~= "readingprogress"
       and self.screensaver_type ~= "bookstatus"
end

function Screensaver:modeIsImage()
    return self.screensaver_type == "cover"
        or self.screensaver_type == "random_image"
end

function Screensaver:withBackground()
    return self.screensaver_background ~= "none"
end

function Screensaver:setup(event, event_message)
    self.show_message = G_reader_settings:isTrue("screensaver_show_message")
    self.screensaver_type = G_reader_settings:readSetting("screensaver_type")
    local screensaver_img_background = G_reader_settings:readSetting("screensaver_img_background")
    local screensaver_msg_background = G_reader_settings:readSetting("screensaver_msg_background")

    -- These 2 (optional) parameters are to support poweroff and reboot actions on Kobo (c.f., UIManager)
    self.prefix = event and event .. "_" or "" -- "", "poweroff_" or "reboot_"
    self.event_message = event_message
    if G_reader_settings:has(self.prefix .. "screensaver_type") then
        self.screensaver_type = G_reader_settings:readSetting(self.prefix .. "screensaver_type")
    else
        if event and G_reader_settings:isFalse("screensaver_hide_fallback_msg") then
            -- Display the provided event_message over the screensaver,
            -- so the user can distinguish between suspend (no overlay),
            -- and reboot/poweroff (overlaid message).
            self.overlay_message = self.event_message
        end
    end

    -- Check lastfile and setup the requested mode's resources, or a fallback mode if the required resources are unavailable.
    self.ui = require("apps/reader/readerui").instance or require("apps/filemanager/filemanager").instance
    local lastfile = G_reader_settings:readSetting("lastfile")
    local is_document_cover = false
    if self.screensaver_type == "document_cover" then
        -- Set lastfile to the document of which we want to show the cover.
        lastfile = G_reader_settings:readSetting("screensaver_document_cover")
        self.screensaver_type = "cover"
        is_document_cover = true
    end
    if self.screensaver_type == "cover" then
        local excluded
        if not is_document_cover and lastfile then
            local exclude_finished_book
            local exclude_on_hold_book
            local exclude_book_in_fm = not self.ui.document and G_reader_settings:isTrue("screensaver_hide_cover_in_filemanager")
            if BookList.hasBookBeenOpened(lastfile) then
                local doc_settings = self.ui.doc_settings or BookList.getDocSettings(lastfile)
                excluded = doc_settings:isTrue("exclude_screensaver")
                local book_summary = doc_settings:readSetting("summary")
                local book_finished = book_summary and book_summary.status == "complete"
                local book_on_hold = book_summary and book_summary.status == "abandoned"
                exclude_finished_book = G_reader_settings:isTrue("screensaver_exclude_finished_books") and book_finished
                exclude_on_hold_book = G_reader_settings:isTrue("screensaver_exclude_on_hold_books") and book_on_hold
            end
            local should_exclude_book = exclude_book_in_fm or exclude_finished_book or exclude_on_hold_book
            if should_exclude_book then
                excluded = true
                self.show_message = false
            end
        else
            -- No DocSetting, not excluded
            excluded = false
        end
        if not excluded then
            if lastfile and lfs.attributes(lastfile, "mode") == "file" then
                if DocumentRegistry:isImageFile(lastfile) then
                    self.image_file = lastfile
                else
                    self.image = self.ui.bookinfo:getCoverImage(self.ui.document, lastfile)
                    if self.image == nil then
                        self.screensaver_type = "random_image"
                    end
                end
            else
                self.screensaver_type = "random_image"
            end
        else
            -- Fallback to random images if this book cover is excluded
            self.screensaver_type = "random_image"
        end
    end
    if self.screensaver_type == "bookstatus" then
        if not (self.ui.document and self.ui.doc_settings:nilOrFalse("exclude_screensaver")) then
            self.screensaver_type = "random_image"
        end
    end
    if self.screensaver_type == "readingprogress" and self.ui.statistics == nil then
        self.screensaver_type = "random_image"
    end
    if self.screensaver_type == "disable" then
        if self.ui.document and self.ui.doc_settings:isTrue("exclude_screensaver") then
            self.screensaver_type = "random_image"
        end
    end
    if self.screensaver_type == "random_image" then
        local screensaver_dir = G_reader_settings:readSetting(self.prefix .. "screensaver_dir")
                             or G_reader_settings:readSetting("screensaver_dir")
        self.image_file = _getRandomImage(screensaver_dir) or "resources/koreader.png" -- Fallback image
    end

    -- Use the right background setting depending on the effective mode, now that fallbacks have kicked in.
    if self:modeIsImage() then
        self.screensaver_background = screensaver_img_background
    else
        self.screensaver_background = screensaver_msg_background
    end
end

function Screensaver:show()
    -- self.ui is set in Screensaver:setup()

    -- Notify Device methods that we're in screen saver mode, so they know whether to suspend or resume on Power events.
    Device.screen_saver_mode = true

    -- Check if we requested a lock gesture
    local with_gesture_lock = Device:isTouchDevice() and G_reader_settings:readSetting("screensaver_delay") == "gesture"

    -- In as-is mode with no message, no overlay and no lock, we've got nothing to show :)
    if self.screensaver_type == "disable" and not self.show_message and not self.overlay_message and not with_gesture_lock then
        return
    end

    local orig_dimen
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    local rotation_mode = Screen:getRotationMode()

    -- We mostly always suspend in Portrait/Inverted Portrait mode...
    -- ... except when we just show an InfoMessage or when the screensaver
    -- is disabled, as it plays badly with Landscape mode (c.f., #4098 and #5920).
    -- We also exclude full-screen widgets that work fine in Landscape mode,
    -- like ReadingProgress and BookStatus (c.f., #5724)
    if self:modeExpectsPortrait() then
        Device.orig_rotation_mode = rotation_mode
        -- Leave Portrait & Inverted Portrait alone, that works just fine.
        if bit.band(Device.orig_rotation_mode, 1) == 1 then
            -- i.e., only switch to Portrait if we're currently in *any* Landscape orientation (odd number)
            Screen:setRotationMode(Screen.DEVICE_ROTATED_UPRIGHT)
            orig_dimen = with_gesture_lock and { w = screen_w, h = screen_h }
            screen_w, screen_h = screen_h, screen_w
        else
            Device.orig_rotation_mode = nil
        end

        -- On eInk, if we're using a screensaver mode that shows an image,
        -- flash the screen to white first, to eliminate ghosting.
        if Device:hasEinkScreen() and self:modeIsImage() then
            if self:withBackground() then
                Screen:clear()
            end
            Screen:refreshFull(0, 0, screen_w, screen_h)

            -- On Kobo, on sunxi SoCs with a recent kernel, wait a tiny bit more to avoid weird refresh glitches...
            if Device:isKobo() and Device:isSunxi() then
                ffiUtil.usleep(150 * 1000)
            end
        end
    else
        -- nil it, in case user switched ScreenSaver modes during our lifetime.
        Device.orig_rotation_mode = nil
    end

    -- Build the main widget for the effective mode, all the sanity checks were handled in setup
    local widget = nil
    if self.screensaver_type == "cover" or self.screensaver_type == "random_image" then
        local widget_settings = {
            width = screen_w,
            height = screen_h,
            scale_factor = G_reader_settings:isFalse("screensaver_stretch_images") and 0 or nil,
            stretch_limit_percentage = G_reader_settings:readSetting("screensaver_stretch_limit_percentage"),
        }
        if self.image then
            widget_settings.image = self.image
            widget_settings.image_disposable = true
        elseif self.image_file then
            if G_reader_settings:isTrue("screensaver_rotate_auto_for_best_fit") then
                -- We need to load the image here to determine whether to rotate
                if util.getFileNameSuffix(self.image_file) == "svg" then
                    widget_settings.image = RenderImage:renderSVGImageFile(self.image_file, nil, nil, 1)
                else
                    widget_settings.image = RenderImage:renderImageFile(self.image_file, false, nil, nil)
                end
                if not widget_settings.image then
                    widget_settings.image = RenderImage:renderCheckerboard(screen_w, screen_h, Screen.bb:getType())
                end
                widget_settings.image_disposable = true
            else
                widget_settings.file = self.image_file
                widget_settings.file_do_cache = false
            end
            widget_settings.alpha = true
        end -- set cover or file
        if G_reader_settings:isTrue("screensaver_rotate_auto_for_best_fit") then
            local angle = rotation_mode == 3 and 180 or 0 -- match mode if possible
            if (widget_settings.image:getWidth() < widget_settings.image:getHeight()) ~= (widget_settings.width < widget_settings.height) then
                angle = angle + (G_reader_settings:isTrue("imageviewer_rotation_landscape_invert") and -90 or 90)
            end
            widget_settings.rotation_angle = angle
        end
        widget = ImageWidget:new(widget_settings)
    elseif self.screensaver_type == "bookstatus" then
        widget = BookStatusWidget:new{
            ui = self.ui,
            readonly = true,
        }
    elseif self.screensaver_type == "readingprogress" then
        widget = self.ui.statistics:onShowReaderProgress(true) -- get widget
    end

    -- Assume that we'll be covering the full-screen by default (either because of a widget, or a background fill).
    local covers_fullscreen = true
    -- Speaking of, set that background fill up...
    local background
    if self.screensaver_background == "black" then
        background = Blitbuffer.COLOR_BLACK
    elseif self.screensaver_background == "white" then
        background = Blitbuffer.COLOR_WHITE
    elseif self.screensaver_background == "none" then
        background = nil
    end

    local message_height
    if self.show_message then
        -- Handle user settings & fallbacks, with that prefix mess on top...
        local screensaver_message = self.default_screensaver_message
        if G_reader_settings:has(self.prefix .. "screensaver_message") then
            screensaver_message = G_reader_settings:readSetting(self.prefix .. "screensaver_message")
        elseif G_reader_settings:has("screensaver_message") then
            screensaver_message = G_reader_settings:readSetting("screensaver_message")
        end
        -- If the message is set to the defaults (which is also the case when it's unset), prefer the event message if there is one.
        if screensaver_message == self.default_screensaver_message then
            if self.event_message then
                screensaver_message = self.event_message
                -- The overlay is only ever populated with the event message, and we only want to show it once ;).
                self.overlay_message = nil
            end
        end

        screensaver_message = self.ui.bookinfo:expandString(screensaver_message)
            or self.event_message or self.default_screensaver_message

        local message_container = G_reader_settings:readSetting(self.prefix .. "screensaver_message_container")
            or G_reader_settings:readSetting("screensaver_message_container")
        local vertical_percentage = G_reader_settings:readSetting(self.prefix .. "screensaver_message_vertical_position")
            or G_reader_settings:readSetting("screensaver_message_vertical_position", 50)
        local alpha_value = G_reader_settings:readSetting(self.prefix .. "screensaver_message_alpha")
            or G_reader_settings:readSetting("screensaver_message_alpha", 100)

        -- The only case where we *won't* cover the full-screen is when we only display a message and no background.
        if widget == nil and self.screensaver_background == "none" then
            covers_fullscreen = false
        end

        local message_widget, content_widget
        if message_container == "box" then
            content_widget = InfoMessage:new{
                text = screensaver_message,
                readonly = true,
                dismissable = false,
                force_one_line = true,
            }
            content_widget = content_widget.movable
        elseif message_container == "banner" then
            local face = Font:getFace("infofont")
            content_widget = TextBoxWidget:new{
                text = screensaver_message,
                face = face,
                width = screen_w,
                alignment = "center",
            }
        end
        -- Create a custom container that places the Message at the requested vertical coordinate.
        message_widget = CustomPositionContainer:new{
            widget = content_widget,
            -- although the computer expects 0 to be the top, users expect 0 to be the bottom
            vertical_position = 1 - (vertical_percentage / 100),
            alpha = alpha_value / 100,
        }
        -- Forward the height of the top message to the overlay widget
        if vertical_percentage > 80 then -- top of the screen
            message_height = message_widget.widget:getSize().h
        end

        -- Check if message_widget should be overlaid on another widget
        if message_widget then
            if widget then  -- We have a Screensaver widget
                -- Show message_widget on top of previously created widget
                widget = OverlapGroup:new{
                    dimen = {
                        w = screen_w,
                        h = screen_h,
                    },
                    widget,
                    message_widget,
                }
            else
                -- No previously created widget, so just show message widget
                widget = message_widget
            end
        end
    end

    if self.overlay_message then
        widget = addOverlayMessage(widget, message_height, self.overlay_message)
    end

    -- NOTE: Make sure InputContainer gestures are not disabled, to prevent stupid interactions with UIManager on close.
    UIManager:setIgnoreTouchInput(false)

    if widget then
        self.screensaver_widget = ScreenSaverWidget:new{
            widget = widget,
            background = background,
            covers_fullscreen = covers_fullscreen,
        }
        self.screensaver_widget.modal = true
        self.screensaver_widget.dithered = true

        UIManager:show(self.screensaver_widget, "full")
    end

    -- Setup the gesture lock through an additional invisible widget, so that it works regardless of the configuration.
    if with_gesture_lock then
        self.screensaver_lock_widget = ScreenSaverLockWidget:new{
            ui = self.ui,
            orig_dimen = orig_dimen,
        }

        -- It's flagged as modal, so it'll stay on top
        UIManager:show(self.screensaver_lock_widget)
    end
end

function Screensaver:close_widget()
    if self.screensaver_widget then
        UIManager:close(self.screensaver_widget)
    end
end

function Screensaver:close()
    if self.screensaver_widget == nil and self.screensaver_lock_widget == nil then
        -- When we *do* have a widget, this is handled by ScreenSaver(Lock)Widget:onCloseWidget ;).
        self:cleanup()
        return
    end

    local screensaver_delay = G_reader_settings:readSetting("screensaver_delay")
    local screensaver_delay_number = tonumber(screensaver_delay)
    if screensaver_delay_number then
        UIManager:scheduleIn(screensaver_delay_number, self.close_widget, self)
        self.delayed_close = true
    elseif screensaver_delay == "disable" then
        self:close_widget()
        -- NOTE: Notify platforms that race with the native system (e.g., Kindle or needsScreenRefreshAfterResume)
        --       that we've actually closed the widget *right now*.
        return true
    elseif screensaver_delay == "gesture" then
        -- ScreenSaverLockWidget's onResume handler should now paint the not-a-widget InfoMessage
        logger.dbg("waiting for screensaver unlock gesture")
    else
        logger.dbg("tap to exit from screensaver")
    end
end

function Screensaver:cleanup()
    self.show_message = nil
    self.screensaver_type = nil
    self.prefix = nil
    self.event_message = nil
    self.overlay_message = nil
    self.screensaver_background = nil

    self.image = nil
    self.image_file = nil

    self.delayed_close = nil
    self.screensaver_widget = nil

    self.screensaver_lock_widget = nil

    -- We run *after* the screensaver has been dismissed, so reset the Device flags
    Device.screen_saver_mode = false
    Device.screen_saver_lock = false
end

return Screensaver
