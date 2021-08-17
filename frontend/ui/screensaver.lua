local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local BookStatusWidget = require("ui/widget/bookstatuswidget")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local ImageWidget = require("ui/widget/imagewidget")
local Math = require("optmath")
local OverlapGroup = require("ui/widget/overlapgroup")
local ScreenSaverWidget = require("ui/widget/screensaverwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TopContainer = require("ui/widget/container/topcontainer")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

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
    screensaver_provider = {
        jpg  = true,
        jpeg = true,
        png  = true,
        gif  = true,
        tif  = true,
        tiff = true,
    },
    default_screensaver_message = _("Sleeping"),
}

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
        for entry in iter, dir_obj do
            if lfs.attributes(dir .. entry, "mode") == "file" then
                local extension = string.lower(string.match(entry, ".+%.([^.]+)") or "")
                if self.screensaver_provider[extension] then
                    i = i + 1
                    pics[i] = entry
                end
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
        local util = require("util")
        local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
        sec = util.secondsToClockDuration(user_duration_format, pages * average_time_per_page, true)
    end
    return sec
end

function Screensaver:expandSpecial(message, fallback)
    -- Expand special character sequences in given message.
    -- %p percentage read
    -- %c current page
    -- %t total pages
    -- %T document title
    -- %A document authors
    -- %S document series
    -- %h time left in chapter
    -- %H time left in document

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

    local ReaderUI = require("apps/reader/readerui")
    local ui = ReaderUI:_getRunningInstance()
    if ui and ui.document then
        -- If we have a ReaderUI instance, use it.
        local doc = ui.document
        currentpage = ui.view.state.page or currentpage
        totalpages = doc:getPageCount() or totalpages
        percent = Math.round((currentpage * 100) / totalpages)
        local props = doc:getProps()
        if props then
            title = props.title and props.title ~= "" and props.title or title
            authors = props.authors and props.authors ~= "" and props.authors or authors
            series = props.series and props.series ~= "" and props.series or series
        end
        time_left_chapter = self:_calcAverageTimeForPages(ui.toc:getChapterPagesLeft(currentpage) or doc:getTotalPagesLeft(currentpage))
        time_left_document = self:_calcAverageTimeForPages(doc:getTotalPagesLeft(currentpage))
    elseif DocSettings:hasSidecarFile(lastfile) then
        -- If there's no ReaderUI instance, but the file has sidecar data, use that
        local docinfo = DocSettings:open(lastfile)
        totalpages = docinfo.data.doc_pages or totalpages
        percent = docinfo.data.percent_finished or percent
        currentpage = Math.round(percent * totalpages)
        percent = Math.round(percent * 100)
        if docinfo.data.doc_props then
            title = docinfo.data.doc_props.title and docinfo.data.doc_props.title ~= "" and docinfo.data.doc_props.title or title
            authors = docinfo.data.doc_props.authors and docinfo.data.doc_props.authors ~= "" and docinfo.data.doc_props.authors or authors
            series = docinfo.data.doc_props.series and docinfo.data.doc_props.series ~= "" and docinfo.data.doc_props.series or series
        end
        -- Unable to set time_left_chapter and time_left_document without ReaderUI, so leave N/A
    end

    local replace = {
        ["%c"] = currentpage,
        ["%t"] = totalpages,
        ["%p"] = percent,
        ["%T"] = title,
        ["%A"] = authors,
        ["%S"] = series,
        ["%h"] = time_left_chapter,
        ["%H"] = time_left_document,
    }
    ret = ret:gsub("(%%%a)", replace)

    return ret
end

local function addOverlayMessage(widget, text)
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
    table.insert(buttons, {
        {
            text = _("Choose screensaver folder"),
            callback = function()
                UIManager:close(self.choose_dialog)
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
                UIManager:close(self.choose_dialog)
            end,
        }
    })
    local screensaver_dir = G_reader_settings:readSetting("screensaver_dir")
                         or DataStorage:getDataDir() .. "/screenshots/"
    self.choose_dialog = ButtonDialogTitle:new{
        title = T(_("Current screensaver image folder:\n%1"), BD.dirpath(screensaver_dir)),
        buttons = buttons
    }
    UIManager:show(self.choose_dialog)
end

function Screensaver:chooseFile(document_cover)
    local text = document_cover and _("Choose document cover") or _("Choose screensaver image")
    local buttons = {}
    table.insert(buttons, {
        {
            text = text,
            callback = function()
                UIManager:close(self.choose_dialog)
                local util = require("util")
                local PathChooser = require("ui/widget/pathchooser")
                local path_chooser = PathChooser:new{
                    select_directory = false,
                    select_file = true,
                    file_filter = function(filename)
                        local suffix = util.getFileNameSuffix(filename)
                        if document_cover and DocumentRegistry:hasProvider(filename) then
                            return true
                        elseif self.screensaver_provider[suffix] then
                            return true
                        end
                    end,
                    detailed_file_info = true,
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
                UIManager:close(self.choose_dialog)
            end,
        }
    })
    local screensaver_image = G_reader_settings:readSetting("screensaver_image")
                           or DataStorage:getDataDir() .. "/resources/koreader.png"
    local screensaver_document_cover = G_reader_settings:readSetting("screensaver_document_cover")
    local title = document_cover and T(_("Current screensaver document cover:\n%1"), BD.filepath(screensaver_document_cover))
        or T(_("Current screensaver image:\n%1"), BD.filepath(screensaver_image))
    self.choose_dialog = ButtonDialogTitle:new{
        title = title,
        buttons = buttons
    }
    UIManager:show(self.choose_dialog)
end

function Screensaver:isExcluded()
    local ReaderUI = require("apps/reader/readerui")
    local ui = ReaderUI:_getRunningInstance()
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
    self.input_dialog = InputDialog:new{
        title = "Screensaver message",
        description = _("Enter the message to be displayed by the screensaver. The following escape sequences can be used:\n  %p percentage read\n  %c current page number\n  %t total number of pages\n  %T title\n  %A authors\n  %S series\n  %h time left in chapter\n  %H time left in document"),
        input = screensaver_message,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(self.input_dialog)
                    end,
                },
                {
                    text = _("Set message"),
                    is_enter_default = true,
                    callback = function()
                        G_reader_settings:saveSetting("screensaver_message", self.input_dialog:getInputText())
                        UIManager:close(self.input_dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(self.input_dialog)
    self.input_dialog:onShowKeyboard()
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

function Screensaver:setup(event, fallback_message)
    self.show_message = G_reader_settings:isTrue("screensaver_show_message")
    self.screensaver_type = G_reader_settings:readSetting("screensaver_type")
    local screensaver_img_background = G_reader_settings:readSetting("screensaver_img_background")
    local screensaver_msg_background = G_reader_settings:readSetting("screensaver_msg_background")

    -- These 2 (optional) parameters are to support poweroff and reboot actions on Kobo (c.f., UIManager)
    self.prefix = event and event .. "_" or "" -- "", "poweroff_" or "reboot_"
    self.fallback_message = fallback_message
    self.overlay_message = nil
    if G_reader_settings:has(self.prefix .. "screensaver_type") then
        self.screensaver_type = G_reader_settings:readSetting(self.prefix .. "screensaver_type")
    else
        if event and G_reader_settings:isFalse("screensaver_hide_fallback_msg") then
            -- Display the provided fallback_message over the screensaver,
            -- so the user can distinguish between suspend (no overlay),
            -- and reboot/poweroff (overlaid message).
            self.overlay_message = self.fallback_message
        end
    end

    -- Reset state
    self.lastfile = nil
    self.image = nil
    self.image_file = nil

    -- Check lastfile and setup the requested mode's resources, or a fallback mode if the required resources are unavailable.
    local ReaderUI = require("apps/reader/readerui")
    local ui = ReaderUI:_getRunningInstance()
    self.lastfile = G_reader_settings:readSetting("lastfile")
    if self.screensaver_type == "document_cover" then
        -- Set lastfile to the document of which we want to show the cover.
        self.lastfile = G_reader_settings:readSetting("screensaver_document_cover")
        self.screensaver_type = "cover"
    end
    if self.screensaver_type == "cover" then
        self.lastfile = self.lastfile ~= nil and self.lastfile or G_reader_settings:readSetting("lastfile")
        local excluded
        if DocSettings:hasSidecarFile(self.lastfile) then
            local doc_settings
            if ui and ui.doc_settings then
                doc_settings = ui.doc_settings
            else
                doc_settings = DocSettings:open(self.lastfile)
            end
            excluded = doc_settings:isTrue("exclude_screensaver")
        else
            -- No DocSetting, not excluded
            excluded = false
        end
        if not excluded then
            if self.lastfile and lfs.attributes(self.lastfile, "mode") == "file" then
                if ui and ui.document then
                    local doc = ui.document
                    self.image = doc:getCoverPageImage()
                else
                    local doc = DocumentRegistry:openDocument(self.lastfile)
                    if doc.loadDocument then -- CreDocument
                        doc:loadDocument(false) -- load only metadata
                    end
                    self.image = doc:getCoverPageImage()
                    doc:close()
                end
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
        if self.lastfile and lfs.attributes(self.lastfile, "mode") == "file" then
            if not ui then
                self.screensaver_type = "disable"
                self.show_message = true
            end
        else
            self.screensaver_type = "disable"
            self.show_message = true
        end
    end
    if self.screensaver_type == "random_image" then
        local screensaver_dir = G_reader_settings:readSetting(self.prefix .. "screensaver_dir")
                             or G_reader_settings:readSetting("screensaver_dir")
        self.image_file = self:_getRandomImage(screensaver_dir)
        if self.image_file == nil then
            self.screensaver_type = "disable"
            self.show_message = true
        end
    end
    if self.screensaver_type == "image_file" then
        self.image_file = G_reader_settings:readSetting(self.prefix .. "screensaver_image")
                       or G_reader_settings:readSetting("screensaver_image")
        if self.image_file == nil or lfs.attributes(self.image_file, "mode") ~= "file" then
            self.screensaver_type = "disable"
            self.show_message = true
        end
    end
    if self.screensaver_type == "readingprogress" then
        -- This is implemented by the Statistics plugin
        if Screensaver.getReaderProgress == nil then
            self.screensaver_type = "disable"
            self.show_message = true
        end
    end

    -- Use the right background setting depending on the effective mode, now that fallbacks have kicked in.
    if self:modeIsImage() then
        self.screensaver_background = screensaver_img_background
    else
        self.screensaver_background = screensaver_msg_background
    end
end

function Screensaver:show()
    if self.screensaver_widget then
        UIManager:close(self.screensaver_widget)
        self.screensaver_widget = nil
    end

    -- In as-is mode with no message and no overlay, we've got nothing to show :)
    if self.screensaver_type == "disable" and not self.show_message and not self.overlay_message then
        return
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
        }
    elseif self.screensaver_type == "bookstatus" then
        local ReaderUI = require("apps/reader/readerui")
        local ui = ReaderUI:_getRunningInstance()
        local doc = ui.document
        local doc_settings = ui.doc_settings
        widget = BookStatusWidget:new{
            thumbnail = doc:getCoverPageImage(),
            props = doc:getProps(),
            document = doc,
            settings = doc_settings,
            view = ui.view,
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

    if self.show_message then
        -- Handle user settings & fallbacks, with that prefix mess on top...
        local screensaver_message
        if G_reader_settings:has(self.prefix .. "screensaver_message") then
            screensaver_message = G_reader_settings:readSetting(self.prefix .. "screensaver_message")
        else
            if G_reader_settings:has("screensaver_message") then
                -- We prefer the global user setting to the event's fallback message.
                screensaver_message = G_reader_settings:readSetting("screensaver_message")
            else
                screensaver_message = self.fallback_message or self.default_screensaver_message
            end
        end
        -- NOTE: Only attempt to expand if there are special characters in the message.
        if screensaver_message:find("%%") then
            screensaver_message = self:expandSpecial(screensaver_message, self.fallback_message or self.default_screensaver_message)
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
        end

        -- No overlay needed as we just displayed *a* message (not necessarily the event's, though).
        self.overlay_message = nil

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
        widget = addOverlayMessage(widget, self.overlay_message)
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
end

function Screensaver:close()
    if self.screensaver_widget == nil then
        return
    end

    local screensaver_delay = G_reader_settings:readSetting("screensaver_delay")
    local screensaver_delay_number = tonumber(screensaver_delay)
    if screensaver_delay_number then
        UIManager:scheduleIn(screensaver_delay_number, function()
            logger.dbg("close screensaver")
            if self.screensaver_widget then
                UIManager:close(self.screensaver_widget)
                self.screensaver_widget = nil
            end
        end)
    elseif screensaver_delay == "disable" then
        logger.dbg("close screensaver")
        if self.screensaver_widget then
            UIManager:close(self.screensaver_widget)
            self.screensaver_widget = nil
        end
    else
        logger.dbg("tap to exit from screensaver")
    end
end

return Screensaver
