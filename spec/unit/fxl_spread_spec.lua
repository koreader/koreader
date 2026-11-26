-- Slice 4b: two-page spreads for fixed-layout (pre-paginated) books.
--
-- In 2-page (landscape) mode crengine draws two facing fixed-layout pages side
-- by side, each scaled/letterboxed into its half of the screen. The current
-- page and the next one share the view:
--   * left-to-right book: current page on the LEFT, next page on the RIGHT;
--   * right-to-left book (page-progression-direction="rtl", e.g. manga): the
--     current page on the RIGHT, next on the LEFT, so the spread reads
--     right-to-left and the two facing pages line up physically.
--
-- Both fixtures have 4 solid-colour pages (PAGE_COLORS in
-- make_fixedlayout_test_epub.py): page1 red, page2 blue. Rendered at 1600x1200,
-- each page fills ~one 800-wide half, so the half centres (400,600)/(1200,600)
-- sample the page drawn there.
local DATA = "spec/front/unit/data/fixedlayout/"
local W, H = 1600, 1200
local RED    = { 0xE6, 0x3B, 0x2E } -- page 1
local BLUE   = { 0x2E, 0x8B, 0xE6 } -- page 2
local GREEN  = { 0x3B, 0xB0, 0x4E } -- page 3
local YELLOW = { 0xE6, 0xC3, 0x2E } -- page 4
local PURPLE = { 0x8B, 0x3B, 0xE6 } -- page 5
local WHITE  = { 0xFF, 0xFF, 0xFF } -- blank half (page background)
local LEFT_X, RIGHT_X, MID_Y = 400, 1200, 600

describe("Fixed-layout two-page spreads (slice 4b)", function()
    local DocumentRegistry, Blitbuffer

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        Blitbuffer = require("ffi/blitbuffer")
    end)

    -- Render page `pageno` of `name` in 2-page spread mode at landscape size.
    local function renderSpread(name, pageno)
        local doc = DocumentRegistry:openDocument(DATA .. name)
        assert.truthy(doc, "could not open " .. name)
        assert.is_true(doc:loadDocument())
        assert.are.equal(1, doc:getFixedLayoutMode())
        doc.render_color = true
        doc:setViewMode("page")
        doc:setViewDimen({ w = W, h = H })
        doc:setVisiblePageCount(2)
        doc:render()
        assert.are.equal(2, doc:getVisiblePageCount()) -- spread mode is active
        local bb = Blitbuffer.new(W, H, Blitbuffer.TYPE_BBRGB32)
        bb:fill(Blitbuffer.COLOR_WHITE)
        doc:drawCurrentViewByPage(bb, 0, 0, { x = 0, y = 0, w = W, h = H }, pageno)
        return doc, bb
    end

    local function assertPixel(bb, x, y, rgb, label)
        local c = bb:getPixel(x, y)
        local pr, pg, pb = c:getR(), c:getG(), c:getB()
        local tol = 20
        assert.is_true(
            math.abs(pr - rgb[1]) <= tol and math.abs(pg - rgb[2]) <= tol and math.abs(pb - rgb[3]) <= tol,
            string.format("%s at (%d,%d): expected ~(%d,%d,%d), got (%d,%d,%d)",
                label, x, y, rgb[1], rgb[2], rgb[3], pr, pg, pb))
    end

    it("places the first page on the LEFT for a left-to-right book", function()
        local doc, bb = renderSpread("fxl_epub3_viewport.epub", 1)
        assert.are.equal("", doc:getPageProgressionDirection())
        assertPixel(bb, LEFT_X,  MID_Y, RED,  "page 1 (ltr) on the left half")
        assertPixel(bb, RIGHT_X, MID_Y, BLUE, "page 2 (ltr) on the right half")
        bb:free()
        doc:close()
    end)

    it("places the first page on the RIGHT for a right-to-left (manga) book", function()
        local doc, bb = renderSpread("fxl_rtl_spread.epub", 1)
        assert.are.equal("rtl", doc:getPageProgressionDirection())
        assertPixel(bb, RIGHT_X, MID_Y, RED,  "page 1 (rtl) on the right half")
        assertPixel(bb, LEFT_X,  MID_Y, BLUE, "page 2 (rtl) on the left half")
        bb:free()
        doc:close()
    end)

    -- fxl_cover_spread.epub: a lone cover (no page-spread hint) then
    -- left/right pairs. The cover must stand alone (not pair with page 2), so
    -- every later spread lines up: page1 alone, [page2|page3], [page4|page5].
    it("keeps a lone cover alone and aligns the following spreads", function()
        -- Cover view: the cover is alone on the left, the right half is blank.
        local doc, bb = renderSpread("fxl_cover_spread.epub", 1)
        assertPixel(bb, LEFT_X,  MID_Y, RED,   "cover alone on the left")
        assertPixel(bb, RIGHT_X, MID_Y, WHITE, "right half blank beside the cover")
        bb:free()
        doc:close()

        -- Next view is the first real spread: page 2 | page 3 (not cover | page2).
        doc, bb = renderSpread("fxl_cover_spread.epub", 2)
        assertPixel(bb, LEFT_X,  MID_Y, BLUE,  "page 2 on the left")
        assertPixel(bb, RIGHT_X, MID_Y, GREEN, "page 3 on the right")
        bb:free()
        doc:close()

        -- And the spread after that: page 4 | page 5.
        doc, bb = renderSpread("fxl_cover_spread.epub", 4)
        assertPixel(bb, LEFT_X,  MID_Y, YELLOW, "page 4 on the left")
        assertPixel(bb, RIGHT_X, MID_Y, PURPLE, "page 5 on the right")
        bb:free()
        doc:close()
    end)
end)
