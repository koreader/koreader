describe("QRWidget capacity limits", function()
    local qrencode, QRWidget

    setup(function()
        require("commonrequire")
        qrencode = require("ffi/qrencode")
        QRWidget = require("ui/widget/qrwidget")
    end)

    -- Lower case letters keep the encoder in byte mode (digits would select numeric
    -- mode, upper case alphanumeric mode), so these are the byte mode capacities.
    local function encode(len)
        local call_ok, res_or_err, _, size = pcall(qrencode.qrcode, ("a"):rep(len))
        return call_ok, res_or_err, size
    end

    it("should accept a payload of MAX_BYTES at version 40", function()
        local ok, _, size = encode(QRWidget.MAX_BYTES)
        assert.is_true(ok)
        assert.are.equal(177, size) -- 17 + 4 * 40
    end)

    it("should reject a payload one byte over MAX_BYTES", function()
        local ok, err = encode(QRWidget.MAX_BYTES + 1)
        assert.is_false(ok)
        assert.is_truthy(tostring(err):find("too long", 1, true))
    end)

    it("should encode an empty string as a version 1 symbol", function()
        -- Documents the encoder's behaviour: this is why QRWidget guards against
        -- empty text itself instead of relying on the encoder to refuse it.
        local call_ok, _, _, size = pcall(qrencode.qrcode, "")
        assert.is_true(call_ok)
        assert.are.equal(21, size)
    end)
end)

describe("QRWidget rendering", function()
    local QRWidget

    setup(function()
        require("commonrequire")
        QRWidget = require("ui/widget/qrwidget")
    end)

    -- "a" is a version 1 symbol: 21 x 21 modules.
    local V1_MODULES = 21

    -- Plain device pixels on purpose: these tests assert exact pixel geometry, which
    -- scaleBySize() would make depend on the screen DPI.
    local ANY_PX = 100    -- an area whose exact size doesn't matter
    local SCREEN_PX = 600 -- a typical screen width

    local function luma(bb, x, y)
        return bb:getPixel(x, y):getColor8().a
    end

    it("should have no image without a width and height", function()
        assert.is_nil(QRWidget:new{ text = "hello" }.image)
        assert.is_nil(QRWidget:new{ text = "hello", width = ANY_PX }.image)
        assert.is_nil(QRWidget:new{ text = "hello", height = ANY_PX }.image)
    end)

    it("should have no image for empty or missing text", function()
        assert.is_nil(QRWidget:new{ text = "", width = ANY_PX, height = ANY_PX }.image)
        assert.is_nil(QRWidget:new{ width = ANY_PX, height = ANY_PX }.image)
    end)

    it("should draw whole pixels per module", function()
        local w = QRWidget:new{ text = "a", width = V1_MODULES * 5, height = V1_MODULES * 5 }
        assert.is_not_nil(w.image)
        assert.are.equal(V1_MODULES * 5, w.image:getWidth())
        assert.are.equal(V1_MODULES * 5, w.image:getHeight())
    end)

    it("should round the scale down and never exceed the area", function()
        -- 5 px per module plus some slack: floor((21 * 5 + 5) / 21) = 5
        local area = V1_MODULES * 5 + 5
        local w = QRWidget:new{ text = "a", width = area, height = area }
        assert.are.equal(V1_MODULES * 5, w.image:getWidth())
        assert.are.equal(V1_MODULES * 5, w.image:getHeight())
    end)

    it("should size from the smaller of width and height", function()
        local w = QRWidget:new{ text = "a", width = SCREEN_PX, height = V1_MODULES * 4 }
        assert.are.equal(V1_MODULES * 4, w.image:getWidth())
    end)

    it("should have no image, and not throw, when the area is under one pixel per module", function()
        local w
        assert.has_no.errors(function()
            w = QRWidget:new{ text = "a", width = V1_MODULES - 1, height = V1_MODULES - 1 }
        end)
        assert.is_nil(w.image)
    end)

    it("should render the largest payload at 3 px per module in 600 px", function()
        -- 2953 bytes -> version 40 -> 177 modules; floor(600 / 177) = 3
        local w = QRWidget:new{
            text = ("a"):rep(QRWidget.MAX_BYTES),
            width = SCREEN_PX,
            height = SCREEN_PX,
        }
        assert.is_not_nil(w.image)
        assert.are.equal(177 * 3, w.image:getWidth())
    end)

    it("should have no image, and not throw, for a payload that is too long", function()
        local w
        assert.has_no.errors(function()
            w = QRWidget:new{
                text = ("a"):rep(QRWidget.MAX_BYTES + 1),
                width = SCREEN_PX,
                height = SCREEN_PX,
            }
        end)
        assert.is_nil(w.image)
    end)

    it("should draw dark modules dark and light modules light", function()
        -- Every symbol has the same top-left finder pattern: a dark 7x7 ring, a light
        -- ring inside it, then a dark 3x3 centre. A colour inversion would flip these.
        local px = 5
        local w = QRWidget:new{ text = "a", width = V1_MODULES * px, height = V1_MODULES * px }
        local bb = w.image
        assert.are.equal(0, luma(bb, 0, 0))        -- module (1,1): dark
        assert.are.equal(255, luma(bb, px, px))    -- module (2,2): light
        assert.are.equal(0, luma(bb, 2 * px, 2 * px)) -- module (3,3): dark
        -- the whole module is painted, not just its corner
        assert.are.equal(255, luma(bb, 2 * px - 1, 2 * px - 1))
    end)
end)
