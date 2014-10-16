local Blitbuffer = require("ffi/blitbuffer")
local einkfb = require("ffi/framebuffer")
local Geom = require("ui/geometry")
local util = require("ffi/util")
local DEBUG = require("dbg")
local _ = require("gettext")

--[[
Codes for rotation modes:

1 for no rotation,
2 for landscape with bottom on the right side of screen, etc.

           2
   +--------------+
   | +----------+ |
   | |          | |
   | | Freedom! | |
   | |          | |
   | |          | |
 3 | |          | | 1
   | |          | |
   | |          | |
   | +----------+ |
   |              |
   |              |
   +--------------+
          0
--]]


local Screen = {
    cur_rotation_mode = 0,
    native_rotation_mode = nil,
    blitbuffer_rotation_mode = 0,

    bb = nil,
    saved_bb = nil,

    fb = einkfb.open("/dev/fb0"),
    -- will be set upon loading by Device class:
    device = nil,
}

function Screen:init()
    self.bb = self.fb.bb
    if self.device:getModel() == 'Kobo_phoenix' then
        function Screen:getSize()
            return Screen:getSizePhoenix()
        end
        function Screen:getWidth()
            return Screen:getWidthPhoenix()
        end
        function Screen:getHeight()
            return Screen:getHeightPhoenix()
        end
        function self:offsetX()
            if Screen.cur_rotation_mode == 0 then
                return 6
            elseif Screen.cur_rotation_mode == 1 then
                return 12
            elseif Screen.cur_rotation_mode == 2 then
                return 12
            elseif Screen.cur_rotation_mode == 3 then
                return 6
            end
        end
        function self:offsetY()
            return 1
        end
    elseif self.device:getModel() == 'Kobo_dahlia' then
        function Screen:getSize()
            return Screen:getSizePhoenix()
        end
        function Screen:getWidth()
            return Screen:getWidthDahlia()
        end
        function Screen:getHeight()
            return Screen:getHeightDahlia()
        end
        function self:offsetX()
            return 0
        end
        function self:offsetY()
            if Screen.cur_rotation_mode == 0 or Screen.cur_rotation_mode == 3 then
                return 10
            else
                return 0
            end
        end
    else
        function Screen:getSize()
            return Screen:getSizeBB()
        end
        function Screen:getWidth()
            return Screen:getWidthBB()
        end
        function Screen:getHeight()
            return Screen:getHeightBB()
        end
        function self:offsetX() return 0 end
        function self:offsetY() return 0 end
    end
    self.blitbuffer_rotation_mode = self.bb:getRotation()
    -- asking the framebuffer for orientation is error prone,
    -- so we do this simple heuristic (for now)
    if self:getWidth() > self:getHeight() then
        self.native_rotation_mode = 1
    else
        self.native_rotation_mode = 0
    end
    self.cur_rotation_mode = self.native_rotation_mode
end

    -- For the Kobo Aura an offset is needed, because the bezel make the
    -- visible screen smaller.
function Screen:PhoenixBezelCleaner()
    -- bb.paintRect(x, y, w, h, color)
    self.bb:paintRect(0,0, Screen:getWidth(), Screen:offsetY() , 0 )
    self.bb:paintRect(0,0, Screen:offsetX(), Screen:getHeight(), 0 )
    self.bb:paintRect(Screen:getWidth() + Screen:offsetX(), 0 , Screen:getWidth() - Screen:getWidth() - Screen:offsetX(), Screen:getHeight(), 0 )
    self.bb:paintRect(0, Screen:getHeight() + Screen:offsetY(), Screen:offsetX(), Screen:getWidth(), 0 )
end

function Screen:refresh(refresh_type, waveform_mode, x, y, w, h)
    self.fb:refresh(refresh_type, waveform_mode, x, y, w, h)
    if self.device:getModel() == 'Kobo_phoenix' and refresh_type == 1 then
        Screen:PhoenixBezelCleaner()
    end
end

function Screen:getSizeBB()
    return Geom:new{w = self.bb:getWidth(), h = self.bb:getHeight()}
end

function Screen:getSizePhoenix()
    return Geom:new{w = self.getWidth(), h = self.getHeight()}
end

function Screen:getWidthBB()
    return self.bb:getWidth()
end

function Screen:getWidthDahlia()
    if self.cur_rotation_mode == 0 then return 1080
    else return 1430
    end
end

function Screen:getWidthPhoenix()
    if self.cur_rotation_mode == 0 then return 752
    else return 1012
    end
end

function Screen:getHeightBB()
    return self.bb:getHeight()
end

function Screen:getHeightDahlia()
    if self.cur_rotation_mode == 0 then return 1430
    else return 1080
    end
end

function Screen:getHeightPhoenix()
    if self.cur_rotation_mode == 0 then return 1012
    else return 752
    end
end

function Screen:getDPI()
    if self.dpi == nil then
        self.dpi = G_reader_settings:readSetting("screen_dpi")
    end
    if self.dpi ~= nil then return self.dpi end
    local model = self.device:getModel()
    if model == "KindlePaperWhite" or model == "KindlePaperWhite2"
        or model == "Kobo_kraken" then
        self.dpi = 212
    elseif model == "Kobo_phoenix" then
        self.dpi = 212.8
    elseif model == "Kobo_dragon" or model == "Kobo_dahlia" then
        self.dpi = 265
    elseif model == "Kobo_pixie" then
        self.dpi = 200
    elseif util.isAndroid() then
        local android = require("android")
        local ffi = require("ffi")
        self.dpi = ffi.C.AConfiguration_getDensity(android.app.config)
    else
        self.dpi = 160
    end
    return self.dpi
end

function Screen:setDPI(dpi)
    G_reader_settings:saveSetting("screen_dpi", dpi)
end

function Screen:scaleByDPI(px)
    -- scaled positive px should also be positive
    return math.ceil(px * self:getDPI()/167)
end

function Screen:getRotationMode()
    return self.cur_rotation_mode
end

function Screen:getScreenMode()
    if self:getWidth() > self:getHeight() then
        return "landscape"
    else
        return "portrait"
    end
end

function Screen:setRotationMode(mode)
    self.fb.bb:rotateAbsolute(-90 * (mode - self.native_rotation_mode - self.blitbuffer_rotation_mode))
    self.cur_rotation_mode = mode
end

function Screen:setScreenMode(mode)
    if mode == "portrait" then
        if self.cur_rotation_mode ~= 0 then
            self:setRotationMode(0)
        end
    elseif mode == "landscape" then
        if self.cur_rotation_mode == 0 or self.cur_rotation_mode == 2 then
            self:setRotationMode(DLANDSCAPE_CLOCKWISE_ROTATION and 1 or 3)
        elseif self.cur_rotation_mode == 1 or self.cur_rotation_mode == 3 then
            self:setRotationMode((self.cur_rotation_mode + 2) % 4)
        end
    end
end

function Screen:saveCurrentBB()
    local width, height = self:getWidth(), self:getHeight()

    if not self.saved_bb then
        self.saved_bb = Blitbuffer.new(width, height)
    end
    if self.saved_bb:getWidth() ~= width then
        self.saved_bb:free()
        self.saved_bb = Blitbuffer.new(width, height)
    end
    self.saved_bb:blitFullFrom(self.bb)
end

function Screen:restoreFromSavedBB()
    self:restoreFromBB(self.saved_bb)
    -- free data
    self.saved_bb = nil
end

function Screen:getCurrentScreenBB()
    local bb = Blitbuffer.new(self:getWidth(), self:getHeight())
    bb:blitFullFrom(self.bb)
    return bb
end

function Screen:restoreFromBB(bb)
    if bb then
        self.bb:blitFullFrom(bb)
    else
        DEBUG("Got nil bb in restoreFromSavedBB!")
    end
end

function Screen:close()
    DEBUG("close screen framebuffer")
    self.fb:close()
end

function Screen:getDPIMenuTable()
    local function dpi() return G_reader_settings:readSetting("screen_dpi") end
    local function custom() return G_reader_settings:readSetting("custom_screen_dpi") end
    local function setDPI(dpi)
        local InfoMessage = require("ui/widget/infomessage")
        local UIManager = require("ui/uimanager")
        UIManager:show(InfoMessage:new{
            text = _("This will take effect on next restart."),
        })
        Screen:setDPI(dpi)
    end
    return {
        text = _("Screen DPI"),
        sub_item_table = {
            {
                text = _("Auto"),
                checked_func = function()
                    return dpi() == nil
                end,
                callback = function() setDPI() end
            },
            {
                text = _("Small"),
                checked_func = function()
                    local dpi, custom = dpi(), custom()
                    return dpi and dpi <= 140 and dpi ~= custom
                end,
                callback = function() setDPI(120) end
            },
            {
                text = _("Medium"),
                checked_func = function()
                    local dpi, custom = dpi(), custom()
                    return dpi and dpi > 140 and dpi <= 200 and dpi ~= custom
                end,
                callback = function() setDPI(160) end
            },
            {
                text = _("Large"),
                checked_func = function()
                    local dpi, custom = dpi(), custom()
                    return dpi and dpi > 200 and dpi ~= custom
                end,
                callback = function() setDPI(240) end
            },
            {
                text = _("Custom DPI") .. ": " .. (custom() or 160),
                checked_func = function()
                    local dpi, custom = dpi(), custom()
                    return custom and dpi == custom
                end,
                callback = function() setDPI(custom() or 160) end,
                hold_input = {
                    title = _("Input screen DPI"),
                    type = "number",
                    hint = "(90 - 330)",
                    callback = function(input)
                        local dpi = tonumber(input)
                        dpi = dpi < 90 and 90 or dpi
                        dpi = dpi > 330 and 330 or dpi
                        G_reader_settings:saveSetting("custom_screen_dpi", dpi)
                        setDPI(dpi)
                    end,
                },
            },
        }
    }
end

return Screen

