local DocumentRegistry = require("document/documentregistry")
local UIManager = require("ui/uimanager")
local Screen = require("ui/screen")
local DEBUG = require("dbg")
local _ = require("gettext")

local Screensaver = {
}

function Screensaver:getCoverImage(file)
    local ImageWidget = require("ui/widget/imagewidget")
    local doc = DocumentRegistry:openDocument(file)
    if doc then
        local image = doc:getCoverPageImage()
        doc:close()
        if image then
            return ImageWidget:new{
                image = image,
                width = Screen:getWidth(),
                height = Screen:getHeight(),
            }
        end
    end
end

function Screensaver:getRandomImage(dir)
    local ImageWidget = require("ui/widget/imagewidget")
    local pics = {}
    local i = 0
    math.randomseed(os.time())
    for entry in lfs.dir(dir) do
        if lfs.attributes(dir .. entry, "mode") == "file" then
            local extension = string.lower(string.match(entry, ".+%.([^.]+)") or "")
            if extension == "jpg" or extension == "jpeg" or extension == "png" then
                i = i + 1
                pics[i] = entry
            end
        end
    end
    local image = pics[math.random(i)]
    if image then
        image = dir .. image
        if lfs.attributes(image, "mode") == "file" then
            return ImageWidget:new{
                file = image,
                width = Screen:getWidth(),
                height = Screen:getHeight(),
            }
        end
    end
end

function Screensaver:show()
    DEBUG("show screensaver")
    local InfoMessage = require("ui/widget/infomessage")
    -- first check book cover image
    if KOBO_SCREEN_SAVER_LAST_BOOK then
        local lastfile = G_reader_settings:readSetting("lastfile")
        self.suspend_msg = self:getCoverImage(lastfile)
    -- then screensaver directory image
    elseif type(KOBO_SCREEN_SAVER) == "string" then
        local file = KOBO_SCREEN_SAVER
        if lfs.attributes(file, "mode") == "directory" then
            if string.sub(file,string.len(file)) ~= "/" then
                file = file .. "/"
            end
            self.suspend_msg = self:getRandomImage(file)
        end
    end
    -- fallback to suspended message
    if not self.suspend_msg then
        self.suspend_msg = InfoMessage:new{ text = _("Suspended") }
    end
    UIManager:show(self.suspend_msg)
end

function Screensaver:close()
    DEBUG("close screensaver")
    if self.suspend_msg then
        UIManager:close(self.suspend_msg)
        self.suspend_msg = nil
    end
end

return Screensaver
