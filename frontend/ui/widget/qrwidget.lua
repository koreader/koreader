--[[
QRWidget shows a QR code for a given text.
]]

local Blitbuffer = require("ffi/blitbuffer")
local ImageWidget = require("ui/widget/imagewidget")
local logger = require("logger")
local qrencode = require("ffi/qrencode")
local time = require("ui/time")

local QRWidget = ImageWidget:extend{
    original_in_nightmode = false,
    scale_factor = nil,
    text = "",
    -- see ImageWidget for other options.
    width = nil,  -- Required. Width in pixels.
    height = nil, -- Required. Height in pixels.
    -- We won't set the error correction level as to maximise the amount of data that can be
    -- encoded. The encoder will choose the best settings automatically for any given payload.
    MAX_BYTES = 2953, -- byte mode, version 40, EC level L (qrencode default selection)
}

function QRWidget:init()
    if not (self.width and self.height) then return end
    if not self.text or self.text == "" then return end
    local start_time = time.now()
    -- qrcode() throws on failure (e.g., payload too long)
    local call_ok, res_or_err, matrix, size = pcall(qrencode.qrcode, self.text)
    if not call_ok then
        logger.warn("QRWidget: QR encoding failed:", res_or_err) -- res_or_err holds the error message here
        return
    end

    local sq_size = math.floor(math.min(self.width, self.height) / size)
    if sq_size < 1 then
        -- Blitbuffer.new(0, 0) would throw. Leave self.image unset so the caller shows its error placeholder.
        logger.warn("QRWidget: area too small for matrix size", size, "| width =", self.width, "| height =", self.height)
        return
    end
    local grid_size = sq_size * size

    local bb = Blitbuffer.new(grid_size, grid_size)
    local white = Blitbuffer.COLOR_WHITE

    for y = 1, size do
        for x = 1, size do
            if matrix[(y - 1) * size + x] < 0 then
                bb:paintRect((x - 1) * sq_size, (y - 1) * sq_size, sq_size, sq_size, white)
            end
        end
    end
    self.image = bb
    local elapsed_time = time.to_s(time.since(start_time))
    logger.dbg("QRWidget: generated QR code for text of byte length", #self.text, "| matrix size", size, "| grid size", grid_size)
    logger.dbg("QRWidget: scale factor =", sq_size, "| width =", self.width, "| height =", self.height, "| encoding time", elapsed_time, "seconds")
end

return QRWidget
