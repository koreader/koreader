local Device = require("device")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local Screen = Device.screen

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
                file_do_cache = false,
                height = Screen:getHeight(),
                width = Screen:getWidth(),
                scale_factor = 0, -- scale to fit height/width
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
            scale_factor = doc_settings:readSetting("proportional_screensaver") and 0 or nil,
        }
        return createWidgetFromImage(img_widget)
    end
end

function Screensaver:show(kind, default_msg)
    logger.dbg("show screensaver")
    local InfoMessage = require("ui/widget/infomessage")
    local screensaver_settings = G_reader_settings:readSetting(kind .. "_screensaver") or {}
    -- first check book cover image, on by default
    local screensaver_last_book = screensaver_settings.use_last_file or
        G_reader_settings:readSetting("use_lastfile_as_screensaver")
    if screensaver_last_book == nil or screensaver_last_book then
        local lastfile = G_reader_settings:readSetting("lastfile")
        if lastfile then
            local doc_settings = DocSettings:open(lastfile)
            local exclude = doc_settings:readSetting("exclude_screensaver")
            if not exclude then
                self.left_msg = self:getCoverImage(lastfile)
            end
        end
    end
    -- then screensaver directory or file image
    if not self.left_msg then
        -- FIXME: rename screensaver_folder to screensaver_path
        local screensaver_path = screensaver_settings.path or
            G_reader_settings:readSetting("screensaver_folder")
        if screensaver_path == nil
        and Device.internal_storage_mount_point ~= nil then
            screensaver_path =
                Device.internal_storage_mount_point .. "screensaver"
        end
        if screensaver_path then
            local mode = lfs.attributes(screensaver_path, "mode")
            if mode ~= nil then
                if mode == "directory" then
                    self.left_msg = getRandomImage(screensaver_path)
                else
                    self.left_msg = createWidgetFromFile(screensaver_path)
                end
            end
        end
    end
    -- fallback to message box
    if not self.left_msg then
        local msg = screensaver_settings.message or default_msg
        if msg then
            self.left_msg = InfoMessage:new{ text = msg }
            UIManager:show(self.left_msg)
        end
    else
        -- set modal to put screensaver on top of everything else
        -- NB InfoMessage (in case of no image) defaults to modal
        self.left_msg.modal = true
        -- refresh whole screen for other types
        UIManager:show(self.left_msg, "full")
    end
end

function Screensaver:close()
    logger.dbg("close screensaver")
    if self.left_msg then
        UIManager:close(self.left_msg)
        self.left_msg = nil
    end
end

return Screensaver
