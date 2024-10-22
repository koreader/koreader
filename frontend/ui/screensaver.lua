local Blitbuffer = require("ffi/blitbuffer")
local BookStatusWidget = require("ui/widget/bookstatuswidget")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Device = require("device")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local ImageWidget = require("ui/widget/imagewidget")
local Math = require("optmath")
local OverlapGroup = require("ui/widget/overlapgroup")
local RenderImage = require("ui/renderimage")
local ScreenSaverWidget = require("ui/widget/screensaverwidget")
local ScreenSaverLockWidget = require("ui/widget/screensaverlockwidget")
local SpinWidget = require("ui/widget/spinwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TopContainer = require("ui/widget/container/topcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local datetime = require("datetime")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
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
if G_reader_settings:hasNot("screensaver_message_position") then
    G_reader_settings:saveSetting("screensaver_message_position", "middle")
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
    return filemanagerutil.getRandomFile(dir, match_func)
end

-- This is implemented by the Statistics plugin
function Screensaver:getAvgTimePerPage()
    return
end

function Screensaver:_calcAverageTimeForPages(pages)
    local sec = _("N/A")
    local average_time_per_page = self:getAvgTimePerPage()

    -- Compare average_time_per_page against itself to make sure it's not nan
    if average_time_per_page and average_time_per_page == average_time_per_page and pages then
        local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
        sec = datetime.secondsToClockDuration(user_duration_format, pages * average_time_per_page, true)
    end
    return sec
end

function Screensaver:expandSpecial(message, fallback)
    -- Expand special character sequences in given message.
    -- %T document title
    -- %A document authors
    -- %S document series
    -- %c current page (if there are hidden flows, current page in current flow)
    -- %t total pages (if there are hidden flows, total pages in current flow)
    -- %p percentage read (if there are hidden flows, percentage read of current flow)
    -- %h time left in chapter
    -- %H time left in document (if there are hidden flows, time left in current flow)
    -- %b battery level

    if G_reader_settings:hasNot("lastfile") then
        return fallback
    end

    local ret = message
    local lastfile = G_reader_settings:readSetting("lastfile")

    local totalpages = 0
    local percent = 0
    local currentpage = 0
    local title = _("N/A")
    local authors = _("N/A")
    local series = _("N/A")
    local time_left_chapter = _("N/A")
    local time_left_document = _("N/A")
    local batt_lvl = _("N/A")
    local props

    local ReaderUI = require("apps/reader/readerui")
    local ui = ReaderUI.instance
    if ui and ui.document then
        -- If we have a ReaderUI instance, use it.
        local doc = ui.document
        if doc:hasHiddenFlows() then
            local currentpageAll = ui.view.state.page or currentpage
            currentpage = doc:getPageNumberInFlow(ui.view.state.page or currentpageAll)
            totalpages = doc:getTotalPagesInFlow(doc:getPageFlow(currentpageAll))
            time_left_chapter = self:_calcAverageTimeForPages(ui.toc:getChapterPagesLeft(currentpageAll) or (totalpages - currentpage))
            time_left_document = self:_calcAverageTimeForPages(totalpages - currentpage)
        else
            currentpage = ui.view.state.page or currentpage
            totalpages = doc:getPageCount() or totalpages
            time_left_chapter = self:_calcAverageTimeForPages(ui.toc:getChapterPagesLeft(currentpage) or doc:getTotalPagesLeft(currentpage))
            time_left_document = self:_calcAverageTimeForPages(doc:getTotalPagesLeft(currentpage))
        end
        if currentpage == 1 then
            percent = 0
        elseif currentpage == totalpages then
            percent = 100
        else
            percent = Math.round(Math.clamp(((currentpage * 100) / totalpages), 1, 99))
        end
        props = ui.doc_props
    elseif DocSettings:hasSidecarFile(lastfile) then
        -- If there's no ReaderUI instance, but the file has sidecar data, use that
        local doc_settings = DocSettings:open(lastfile)
        totalpages = doc_settings:readSetting("doc_pages") or totalpages
        percent = doc_settings:readSetting("percent_finished") or percent
        currentpage = Math.round(percent * totalpages)
        if currentpage == 1 then
            percent = 0
        elseif currentpage == totalpages then
            percent = 100
        else
            percent = Math.round(Math.clamp(percent * 100, 1, 99))
        end
        props = FileManagerBookInfo.extendProps(doc_settings:readSetting("doc_props"), lastfile)
        -- Unable to set time_left_chapter and time_left_document without ReaderUI, so leave N/A
    end
    if props then
        title = props.display_title
        if props.authors then
            authors = props.authors
        end
        if props.series then
            series = props.series
            if props.series_index then
                series = series .. " #" .. props.series_index
            end
        end
    end
    if Device:hasBattery() then
        local powerd = Device:getPowerDevice()
        if Device:hasAuxBattery() and powerd:isAuxBatteryConnected() then
            batt_lvl = powerd:getCapacity() + powerd:getAuxCapacity()
        else
            batt_lvl = powerd:getCapacity()
        end
    end

    local replace = {
        ["%T"] = title,
        ["%A"] = authors,
        ["%S"] = series,
        ["%c"] = currentpage,
        ["%t"] = totalpages,
        ["%p"] = percent,
        ["%h"] = time_left_chapter,
        ["%H"] = time_left_document,
        ["%b"] = batt_lvl,
    }
    ret = ret:gsub("(%%%a)", replace)

    return ret
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

function Screensaver:chooseFolder()
    local title_header = _("Current random image folder:")
    local current_path = G_reader_settings:readSetting("screensaver_dir")
    local caller_callback = function(path)
        G_reader_settings:saveSetting("screensaver_dir", path)
    end
    filemanagerutil.showChooseDialog(title_header, caller_callback, current_path)
end

function Screensaver:chooseFile()
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

function Screensaver:isExcluded()
    local ReaderUI = require("apps/reader/readerui")
    local ui = ReaderUI.instance
    if ui and ui.doc_settings then
        local doc_settings = ui.doc_settings
        return doc_settings:isTrue("exclude_screensaver")
    else
        if G_reader_settings:hasNot("lastfile") then
            return false
        end

        local lastfile = G_reader_settings:readSetting("lastfile")
        if DocSettings:hasSidecarFile(lastfile) then
            local doc_settings = DocSettings:open(lastfile)
            return doc_settings:isTrue("exclude_screensaver")
        else
            -- No DocSetting, not excluded
            return false
        end
    end
end

function Screensaver:setMessage()
    local InputDialog = require("ui/widget/inputdialog")
    local screensaver_message = G_reader_settings:readSetting("screensaver_message")
                             or self.default_screensaver_message
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Sleep screen message"),
        description = _([[
Enter a custom message to be displayed on the sleep screen. The following escape sequences are available:
  %T title
  %A author(s)
  %S series
  %c current page number
  %t total page number
  %p percentage read
  %h time left in chapter
  %H time left in document
  %b battery level]]),
        input = screensaver_message,
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
                    text = _("Set message"),
                    is_enter_default = true,
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
    local ReaderUI = require("apps/reader/readerui")
    local ui = ReaderUI.instance
    local lastfile = G_reader_settings:readSetting("lastfile")
    if self.screensaver_type == "document_cover" then
        -- Set lastfile to the document of which we want to show the cover.
        lastfile = G_reader_settings:readSetting("screensaver_document_cover")
        self.screensaver_type = "cover"
    end
    if self.screensaver_type == "cover" then
        local excluded
        if lastfile and DocSettings:hasSidecarFile(lastfile) then
            local doc_settings
            if ui and ui.doc_settings then
                doc_settings = ui.doc_settings
            else
                doc_settings = DocSettings:open(lastfile)
            end
            excluded = doc_settings:isTrue("exclude_screensaver")
        else
            -- No DocSetting, not excluded
            excluded = false
        end
        if not excluded then
            if lastfile and lfs.attributes(lastfile, "mode") == "file" then
                if DocumentRegistry:isImageFile(lastfile) then
                    self.image_file = lastfile
                else
                    self.image = FileManagerBookInfo:getCoverImage(ui and ui.document, lastfile)
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
        if not (ui and ui.doc_settings and ui.doc_settings:nilOrFalse("exclude_screensaver")) then
            self.screensaver_type = "random_image"
        end
    end
    if self.screensaver_type == "readingprogress" then
        -- This is implemented by the Statistics plugin
        if Screensaver.getReaderProgress == nil then
            self.screensaver_type = "random_image"
        end
    end
    if self.screensaver_type == "disable" then
        if ui and ui.doc_settings and ui.doc_settings:isTrue("exclude_screensaver") then
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
    -- Notify Device methods that we're in screen saver mode, so they know whether to suspend or resume on Power events.
    Device.screen_saver_mode = true

    -- Check if we requested a lock gesture
    local with_gesture_lock = Device:isTouchDevice() and G_reader_settings:readSetting("screensaver_delay") == "gesture"

    -- In as-is mode with no message, no overlay and no lock, we've got nothing to show :)
    if self.screensaver_type == "disable" and not self.show_message and not self.overlay_message and not with_gesture_lock then
        return
    end

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
        else
            Device.orig_rotation_mode = nil
        end

        -- On eInk, if we're using a screensaver mode that shows an image,
        -- flash the screen to white first, to eliminate ghosting.
        if Device:hasEinkScreen() and self:modeIsImage() then
            if self:withBackground() then
                Screen:clear()
            end
            Screen:refreshFull(0, 0, Screen:getWidth(), Screen:getHeight())

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
            width = Screen:getWidth(),
            height = Screen:getHeight(),
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
                    widget_settings.image = RenderImage:renderCheckerboard(Screen:getWidth(), Screen:getHeight(), Screen.bb:getType())
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
        local ReaderUI = require("apps/reader/readerui")
        widget = BookStatusWidget:new{
            ui = ReaderUI.instance,
            readonly = true,
        }
    elseif self.screensaver_type == "readingprogress" then
        widget = Screensaver.getReaderProgress()
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

        -- NOTE: Only attempt to expand if there are special characters in the message.
        if screensaver_message:find("%%") then
            screensaver_message = self:expandSpecial(screensaver_message, self.event_message or self.default_screensaver_message)
        end

        local message_pos
        if G_reader_settings:has(self.prefix .. "screensaver_message_position") then
            message_pos = G_reader_settings:readSetting(self.prefix .. "screensaver_message_position")
        else
            message_pos = G_reader_settings:readSetting("screensaver_message_position")
        end

        -- The only case where we *won't* cover the full-screen is when we only display a message and no background.
        if widget == nil and self.screensaver_background == "none" then
            covers_fullscreen = false
        end

        local message_widget
        if message_pos == "middle" then
            message_widget = InfoMessage:new{
                text = screensaver_message,
                readonly = true,
                dismissable = false,
            }
        else
            local face = Font:getFace("infofont")
            local container
            if message_pos == "bottom" then
                container = BottomContainer
            else
                container = TopContainer
            end

            local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
            message_widget = container:new{
                dimen = Geom:new{
                    w = screen_w,
                    h = screen_h,
                },
                TextBoxWidget:new{
                    text = screensaver_message,
                    face = face,
                    width = screen_w,
                    alignment = "center",
                }
            }

            -- Forward the height of the top message to the overlay widget
            if message_pos == "top" then
                message_height = message_widget[1]:getSize().h
            end
        end

        -- Check if message_widget should be overlaid on another widget
        if message_widget then
            if widget then  -- We have a Screensaver widget
                -- Show message_widget on top of previously created widget
                widget = OverlapGroup:new{
                    dimen = {
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
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
        self.screensaver_lock_widget = ScreenSaverLockWidget:new{}

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
