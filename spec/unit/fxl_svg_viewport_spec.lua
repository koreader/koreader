-- Fixed-layout pages that declare their canvas with an <svg viewBox="0 0 W H">
-- wrapping a single full-page image, and have NO <meta name="viewport"> (a
-- common cover/title-page pattern). The viewBox is used as the viewport, and the
-- full-page SVG is laid out as a block filling its page, so the image fills the
-- page edge to edge instead of being letterboxed/inset in a corner.
local DATA = "spec/front/unit/data/fixedlayout/"
local W, H = 800, 1200
local RED = { 0xE6, 0x3B, 0x2E } -- page 1's solid colour (PAGE_COLORS[0])

describe("Fixed-layout SVG-viewBox viewport", function()
    local DocumentRegistry, Blitbuffer

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        Blitbuffer = require("ffi/blitbuffer")
    end)

    it("fills the page from an <svg viewBox> when there is no <meta viewport>", function()
        local doc = DocumentRegistry:openDocument(DATA .. "fxl_svg_viewport.epub")
        assert.truthy(doc, "could not open fxl_svg_viewport.epub")
        assert.is_true(doc:loadDocument())
        assert.are.equal(1, doc:getFixedLayoutMode())
        doc.render_color = true
        doc:setViewMode("page")
        doc:setViewDimen({ w = W, h = H })
        doc:render()
        local bb = Blitbuffer.new(W, H, Blitbuffer.TYPE_BBRGB32)
        bb:fill(Blitbuffer.COLOR_WHITE)
        doc:drawCurrentViewByPage(bb, 0, 0, { x = 0, y = 0, w = W, h = H }, 1)

        local function assertRed(x, y, label)
            local c = bb:getPixel(x, y)
            local pr, pg, pb = c:getR(), c:getG(), c:getB()
            assert.is_true(
                math.abs(pr - RED[1]) <= 20 and math.abs(pg - RED[2]) <= 20 and math.abs(pb - RED[3]) <= 20,
                string.format("%s at (%d,%d): expected ~(230,59,46), got (%d,%d,%d)", label, x, y, pr, pg, pb))
        end

        -- The full-page image fills the canvas edge to edge: the four corners are
        -- the page colour, not the white page background (which is what they would
        -- be if the viewport-less SVG were laid out at default size and inset).
        assertRed(3, 3, "top-left corner")
        assertRed(W - 3, 3, "top-right corner")
        assertRed(3, H - 3, "bottom-left corner")
        assertRed(W - 3, H - 3, "bottom-right corner")
        assertRed(400, 600, "center")

        bb:free()
        doc:close()
    end)
end)
