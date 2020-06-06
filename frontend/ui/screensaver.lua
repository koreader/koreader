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

local screensaver_provider = {
    ["jpg"] = true,
    ["jpeg"] = true,
    ["png"] = true,
    ["gif"] = true,
    ["tif"] = true,
    ["tiff"] = true,
}
local default_screensaver_message = _("Sleeping")
local Screensaver = {}

local function getRandomImage(dir)
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
                if screensaver_provider[extension] then
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

function Screensaver:chooseFolder()
    local buttons = {}
    table.insert(buttons, {
        {
            text = _("Choose screensaver directory"),
            callback = function()
                UIManager:close(self.choose_dialog)
                require("ui/downloadmgr"):new{
                    onConfirm = function(path)
                        logger.dbg("set screensaver directory to", path)
                        G_reader_settings:saveSetting("screensaver_dir", path)
                        UIManager:show(InfoMessage:new{
                            text = T(_("Screensaver directory set to:\n%1"), BD.dirpath(path)),
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
        screensaver_dir = DataStorage:getDataDir() .. "/screenshots/"
    end
    self.choose_dialog = ButtonDialogTitle:new{
        title = T(_("Current screensaver image directory:\n%1"), BD.dirpath(screensaver_dir)),
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
                        elseif screensaver_provider[suffix] then
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
    local screensaver_document_cover = G_reader_settings:readSetting("screensaver_document_cover")
    if screensaver_image == nil then
        screensaver_image = DataStorage:getDataDir() .. "/resources/koreader.png"
    end
    local title = document_cover and T(_("Current screensaver document cover:\n%1"), BD.filepath(screensaver_document_cover))
        or T(_("Current screensaver image:\n%1"), BD.filepath(screensaver_image))
    self.choose_dialog = ButtonDialogTitle:new{
        title = title,
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

function Screensaver:noBackground()
    return G_reader_settings:isTrue("screensaver_no_background")
end

function Screensaver:showMessage()
    return G_reader_settings:isTrue("screensaver_show_message")
end

function Screensaver:excluded()
    local lastfile = G_reader_settings:readSetting("lastfile")
    local exclude_ss = false -- consider it not excluded if there's no docsetting
    if DocSettings:hasSidecarFile(lastfile) then
        local doc_settings = DocSettings:open(lastfile)
        exclude_ss = doc_settings:readSetting("exclude_screensaver")
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
        description = _("Enter the message to be displayed by the screensaver. The following escape sequences can be used:\n  %p percentage read\n  %c current page number\n  %t total number of pages\n  %T title"),
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

function Screensaver:show(event, fallback_message)
    -- These 2 (optional) parameters are to support poweroff and reboot actions
    -- on Kobo (see uimanager.lua)
    if self.left_msg then
        UIManager:close(self.left_msg)
        self.left_msg = nil
    end
    local covers_fullscreen = true -- hint for UIManager:_repaint()
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

    local show_message = self:showMessage()

    if screensaver_type == nil then
        show_message = true
    end

    if screensaver_type == "message" then
        -- obsolete screensaver_type: migrate to new show_message = true
        screensaver_type = "disable"
        G_reader_settings:saveSetting("screensaver_type", "disable")
        G_reader_settings:saveSetting("screensaver_show_message", true)
    end

    -- messages can still be shown over "as-is" screensaver
    if screensaver_type == "disable" and show_message == false then
        return
    end

    local widget = nil
    local background = Blitbuffer.COLOR_BLACK
    if self:whiteBackground() then
        background = Blitbuffer.COLOR_WHITE
    elseif self:noBackground() then
        background = nil
    end

    local lastfile = G_reader_settings:readSetting("lastfile")
    if screensaver_type == "document_cover" then
        -- Set lastfile to the document of which we want to show the cover.
        lastfile = G_reader_settings:readSetting("screensaver_document_cover")
        screensaver_type = "cover"
    end
    if screensaver_type == "cover" then
        lastfile = lastfile ~= nil and lastfile or G_reader_settings:readSetting("lastfile")
        local exclude = false -- consider it not excluded if there's no docsetting
        if DocSettings:hasSidecarFile(lastfile) then
            local doc_settings = DocSettings:open(lastfile)
            exclude = doc_settings:readSetting("exclude_screensaver")
        end
        if exclude ~= true then
            if lastfile and lfs.attributes(lastfile, "mode") == "file" then
                local doc = DocumentRegistry:openDocument(lastfile)
                if doc.loadDocument then -- CreDocument
                    doc:loadDocument(false) -- load only metadata
                end
                local image = doc:getCoverPageImage()
                doc:close()
                if image ~= nil then
                    widget = ImageWidget:new{
                        image = image,
                        image_disposable = true,
                        height = Screen:getHeight(),
                        width = Screen:getWidth(),
                        scale_factor = not self:stretchImages() and 0 or nil,
                    }
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
        if lastfile and lfs.attributes(lastfile, "mode") == "file" then
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
                show_message = true
            end
            doc:close()
        else
            show_message = true
        end
    end
    if screensaver_type == "random_image" then
        local screensaver_dir = G_reader_settings:readSetting(prefix.."screensaver_dir")
        if screensaver_dir == nil and prefix ~= "" then
            screensaver_dir = G_reader_settings:readSetting("screensaver_dir")
        end
        if screensaver_dir == nil then
            screensaver_dir = DataStorage:getDataDir() .. "/screenshots/"
        end
        local image_file = getRandomImage(screensaver_dir)
        if image_file == nil then
            show_message = true
        else
            widget = ImageWidget:new{
                file = image_file,
                file_do_cache = false,
                alpha = true,
                height = Screen:getHeight(),
                width = Screen:getWidth(),
                scale_factor = not self:stretchImages() and 0 or nil,
            }
        end
    end
    if screensaver_type == "image_file" then
        local screensaver_image = G_reader_settings:readSetting(prefix.."screensaver_image")
        if screensaver_image == nil and prefix ~= "" then
            screensaver_image = G_reader_settings:readSetting("screensaver_image")
        end
        if screensaver_image == nil then
            screensaver_image = DataStorage:getDataDir() .. "/resources/koreader.png"
        end
        if  lfs.attributes(screensaver_image, "mode") ~= "file" then
            show_message = true
        else
            widget = ImageWidget:new{
                file = screensaver_image,
                file_do_cache = false,
                alpha = true,
                height = Screen:getHeight(),
                width = Screen:getWidth(),
                scale_factor = not self:stretchImages() and 0 or nil,
            }
        end
    end
    if screensaver_type == "readingprogress" then
        if Screensaver.getReaderProgress ~= nil then
            widget = Screensaver.getReaderProgress()
        else
            show_message = true
        end
    end

    if show_message == true then
        local screensaver_message = G_reader_settings:readSetting(prefix.."screensaver_message")
        local message_pos = G_reader_settings:readSetting(prefix.."screensaver_message_position")
        if not self:whiteBackground() then
            background = nil -- no background filling, let book text visible
            covers_fullscreen = false
        end
        if screensaver_message == nil and prefix ~= "" then
            screensaver_message = G_reader_settings:readSetting("screensaver_message")
        end

        local fallback = fallback_message or default_screensaver_message
        if screensaver_message == nil then
            screensaver_message = fallback
        else
            screensaver_message = self:expandSpecial(screensaver_message, fallback)
        end

        local message_widget
        if message_pos == "middle" or message_pos == nil then
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

        -- No overlay needed as we just displayed the message
        overlay_message = nil

        -- check if message_widget should be overlaid on another widget
        if message_widget then
            if widget then  -- we have a screensaver widget
                -- show message_widget on top of previously created widget
                local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
                widget = OverlapGroup:new{
                    dimen = {
                        h = screen_w,
                        w = screen_h,
                    },
                    widget,
                    message_widget,
                }
            else
                -- no prevously created widget so just show message widget
                widget = message_widget
            end
        end
    end

    if overlay_message then
        widget = self:addOverlayMessage(widget, overlay_message)
    end

    if widget then
        self.left_msg = ScreenSaverWidget:new{
            widget = widget,
            background = background,
            covers_fullscreen = covers_fullscreen,
        }
        self.left_msg.modal = true
        -- Refresh whole screen for other types
        self.left_msg.dithered = true
        UIManager:show(self.left_msg, "full")
    end
end

function Screensaver:expandSpecial(message, fallback)
    -- Expand special character sequences in given message. Use fallback string if there is no document instance
    -- %p percentage read
    -- %c current page
    -- %t total pages
    -- %T document title

    local ret = message

    local lastfile = G_reader_settings:readSetting("lastfile")
    local instance = require("apps/reader/readerui"):_getRunningInstance()
    if lastfile and lfs.attributes(lastfile, "mode") == "file" and instance ~= nil then
        local doc = DocumentRegistry:openDocument(lastfile)
        local currentpage = instance.view.state.page
        ret = string.gsub(ret, "%%c", currentpage)

        local totalpages = doc:getPageCount()
        ret = string.gsub(ret, "%%t", totalpages)

        local percent = Math.round((currentpage * 100) / totalpages)
        ret = string.gsub(ret, "%%p", percent)

        local props = doc:getProps()
        ret = string.gsub(ret, "%%T", props.title)
        doc:close()
    else
        ret = fallback
    end

    return ret
end

function Screensaver:close()
    if self.left_msg == nil then return end
    local screensaver_delay = G_reader_settings:readSetting("screensaver_delay")
    local screensaver_delay_number = tonumber(screensaver_delay)
    if screensaver_delay_number then
        UIManager:scheduleIn(screensaver_delay_number, function()
            logger.dbg("close screensaver")
            if self.left_msg then
                UIManager:close(self.left_msg, "full")
                self.left_msg = nil
            end
        end)
    elseif screensaver_delay == "disable" or screensaver_delay == nil then
        logger.dbg("close screensaver")
        if self.left_msg then
            UIManager:close(self.left_msg, "full")
            self.left_msg = nil
        end
    else
        logger.dbg("tap to exit from screensaver")
    end
end

function Screensaver:addOverlayMessage(widget, text)
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

return Screensaver
