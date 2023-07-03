local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
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
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen
local T = ffiUtil.template

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

function Screensaver:_getRandomImage(dir)
    if not dir then
        return nil
    end

    if string.sub(dir, string.len(dir)) ~= "/" then
       dir = dir .. "/"
    end
    local pics = {}
    local i = 0
    math.randomseed(os.time())
    local ok, iter, dir_obj = pcall(lfs.dir, dir)
    if ok then
        for f in iter, dir_obj do
            -- Always ignore macOS resource forks, too.
            if lfs.attributes(dir .. f, "mode") == "file" and not util.stringStartsWith(f, "._")
                    and DocumentRegistry:isImageFile(f) then
                i = i + 1
                pics[i] = f
            end
        end
        if i == 0 then
            return nil
        end
    else
        return nil
    end

    return dir .. pics[math.random(i)]
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
        percent = Math.round((currentpage * 100) / totalpages)
        local props = doc:getProps()
        if props then
            title = props.title and props.title ~= "" and props.title or title
            authors = props.authors and props.authors ~= "" and props.authors or authors
            series = props.series and props.series ~= "" and props.series or series
        end
    elseif DocSettings:hasSidecarFile(lastfile) then
        -- If there's no ReaderUI instance, but the file has sidecar data, use that
        local doc_settings = DocSettings:open(lastfile)
        totalpages = doc_settings:readSetting("doc_pages") or totalpages
        percent = doc_settings:readSetting("percent_finished") or percent
        currentpage = Math.round(percent * totalpages)
        percent = Math.round(percent * 100)
        local doc_props = doc_settings:readSetting("doc_props")
        if doc_props then
            title = doc_props.title and doc_props.title ~= "" and doc_props.title or title
            authors = doc_props.authors and doc_props.authors ~= "" and doc_props.authors or authors
            series = doc_props.series and doc_props.series ~= "" and doc_props.series or series
        end
        -- Unable to set time_left_chapter and time_left_document without ReaderUI, so leave N/A
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
    local buttons = {}
    local choose_dialog
    table.insert(buttons, {
        {
            text = _("Choose screensaver folder"),
            callback = function()
                UIManager:close(choose_dialog)
                require("ui/downloadmgr"):new{
                    onConfirm = function(path)
                        logger.dbg("set screensaver directory to", path)
                        G_reader_settings:saveSetting("screensaver_dir", path)
                        UIManager:show(InfoMessage:new{
                            text = T(_("Screensaver folder set to:\n%1"), BD.dirpath(path)),
                            timeout = 3,
                        })
                    end,
                }:chooseDir()
            end,
        }
    })
    table.insert(buttons, {
        {
            text = _("Close"),
            callback = function()
                UIManager:close(choose_dialog)
            end,
        }
    })
    local screensaver_dir = G_reader_settings:readSetting("screensaver_dir")
                         or _("N/A")
    choose_dialog = ButtonDialog:new{
        title = T(_("Current screensaver image folder:\n%1"), BD.dirpath(screensaver_dir)),
        buttons = buttons
    }
    UIManager:show(choose_dialog)
end

function Screensaver:chooseFile(document_cover)
    local text = document_cover and _("Choose document cover") or _("Choose screensaver image")
    local buttons = {}
    local choose_dialog
    table.insert(buttons, {
        {
            text = text,
            callback = function()
                UIManager:close(choose_dialog)
                local PathChooser = require("ui/widget/pathchooser")
                local path_chooser = PathChooser:new{
                    select_directory = false,
                    file_filter = function(filename)
                        return document_cover and DocumentRegistry:hasProvider(filename)
                                               or DocumentRegistry:isImageFile(filename)
                    end,
                    path = self.root_path,
                    onConfirm = function(file_path)
                        if document_cover then
                            G_reader_settings:saveSetting("screensaver_document_cover", file_path)
                            UIManager:show(InfoMessage:new{
                                text = T(_("Screensaver document cover set to:\n%1"), BD.filepath(file_path)),
                                timeout = 3,
                            })
                        else
                            G_reader_settings:saveSetting("screensaver_image", file_path)
                            UIManager:show(InfoMessage:new{
                                text = T(_("Screensaver image set to:\n%1"), BD.filepath(file_path)),
                                timeout = 3,
                            })
                        end
                    end
                }
                UIManager:show(path_chooser)
            end,
        }
    })
    table.insert(buttons, {
        {
            text = _("Close"),
            callback = function()
                UIManager:close(choose_dialog)
            end,
        }
    })
    local screensaver_image = G_reader_settings:readSetting("screensaver_image")
                           or _("N/A")
    local screensaver_document_cover = G_reader_settings:readSetting("screensaver_document_cover")
                                    or _("N/A")
    local title = document_cover and T(_("Current screensaver document cover:\n%1"), BD.filepath(screensaver_document_cover))
        or T(_("Current screensaver image:\n%1"), BD.filepath(screensaver_image))
    choose_dialog = ButtonDialog:new{
        title = title,
        buttons = buttons
    }
    UIManager:show(choose_dialog)
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
        title = _("Screensaver message"),
        description = _([[
Enter the message to be displayed by the screensaver. The following escape sequences can be used:
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
        or self.screensaver_type == "image_file"
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
        lastfile = lastfile ~= nil and lastfile or G_reader_settings:readSetting("lastfile")
        local excluded
        if DocSettings:hasSidecarFile(lastfile) then
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
                self.image = FileManagerBookInfo:getCoverImage(ui and ui.document, lastfile)
                if self.image == nil then
                    self.screensaver_type = "random_image"
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
        if not ui or not lastfile or lfs.attributes(lastfile, "mode") ~= "file" or (ui.doc_settings and ui.doc_settings:isTrue("exclude_screensaver")) then
            self.screensaver_type = "random_image"
        end
    end
    if self.screensaver_type == "image_file" then
        self.image_file = G_reader_settings:readSetting(self.prefix .. "screensaver_image")
                       or G_reader_settings:readSetting("screensaver_image")
        if self.image_file == nil or lfs.attributes(self.image_file, "mode") ~= "file" then
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
        self.image_file = self:_getRandomImage(screensaver_dir) or "resources/koreader.png" -- Fallback image
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

    -- We mostly always suspend in Portrait/Inverted Portrait mode...
    -- ... except when we just show an InfoMessage or when the screensaver
    -- is disabled, as it plays badly with Landscape mode (c.f., #4098 and #5290).
    -- We also exclude full-screen widgets that work fine in Landscape mode,
    -- like ReadingProgress and BookStatus (c.f., #5724)
    if self:modeExpectsPortrait() then
        Device.orig_rotation_mode = Screen:getRotationMode()
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
            Screen:refreshFull()

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
    if self.screensaver_type == "cover" then
        widget = ImageWidget:new{
            image = self.image,
            image_disposable = true,
            width = Screen:getWidth(),
            height = Screen:getHeight(),
            scale_factor = G_reader_settings:isFalse("screensaver_stretch_images") and 0 or nil,
            stretch_limit_percentage = G_reader_settings:readSetting("screensaver_stretch_limit_percentage"),
        }
    elseif self.screensaver_type == "bookstatus" then
        local ReaderUI = require("apps/reader/readerui")
        local ui = ReaderUI.instance
        local doc = ui.document
        local doc_settings = ui.doc_settings
        widget = BookStatusWidget:new{
            thumbnail = FileManagerBookInfo:getCoverImage(doc),
            props = doc:getProps(),
            document = doc,
            settings = doc_settings,
            ui = ui,
            readonly = true,
        }
    elseif self.screensaver_type == "random_image" or self.screensaver_type == "image_file" then
        widget = ImageWidget:new{
            file = self.image_file,
            file_do_cache = false,
            alpha = true,
            width = Screen:getWidth(),
            height = Screen:getHeight(),
            scale_factor = G_reader_settings:isFalse("screensaver_stretch_images") and 0 or nil,
            stretch_limit_percentage = G_reader_settings:readSetting("screensaver_stretch_limit_percentage"),
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
        local screensaver_message
        if G_reader_settings:has(self.prefix .. "screensaver_message") then
            screensaver_message = G_reader_settings:readSetting(self.prefix .. "screensaver_message")
        else
            if G_reader_settings:has("screensaver_message") then
                screensaver_message = G_reader_settings:readSetting("screensaver_message")
            else
                -- In the absence of a custom message, use the event message if any, barring that, use the default message.
                if self.event_message then
                    screensaver_message = self.event_message
                    -- The overlay is only ever populated with the event message, and we only want to show it once ;).
                    self.overlay_message = nil
                else
                    screensaver_message = self.default_screensaver_message
                end
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
                -- No prevously created widget, so just show message widget
                widget = message_widget
            end
        end
    end

    if self.overlay_message then
        widget = addOverlayMessage(widget, message_height, self.overlay_message)
    end

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
        if self.screensaver_lock_widget then
            self.screensaver_lock_widget:showWaitForGestureMessage()
        end
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
