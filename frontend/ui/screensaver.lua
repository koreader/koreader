local DocumentRegistry = require("document/documentregistry")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Screen = Device.screen
local DocSettings = require("docsettings")
local DEBUG = require("dbg")
local _ = require("gettext")

local Screensaver = {
}

local function createWidgetFromImage(image_widget)
    if image_widget then
        local AlphaContainer = require("ui/widget/container/alphacontainer")
        local CenterContainer = require("ui/widget/container/centercontainer")
        return AlphaContainer:new{
            alpha = 1,
            height = Screen:getHeight(),
            width = Screen:getWidth(),
            CenterContainer:new{
                dimen = Screen:getSize(),
                image_widget,
            }
        }
    end
end

local function createWidgetFromFile(file)
    if lfs.attributes(file, "mode") == "file" then
        local ImageWidget = require("ui/widget/imagewidget")
        return createWidgetFromImage(
                   ImageWidget:new{
                       file = file,
                       height = Screen:getHeight(),
                       width = Screen:getWidth(),
                       autostretch = true,
                   })
    end
end

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
    return createWidgetFromFile(dir .. pics[math.random(i)])
end

function Screensaver:isUsingBookCover()
    -- this setting is on by default
    return G_reader_settings:readSetting('use_lastfile_as_screensaver') ~= false
end

function Screensaver:getCoverImage(file)
    local ImageWidget = require("ui/widget/imagewidget")
    local doc = DocumentRegistry:openDocument(file)
    if not doc then return end

    local image = doc:getCoverPageImage()
    doc:close()
    local lastfile = G_reader_settings:readSetting("lastfile")
    local doc_settings = DocSettings:open(lastfile)
    if image then
        local img_widget = ImageWidget:new{
            image = image,
            height = Screen:getHeight(),
            width = Screen:getWidth(),
            autostretch = doc_settings:readSetting("proportional_screensaver"),
        }
        return createWidgetFromImage(img_widget)
    end
end

function Screensaver:show()
    DEBUG("show screensaver")
    local InfoMessage = require("ui/widget/infomessage")
    -- first check book cover image, on by default
    local screen_saver_last_book =
        G_reader_settings:readSetting("use_lastfile_as_screensaver")
    if screen_saver_last_book == nil or screen_saver_last_book then
        local lastfile = G_reader_settings:readSetting("lastfile")
        if lastfile then
            local doc_settings = DocSettings:open(lastfile)
            local exclude = doc_settings:readSetting("exclude_screensaver")
            if not exclude then
                self.suspend_msg = self:getCoverImage(lastfile)
            end
        end
    end
    -- then screensaver directory or file image
    if not self.suspend_msg then
        -- FIXME: rename this config to screen_saver_path
        local screen_saver_folder =
            G_reader_settings:readSetting("screensaver_folder")
        if screen_saver_folder == nil
        and Device.internal_storage_mount_point ~= nil then
            screen_saver_folder =
                Device.internal_storage_mount_point .. "screensaver"
        end
        if screen_saver_folder then
            local file = screen_saver_folder
            if lfs.attributes(file, "mode") == "directory" then
                self.suspend_msg = getRandomImage(file)
            else
                self.suspend_msg = createWidgetFromFile(file)
            end
        end
    end
    -- fallback to suspended message
    if not self.suspend_msg then
        self.suspend_msg = InfoMessage:new{ text = _("Suspended") }
        UIManager:show(self.suspend_msg)
    else
        -- refresh whole screen for other types
        UIManager:show(self.suspend_msg, "full")
    end
end

function Screensaver:close()
    DEBUG("close screensaver")
    if self.suspend_msg then
        UIManager:close(self.suspend_msg)
        self.suspend_msg = nil
    end
end

return Screensaver
