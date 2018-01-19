local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local BookStatusWidget = require("ui/widget/bookstatuswidget")
local Device = require("device")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local ImageWidget = require("ui/widget/imagewidget")
local ScreenSaverWidget = require("ui/widget/screensaverwidget")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

local default_screensaver_message = _("Sleeping")
local Screensaver = {}

local function getRandomImage(dir)
    if string.sub(dir, string.len(dir)) ~= "/" then
       dir = dir .. "/"
    end
    local pics = {}
    local i = 0
    math.randomseed(os.time())
    for entry in lfs.dir(dir) do
        if lfs.attributes(dir .. entry, "mode") == "file" then
            local extension =
                string.lower(string.match(entry, ".+%.([^.]+)") or "")
            if extension == "jpg"
            or extension == "jpeg"
            or extension == "png" then
                i = i + 1
                pics[i] = entry
            end
        end
    end
    if i == 0 then
        return nil
    end
    return dir .. pics[math.random(i)]
end

function Screensaver:chooseFolder()
    local buttons = {}
    table.insert(buttons, {
        {
            text = _("Choose screensaver directory by long-pressing"),
            callback = function()
                UIManager:close(self.choose_dialog)
                require("ui/downloadmgr"):new{
                    title = _("Choose screensaver directory"),
                    onConfirm = function(path)
                        logger.dbg("set screensaver directory to", path)
                        G_reader_settings:saveSetting("screensaver_dir", path)
                        UIManager:show(InfoMessage:new{
                            text = T(_("Screensaver directory set to:\n%1"), path),
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
    if screensaver_dir == nil then
        local DataStorage = require("datastorage")
        screensaver_dir = DataStorage:getDataDir() .. "/screenshots/"
    end
    self.choose_dialog = ButtonDialogTitle:new{
        title = T(_("Current screensaver image directory:\n %1"), screensaver_dir),
        buttons = buttons
    }
    UIManager:show(self.choose_dialog)
end

function Screensaver:stretchImages()
    return G_reader_settings:isTrue("screensaver_stretch_images")
end

function Screensaver:whiteBackground()
    return G_reader_settings:isTrue("screensaver_white_background")
end

function Screensaver:excluded()
    local lastfile = G_reader_settings:readSetting("lastfile")
    local exclude_ss = false -- consider it not excluded if there's no docsetting
    if DocSettings:hasSidecarFile(lastfile) then
        local doc_settings = DocSettings:open(lastfile)
        exclude_ss = doc_settings:readSetting("exclude_screensaver")
        doc_settings:close()
    end
    return exclude_ss or false
end

function Screensaver:setMessage()
    local InputDialog = require("ui/widget/inputdialog")
    local screensaver_message = G_reader_settings:readSetting("screensaver_message")
    if screensaver_message == nil then
        screensaver_message = default_screensaver_message
    end
    self.input_dialog = InputDialog:new{
        title = "Screensaver message",
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
    self.input_dialog:onShowKeyboard()
    UIManager:show(self.input_dialog)
end

function Screensaver:show(event, fallback_message)
    -- These 2 (optional) parameters are to support poweroff and reboot actions
    -- on Kobo (see uimanager.lua)
    if self.left_msg then
        UIManager:close(self.left_msg)
        self.left_msg = nil
    end
    local overlay_message
    local prefix = event and event.."_" or "" -- "", "poweroff_" or "reboot_"
    local screensaver_type = G_reader_settings:readSetting(prefix.."screensaver_type")
    if prefix and not screensaver_type then
        -- No manually added setting for poweroff/reboot, fallback to using the
        -- same settings as for suspend that could be set via menus
        screensaver_type = G_reader_settings:readSetting("screensaver_type")
        prefix = ""
        -- And display fallback_message over the common screensaver,
        -- so user can distinguish between suspend (no message) and
        -- poweroff (overlay message)
        overlay_message = fallback_message
    end
    if screensaver_type == nil then
        screensaver_type = "message"
    end
    if screensaver_type == "disable" then
        return
    end
    local widget = nil
    local background = Blitbuffer.COLOR_WHITE
    if screensaver_type == "cover" then
        local lastfile = G_reader_settings:readSetting("lastfile")
        local exclude = false -- consider it not excluded if there's no docsetting
        if DocSettings:hasSidecarFile(lastfile) then
            local doc_settings = DocSettings:open(lastfile)
            exclude = doc_settings:readSetting("exclude_screensaver")
            doc_settings:close()
        end
        if exclude ~= true then
            if lfs.attributes(lastfile, "mode") == "file" then
                local doc = DocumentRegistry:openDocument(lastfile)
                local image = doc:getCoverPageImage()
                doc:close()
                if image ~= nil then
                    widget = ImageWidget:new{
                        image = image,
                        image_disposable = true,
                        alpha = true,
                        height = Screen:getHeight(),
                        width = Screen:getWidth(),
                        scale_factor = not self:stretchImages() and 0 or nil,
                    }
                    if not self:whiteBackground() then
                        background = Blitbuffer.COLOR_BLACK
                    end
                else
                    screensaver_type = "random_image"
                end
            else
                screensaver_type = "random_image"
            end
        else  --fallback to random images if this book cover is excluded
            screensaver_type = "random_image"
        end
    end
    if screensaver_type == "bookstatus" then
        local lastfile = G_reader_settings:readSetting("lastfile")
        if lfs.attributes(lastfile, "mode") == "file" then
            local doc = DocumentRegistry:openDocument(lastfile)
            local doc_settings = DocSettings:open(lastfile)
            local instance = require("apps/reader/readerui"):_getRunningInstance()
            if instance ~= nil then
                widget = BookStatusWidget:new {
                    thumbnail = doc:getCoverPageImage(),
                    props = doc:getProps(),
                    document = doc,
                    settings = doc_settings,
                    view = instance.view,
                    readonly = true,
                }
            else
                screensaver_type = "message"
            end
            doc:close()
            doc_settings:close()
        else
            screensaver_type = "message"
        end
    end
    if screensaver_type == "random_image" then
        local screensaver_dir = G_reader_settings:readSetting(prefix.."screensaver_dir")
        if screensaver_dir == nil then
            local DataStorage = require("datastorage")
            screensaver_dir = DataStorage:getDataDir() .. "/screenshots/"
        end
        local image_file = getRandomImage(screensaver_dir)
        if image_file == nil then
            screensaver_type = "message"
        else
            widget = ImageWidget:new{
                file = image_file,
                file_do_cache = false,
                alpha = true,
                height = Screen:getHeight(),
                width = Screen:getWidth(),
                scale_factor = not self:stretchImages() and 0 or nil,
            }
            if not self:whiteBackground() then
                background = Blitbuffer.COLOR_BLACK
            end
        end
    end
    if screensaver_type == "readingprogress" then
        if Screensaver.getReaderProgress ~= nil then
            widget = Screensaver.getReaderProgress()
        else
            screensaver_type = "message"
        end
    end
    if screensaver_type == "message" then
        local screensaver_message = G_reader_settings:readSetting(prefix.."screensaver_message")
        if not self:whiteBackground() then
            background = nil -- no background filling, let book text visible
        end
        if screensaver_message == nil then
            screensaver_message = fallback_message or default_screensaver_message
        end
        widget = InfoMessage:new{
            text = screensaver_message,
            readonly = true,
        }
        -- No overlay needed as we just displayed the message
        overlay_message = nil
    end

    if overlay_message then
        widget = self:addOverlayMessage(widget, overlay_message)
    end

    if widget then
        self.left_msg = ScreenSaverWidget:new{
            widget = widget,
            background = background,
        }
        self.left_msg.modal = true
        -- refresh whole screen for other types
        UIManager:show(self.left_msg, "full")
    end
end

function Screensaver:close()
    if self.left_msg == nil then return end
    local screensaver_delay = G_reader_settings:readSetting("screensaver_delay")
    local screensaver_delay_number = tonumber(screensaver_delay)
    if screensaver_delay_number then
        UIManager:scheduleIn(screensaver_delay_number, function()
            logger.dbg("close screensaver")
            if self.left_msg then
                UIManager:close(self.left_msg)
                UIManager:setDirty("all", "full")
                self.left_msg = nil
            end
        end)
    elseif screensaver_delay == "disable" or screensaver_delay == nil then
        logger.dbg("close screensaver")
        if self.left_msg then
            UIManager:close(self.left_msg)
            self.left_msg = nil
        end
    else
        logger.dbg("tap to exit from screensaver")
    end
end

function Screensaver:addOverlayMessage(widget, text)
    local Font = require("ui/font")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local RenderText = require("ui/rendertext")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local Size = require("ui/size")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local TextWidget = require("ui/widget/textwidget")

    local face = Font:getFace("infofont")
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()

    local textw
    -- Don't make our message reach full screen width
    local tsize = RenderText:sizeUtf8Text(0, screen_w, face, text)
    if tsize.x < screen_w * 0.9 then
        textw = TextWidget:new{
            text = text,
            face = face,
        }
    else -- if text too wide, use TextBoxWidget for multi lines display
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

return Screensaver
