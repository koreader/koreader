--[[
QRWidget shows a QR code for a given text.
]]

local ImageWidget = require("ui/widget/imagewidget")
local RenderImage = require("ui/renderimage")
local logger = require("logger")
local qrencode = require("qrencode")
local _ = require("gettext")

local QRWidget = ImageWidget:extend{
    scale_factor = 0,
    text = ""
    -- see ImageWidget for other options.
}

function QRWidget:init()
    local text = self.text
    if #text > 2953 then
        local truncated = _('... (truncated...)')
        text = text:sub(1, 2953 - #truncated) .. truncated
    end
    local ok, ret = qrencode.qrcode(text)
    if not ok then
        logger.info("QRWidget: failed to generate QR code.")
        return
    else
        -- We generate pbm data
        local scaling = 4
        local qr = {"P1\n", scaling*#ret[1], " ", scaling*#ret, "\n"}
        for _, col in ipairs(ret) do
            for i = 1, scaling do
                for _, lgn in ipairs(col) do
                    for j = 1, scaling do
                        table.insert(qr, lgn > 0 and "1 " or "0 ")
                    end
                end
                table.insert(qr, "\n")
            end
        end
        qr = table.concat(qr, '')
        local square_size
        if self.width then
            if self.height then
                square_size = math.min(self.width, self.height)
            else
                square_size = self.width
            end
        elseif self.height then
            square_size = self.height
        end
        self.image = RenderImage:renderImageData(qr, #qr, square_size, square_size)
    end
end

return QRWidget
