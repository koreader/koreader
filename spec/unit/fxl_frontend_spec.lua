-- Slice 4a (frontend): the reader UI adapts to fixed-layout (pre-paginated) books.
--  * A book whose spine declares page-progression-direction="rtl" (e.g. manga)
--    defaults page turns to right-to-left (inverse_reading_order) for a fresh
--    book, without the user having to toggle it.
--  * A fully fixed-layout book hides the reflow-only settings that have no
--    effect on it (font, typography/hyphenation, CSS render style, style
--    tweaks). Mixed-layout and reflowable books keep them.
local DATA = "spec/front/unit/data/fixedlayout/"
local REFLOWABLE = "spec/front/unit/data/juliet.epub"

describe("Fixed-layout frontend (slice 4a)", function()
    local DocumentRegistry, ReaderUI, DocSettings, Screen
    local had_inverse

    setup(function()
        require("commonrequire")
        disable_plugins()
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        DocSettings = require("docsettings")
        Screen = require("device").screen
        -- Make the global default LTR, so an RTL result is attributable to the
        -- book rather than to a leftover global preference.
        had_inverse = G_reader_settings:isTrue("inverse_reading_order")
        G_reader_settings:makeFalse("inverse_reading_order")
    end)

    teardown(function()
        if had_inverse then
            G_reader_settings:makeTrue("inverse_reading_order")
        else
            G_reader_settings:delSetting("inverse_reading_order")
        end
        G_reader_settings:flush()
    end)

    -- Open a fresh ReaderUI on `path`, with no carried-over per-book settings.
    local function openReader(path)
        DocSettings:open(path):purge()
        return ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(path),
        }
    end

    local function closeReader(readerui)
        readerui:closeDocument()
        readerui:onClose()
    end

    -- Populate a menu_items table the way the reader main menu does.
    local function buildReflowMenus(readerui)
        local menu_items = {}
        readerui.font:addToMainMenu(menu_items)
        readerui.typeset:addToMainMenu(menu_items)
        readerui.typography:addToMainMenu(menu_items)
        readerui.styletweak:addToMainMenu(menu_items)
        return menu_items
    end

    it("defaults page turns to RTL for an rtl-progression book", function()
        local readerui = openReader(DATA .. "fxl_rtl_spread.epub")
        assert.are.equal("rtl", readerui.document:getPageProgressionDirection())
        assert.is_true(readerui.view.inverse_reading_order)
        closeReader(readerui)
    end)

    it("keeps page turns LTR for a fixed-layout book with no rtl hint", function()
        local readerui = openReader(DATA .. "fxl_positioned.epub")
        assert.are.equal(1, readerui.document:getFixedLayoutMode())
        assert.are.equal("", readerui.document:getPageProgressionDirection())
        assert.is_falsy(readerui.view.inverse_reading_order)
        closeReader(readerui)
    end)

    it("hides reflow-only menus for a fully fixed-layout book", function()
        local readerui = openReader(DATA .. "fxl_positioned.epub")
        local menu_items = buildReflowMenus(readerui)
        assert.is_nil(menu_items.change_font)
        assert.is_nil(menu_items.set_render_style)
        assert.is_nil(menu_items.typography)
        assert.is_nil(menu_items.style_tweaks)
        closeReader(readerui)
    end)

    it("keeps reflow-only menus for a mixed-layout book", function()
        local readerui = openReader(DATA .. "fxl_mixed.epub")
        assert.are.equal(2, readerui.document:getFixedLayoutMode())
        local menu_items = buildReflowMenus(readerui)
        assert.truthy(menu_items.change_font)
        assert.truthy(menu_items.set_render_style)
        assert.truthy(menu_items.typography)
        assert.truthy(menu_items.style_tweaks)
        closeReader(readerui)
    end)

    it("keeps reflow-only menus for a reflowable book", function()
        local readerui = openReader(REFLOWABLE)
        assert.are.equal(0, readerui.document:getFixedLayoutMode())
        local menu_items = buildReflowMenus(readerui)
        assert.truthy(menu_items.change_font)
        assert.truthy(menu_items.set_render_style)
        assert.truthy(menu_items.typography)
        assert.truthy(menu_items.style_tweaks)
        closeReader(readerui)
    end)
end)
