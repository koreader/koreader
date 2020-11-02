--[[
QRWidget shows a QR code for a given text.
]]

local ImageWidget = require("ui/widget/imagewidget")
local RenderImage = require("ui/renderimage")
local Widget = require("ui/widget/widget")
local logger = require("logger")
local qrencode = require("qrencode")

local QRWidget = Widget:new{
    scale_factor = 0,
    text = ""
    -- see ImageWidget for other options.
}

function QRWidget:init()
    local ok, ret = qrencode.qrcode(self.text)
    if not ok then
        logger.info("QRWidget: failed to generate QR code.")
        return
    else
        -- We generate pbm data
        local qr = {"P1\n", #ret[1], " ", #ret, "\n"}
        for _, col in ipairs(ret) do
            for _, lgn in ipairs(col) do
                table.insert(qr, lgn > 0 and "1 " or "0 ")
            end
            table.insert(qr, "\n")
        end
        qr = table.concat(qr, '')
        local dim = math.min(self.width, self.height)
        self.image = RenderImage:renderImageData(qr, #qr, dim, dim)
        return ImageWidget:new(self)
    end
end

return QRWidget
