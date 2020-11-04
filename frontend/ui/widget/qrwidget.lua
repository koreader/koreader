--[[
QRWidget shows a QR code for a given text.
]]

local Blitbuffer = require("ffi/blitbuffer")
local ImageWidget = require("ui/widget/imagewidget")
local logger = require("logger")
local qrencode = require("ffi/qrencode")
local _ = require("gettext")

local QRWidget = ImageWidget:extend{
    scale_factor = nil,
    text = ""
    -- see ImageWidget for other options.
}

function QRWidget:init()
    local text = self.text
    if #text > 2953 then
        local truncated = _("... (truncated...)")
        text = text:sub(1, 2953 - #truncated) .. truncated
    end
    local ok, grid = qrencode.qrcode(text)
    if not ok then
        logger.info("QRWidget: failed to generate QR code.")
        return
    else
        local sq_size
        if self.width then
            if self.height then
                sq_size = math.min(self.width, self.height)/#grid
            else
                sq_size = self.width/#grid
            end
        elseif self.height then
            sq_size = self.height/#grid
        else sq_size = 1
        end
        sq_size = math.floor(sq_size)
        local grid_size = sq_size * #grid
        local bb = Blitbuffer.new(grid_size, grid_size)
        local white = Blitbuffer.COLOR_WHITE
        for x, col in ipairs(grid) do
            for y, lgn in ipairs(col) do
                if lgn < 0 then
                    bb:paintRect((x - 1) * sq_size, (y - 1) * sq_size, sq_size, sq_size, white)
                end
            end
        end
        self.image = bb
    end
end

return QRWidget
