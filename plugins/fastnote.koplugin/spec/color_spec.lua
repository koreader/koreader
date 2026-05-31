-- spec/color_spec.lua — tests for lib/color.lua
-- Run with: busted spec/  (from plugins/fastnote.koplugin/)

package.path = package.path .. ";fastnote.koplugin/?.lua"

describe("Color", function()
    local Color

    before_each(function()
        package.loaded["lib/color"] = nil
        Color = require("lib/color")
    end)

    -- Palette structure --------------------------------------------------------

    it("PALETTE has 6 entries", function()
        assert.equals(6, #Color.PALETTE)
    end)

    it("each palette entry has name, light and dark string fields", function()
        for _, entry in ipairs(Color.PALETTE) do
            assert.is_string(entry.name)
            assert.is_string(entry.light)
            assert.is_string(entry.dark)
        end
    end)

    it("all light hex values start with #", function()
        for _, entry in ipairs(Color.PALETTE) do
            assert.equals("#", entry.light:sub(1, 1))
        end
    end)

    -- resolve() ----------------------------------------------------------------

    describe("resolve()", function()
        it("returns light hex unchanged in light mode", function()
            assert.equals("#cc2222", Color.resolve("#cc2222", false))
        end)

        it("returns dark variant in dark mode", function()
            assert.equals("#ff5555", Color.resolve("#cc2222", true))
        end)

        it("maps black (#000000) to white (#ffffff) in dark mode", function()
            assert.equals("#ffffff", Color.resolve("#000000", true))
        end)

        it("returns black unchanged in light mode", function()
            assert.equals("#000000", Color.resolve("#000000", false))
        end)

        it("passes through unknown hex unchanged in light mode", function()
            assert.equals("#aabbcc", Color.resolve("#aabbcc", false))
        end)

        it("passes through unknown hex unchanged in dark mode", function()
            assert.equals("#aabbcc", Color.resolve("#aabbcc", true))
        end)

        it("resolve does not mutate the palette", function()
            Color.resolve("#cc2222", true)
            assert.equals("#cc2222", Color.PALETTE[2].light)
            assert.equals("#ff5555", Color.PALETTE[2].dark)
        end)

        it("all 6 palette light values resolve to themselves in light mode", function()
            for _, entry in ipairs(Color.PALETTE) do
                assert.equals(entry.light, Color.resolve(entry.light, false))
            end
        end)

        it("all 6 palette light values resolve to their dark variants in dark mode", function()
            for _, entry in ipairs(Color.PALETTE) do
                assert.equals(entry.dark, Color.resolve(entry.light, true))
            end
        end)
    end)

    -- is_achromatic() ----------------------------------------------------------

    describe("is_achromatic()", function()
        it("returns true for black (#000000)", function()
            assert.is_true(Color.is_achromatic("#000000"))
        end)

        it("returns true for white (#ffffff)", function()
            assert.is_true(Color.is_achromatic("#ffffff"))
        end)

        it("returns false for red", function()
            assert.is_false(Color.is_achromatic("#cc2222"))
        end)

        it("returns false for blue", function()
            assert.is_false(Color.is_achromatic("#2244cc"))
        end)
    end)
end)
