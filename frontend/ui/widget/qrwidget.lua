--[[
QRWidget shows a QR code for a given text.
]]

local ImageWidget = require("ui/widget/imagewidget")
local RenderImage = require("ui/renderimage")
local logger = require("logger")
local qrencode = require("qrencode")

local QRWidget = ImageWidget:extend{
    scale_factor = 0,
    text = ""
    -- see ImageWidget for other options.
}

function QRWidget:init()
    local ok, ret = qrencode.qrcode(self.text:sub(1, 2953))
    if not ok then
        logger.info("QRWidget: failed to generate QR code.")
        return
    else
        -- We generate pbm data
        local qr = {"P1\n", 2*#ret[1], " ", 2*#ret, "\n"}
        for _, col in ipairs(ret) do
            for i = 1, 2 do
                for _, lgn in ipairs(col) do
                    table.insert(qr, lgn > 0 and "1 1 " or "0 0 ")
                end
                table.insert(qr, "\n")
            end
        end
        qr = table.concat(qr, '')
        local dim
        if self.width then
            if self.height then
                dim = math.min(self.width, self.height)
            else
                dim = self.width
            end
        elseif self.height then
            dim = self.height
        end
        self.image = RenderImage:renderImageData(qr, #qr, dim, dim)
    end
end

return QRWidget
