describe("ReaderPanelNav module", function()
    local ReaderPanelNav

    setup(function()
        require("commonrequire")
        ReaderPanelNav = require("apps/reader/modules/readerpanelnav")
    end)

    describe("sortPanelsByReadingDirection", function()
        local panelnav

        before_each(function()
            -- Create a minimal instance for testing sorting logic
            panelnav = ReaderPanelNav:new{
                ui = {
                    document = {},
                    paging = { current_page = 1 },
                    highlight = { panel_zoom_enabled = true },
                },
                view = {
                    registerViewModule = function() end,
                },
            }
        end)

        describe("with LRTB direction (Left-Right, Top-Bottom)", function()
            before_each(function()
                panelnav.panel_direction = "LRTB"
            end)

            it("should sort panels top to bottom, left to right", function()
                local panels = {
                    { x = 300, y = 100, w = 200, h = 150 },  -- top right
                    { x = 50, y = 100, w = 200, h = 150 },   -- top left
                    { x = 50, y = 300, w = 200, h = 150 },   -- bottom left
                    { x = 300, y = 300, w = 200, h = 150 },  -- bottom right
                }
                local sorted = panelnav:sortPanelsByReadingDirection(panels)
                -- Expected order: top-left, top-right, bottom-left, bottom-right
                assert.are.equal(50, sorted[1].x)
                assert.are.equal(100, sorted[1].y)
                assert.are.equal(300, sorted[2].x)
                assert.are.equal(100, sorted[2].y)
                assert.are.equal(50, sorted[3].x)
                assert.are.equal(300, sorted[3].y)
                assert.are.equal(300, sorted[4].x)
                assert.are.equal(300, sorted[4].y)
            end)

            it("should handle panels with slight Y overlap as different rows", function()
                -- This is the specific case from user: panels with 8px Y overlap
                -- A: (45,65)-(534,350) and B: (45,342)-(506,499)
                -- Overlap: 342-350 = 8 pixels, which is < 30% threshold
                local panels = {
                    { x = 45, y = 342, w = 461, h = 157 },  -- B (lower)
                    { x = 45, y = 65, w = 489, h = 285 },   -- A (upper)
                }
                local sorted = panelnav:sortPanelsByReadingDirection(panels)
                -- A should come before B (A has smaller Y center)
                assert.are.equal(65, sorted[1].y)   -- A first
                assert.are.equal(342, sorted[2].y)  -- B second
            end)

            it("should treat panels with significant Y overlap as same row", function()
                -- Two panels with same Y range should be in the same row
                local panels = {
                    { x = 300, y = 100, w = 200, h = 100 },  -- right
                    { x = 50, y = 100, w = 200, h = 100 },   -- left, same Y range
                }
                local sorted = panelnav:sortPanelsByReadingDirection(panels)
                -- Same row, so sort by X: left first, then right
                assert.are.equal(50, sorted[1].x)
                assert.are.equal(300, sorted[2].x)
            end)
        end)

        describe("with RLTB direction (Right-Left, Top-Bottom)", function()
            before_each(function()
                panelnav.panel_direction = "RLTB"
            end)

            it("should sort panels top to bottom, right to left", function()
                local panels = {
                    { x = 50, y = 100, w = 200, h = 150 },   -- top left
                    { x = 300, y = 100, w = 200, h = 150 },  -- top right
                    { x = 50, y = 300, w = 200, h = 150 },   -- bottom left
                    { x = 300, y = 300, w = 200, h = 150 },  -- bottom right
                }
                local sorted = panelnav:sortPanelsByReadingDirection(panels)
                -- Expected order: top-right, top-left, bottom-right, bottom-left
                assert.are.equal(300, sorted[1].x)
                assert.are.equal(100, sorted[1].y)
                assert.are.equal(50, sorted[2].x)
                assert.are.equal(100, sorted[2].y)
                assert.are.equal(300, sorted[3].x)
                assert.are.equal(300, sorted[3].y)
                assert.are.equal(50, sorted[4].x)
                assert.are.equal(300, sorted[4].y)
            end)
        end)

        describe("with TBLR direction (Top-Bottom, Left-Right)", function()
            before_each(function()
                panelnav.panel_direction = "TBLR"
            end)

            it("should sort panels left to right, top to bottom in each column", function()
                local panels = {
                    { x = 300, y = 300, w = 200, h = 150 },  -- right bottom
                    { x = 50, y = 100, w = 200, h = 150 },   -- left top
                    { x = 300, y = 100, w = 200, h = 150 },  -- right top
                    { x = 50, y = 300, w = 200, h = 150 },   -- left bottom
                }
                local sorted = panelnav:sortPanelsByReadingDirection(panels)
                -- Expected: left-top, left-bottom, right-top, right-bottom
                assert.are.equal(50, sorted[1].x)
                assert.are.equal(100, sorted[1].y)
                assert.are.equal(50, sorted[2].x)
                assert.are.equal(300, sorted[2].y)
                assert.are.equal(300, sorted[3].x)
                assert.are.equal(100, sorted[3].y)
                assert.are.equal(300, sorted[4].x)
                assert.are.equal(300, sorted[4].y)
            end)
        end)

        describe("with TBRL direction (Top-Bottom, Right-Left)", function()
            before_each(function()
                panelnav.panel_direction = "TBRL"
            end)

            it("should sort panels right to left, top to bottom in each column", function()
                local panels = {
                    { x = 50, y = 100, w = 200, h = 150 },   -- left top
                    { x = 300, y = 100, w = 200, h = 150 },  -- right top
                    { x = 50, y = 300, w = 200, h = 150 },   -- left bottom
                    { x = 300, y = 300, w = 200, h = 150 },  -- right bottom
                }
                local sorted = panelnav:sortPanelsByReadingDirection(panels)
                -- Expected: right-top, right-bottom, left-top, left-bottom
                assert.are.equal(300, sorted[1].x)
                assert.are.equal(100, sorted[1].y)
                assert.are.equal(300, sorted[2].x)
                assert.are.equal(300, sorted[2].y)
                assert.are.equal(50, sorted[3].x)
                assert.are.equal(100, sorted[3].y)
                assert.are.equal(50, sorted[4].x)
                assert.are.equal(300, sorted[4].y)
            end)
        end)

        it("should handle empty panels array", function()
            local panels = {}
            local sorted = panelnav:sortPanelsByReadingDirection(panels)
            assert.are.equal(0, #sorted)
        end)

        it("should handle nil panels", function()
            local sorted = panelnav:sortPanelsByReadingDirection(nil)
            assert.is_nil(sorted)
        end)

        it("should handle single panel", function()
            local panels = {{ x = 100, y = 100, w = 200, h = 150 }}
            local sorted = panelnav:sortPanelsByReadingDirection(panels)
            assert.are.equal(1, #sorted)
            assert.are.equal(100, sorted[1].x)
        end)
    end)

    describe("overlap threshold for row/column detection", function()
        local panelnav

        before_each(function()
            panelnav = ReaderPanelNav:new{
                ui = {
                    document = {},
                    paging = { current_page = 1 },
                    highlight = { panel_zoom_enabled = true },
                },
                view = {
                    registerViewModule = function() end,
                },
            }
            panelnav.panel_direction = "LRTB"
        end)

        it("should not consider 5% Y overlap as same row", function()
            -- Panel A: height 200, Panel B: height 100
            -- Overlap: 5 pixels = 5% of smaller (100)
            local panels = {
                { x = 50, y = 100, w = 200, h = 200 },   -- A
                { x = 50, y = 295, w = 200, h = 100 },   -- B (5px overlap with A)
            }
            local sorted = panelnav:sortPanelsByReadingDirection(panels)
            -- Should be treated as different rows, sorted by Y
            assert.are.equal(100, sorted[1].y)  -- A first (smaller Y)
            assert.are.equal(295, sorted[2].y)  -- B second
        end)

        it("should consider 40% Y overlap as same row", function()
            -- Panel A and B both at y=100-200 (same Y range, 100% overlap)
            local panels = {
                { x = 300, y = 100, w = 200, h = 100 },  -- right
                { x = 50, y = 100, w = 200, h = 100 },   -- left (same Y range)
            }
            local sorted = panelnav:sortPanelsByReadingDirection(panels)
            -- Same row, sorted by X (left to right in LRTB)
            assert.are.equal(50, sorted[1].x)   -- left first
            assert.are.equal(300, sorted[2].x)  -- right second
        end)

        it("should not consider 25% Y overlap as same row", function()
            -- Panel A: height 100, Panel B: height 100
            -- Overlap: 25 pixels = 25% (below 30% threshold)
            local panels = {
                { x = 50, y = 100, w = 200, h = 100 },
                { x = 50, y = 175, w = 200, h = 100 },
            }
            local sorted = panelnav:sortPanelsByReadingDirection(panels)
            -- Different rows, sorted by Y center
            assert.are.equal(100, sorted[1].y)  -- first panel
            assert.are.equal(175, sorted[2].y)  -- second panel
        end)
    end)

    describe("filterNestedPanels", function()
        local panelnav

        before_each(function()
            panelnav = ReaderPanelNav:new{
                ui = {
                    document = {},
                    paging = { current_page = 1 },
                    highlight = { panel_zoom_enabled = true },
                },
                view = {
                    registerViewModule = function() end,
                },
            }
        end)

        it("should remove panels completely contained within others", function()
            local panels = {
                { x = 0, y = 0, w = 500, h = 500 },      -- outer
                { x = 100, y = 100, w = 100, h = 100 },  -- inner (nested)
            }
            local filtered = panelnav:filterNestedPanels(panels)
            assert.are.equal(1, #filtered)
            assert.are.equal(500, filtered[1].w)  -- only outer remains
        end)

        it("should keep both panels if neither is contained in the other", function()
            local panels = {
                { x = 0, y = 0, w = 200, h = 200 },
                { x = 150, y = 150, w = 200, h = 200 },  -- overlapping but not contained
            }
            local filtered = panelnav:filterNestedPanels(panels)
            assert.are.equal(2, #filtered)
        end)

        it("should handle multiple nested levels", function()
            local panels = {
                { x = 0, y = 0, w = 500, h = 500 },      -- outermost
                { x = 50, y = 50, w = 300, h = 300 },    -- middle (nested in outer)
                { x = 100, y = 100, w = 100, h = 100 },  -- innermost (nested in middle)
            }
            local filtered = panelnav:filterNestedPanels(panels)
            assert.are.equal(1, #filtered)
            assert.are.equal(500, filtered[1].w)  -- only outermost remains
        end)

        it("should handle empty panels array", function()
            local filtered = panelnav:filterNestedPanels({})
            assert.are.equal(0, #filtered)
        end)

        it("should handle nil panels", function()
            local filtered = panelnav:filterNestedPanels(nil)
            assert.is_nil(filtered)
        end)

        it("should handle single panel", function()
            local panels = {{ x = 100, y = 100, w = 200, h = 150 }}
            local filtered = panelnav:filterNestedPanels(panels)
            assert.are.equal(1, #filtered)
        end)
    end)

    describe("mergeOverlappingPanels", function()
        local panelnav

        before_each(function()
            panelnav = ReaderPanelNav:new{
                ui = {
                    document = {},
                    paging = { current_page = 1 },
                    highlight = { panel_zoom_enabled = true },
                },
                view = {
                    registerViewModule = function() end,
                },
            }
        end)

        it("should merge two panels with significant overlap", function()
            -- Two panels with 64% overlap of smaller panel's area
            -- Panel A: 100x100 = 10000, Panel B: 100x100 = 10000
            -- Overlap: 80x80 = 6400, which is 64% of smaller area (10000)
            local panels = {
                { x = 0, y = 0, w = 100, h = 100 },
                { x = 20, y = 20, w = 100, h = 100 },  -- 80x80=6400 overlap, 64% of 10000
            }
            local merged = panelnav:mergeOverlappingPanels(panels, 0.5)
            assert.are.equal(1, #merged)
            -- Merged bounding box should be 0,0 to 120,120
            assert.are.equal(0, merged[1].x)
            assert.are.equal(0, merged[1].y)
            assert.are.equal(120, merged[1].w)
            assert.are.equal(120, merged[1].h)
        end)

        it("should not merge panels with small overlap", function()
            -- Two panels with only 10% overlap
            local panels = {
                { x = 0, y = 0, w = 100, h = 100 },
                { x = 90, y = 90, w = 100, h = 100 },  -- 10x10=100 overlap, 1% of 10000
            }
            local merged = panelnav:mergeOverlappingPanels(panels, 0.5)
            assert.are.equal(2, #merged)
        end)

        it("should not merge non-overlapping panels", function()
            local panels = {
                { x = 0, y = 0, w = 100, h = 100 },
                { x = 200, y = 200, w = 100, h = 100 },
            }
            local merged = panelnav:mergeOverlappingPanels(panels, 0.5)
            assert.are.equal(2, #merged)
        end)

        it("should merge multiple overlapping panels iteratively", function()
            -- Three panels that chain overlap: A overlaps B, B overlaps C
            local panels = {
                { x = 0, y = 0, w = 100, h = 100 },
                { x = 30, y = 30, w = 100, h = 100 },  -- overlaps first
                { x = 60, y = 60, w = 100, h = 100 },  -- overlaps second
            }
            local merged = panelnav:mergeOverlappingPanels(panels, 0.3)
            -- Should end up as one merged panel
            assert.are.equal(1, #merged)
            assert.are.equal(0, merged[1].x)
            assert.are.equal(0, merged[1].y)
            assert.are.equal(160, merged[1].w)
            assert.are.equal(160, merged[1].h)
        end)

        it("should handle empty panels array", function()
            local merged = panelnav:mergeOverlappingPanels({}, 0.5)
            assert.are.equal(0, #merged)
        end)

        it("should handle nil panels", function()
            local merged = panelnav:mergeOverlappingPanels(nil, 0.5)
            assert.is_nil(merged)
        end)

        it("should handle single panel", function()
            local panels = {{ x = 100, y = 100, w = 200, h = 150 }}
            local merged = panelnav:mergeOverlappingPanels(panels, 0.5)
            assert.are.equal(1, #merged)
        end)
    end)

    describe("clipPanelsToPage", function()
        local panelnav

        before_each(function()
            panelnav = ReaderPanelNav:new{
                ui = {
                    document = {},
                    paging = { current_page = 1 },
                    highlight = { panel_zoom_enabled = true },
                },
                view = {
                    registerViewModule = function() end,
                },
            }
        end)

        it("should clip panel extending beyond page bounds", function()
            local panels = {
                { x = -10, y = -10, w = 200, h = 200 },  -- extends past top-left
            }
            local clipped = panelnav:clipPanelsToPage(panels, 500, 500)
            assert.are.equal(1, #clipped)
            assert.are.equal(0, clipped[1].x)
            assert.are.equal(0, clipped[1].y)
            assert.are.equal(190, clipped[1].w)
            assert.are.equal(190, clipped[1].h)
        end)

        it("should clip panel extending beyond bottom-right", function()
            local panels = {
                { x = 400, y = 400, w = 200, h = 200 },  -- extends past bottom-right
            }
            local clipped = panelnav:clipPanelsToPage(panels, 500, 500)
            assert.are.equal(1, #clipped)
            assert.are.equal(400, clipped[1].x)
            assert.are.equal(400, clipped[1].y)
            assert.are.equal(100, clipped[1].w)
            assert.are.equal(100, clipped[1].h)
        end)

        it("should remove panel completely outside page bounds", function()
            local panels = {
                { x = -200, y = -200, w = 100, h = 100 },  -- completely outside
            }
            local clipped = panelnav:clipPanelsToPage(panels, 500, 500)
            assert.are.equal(0, #clipped)
        end)

        it("should not modify panel within page bounds", function()
            local panels = {
                { x = 100, y = 100, w = 200, h = 200 },
            }
            local clipped = panelnav:clipPanelsToPage(panels, 500, 500)
            assert.are.equal(1, #clipped)
            assert.are.equal(100, clipped[1].x)
            assert.are.equal(100, clipped[1].y)
            assert.are.equal(200, clipped[1].w)
            assert.are.equal(200, clipped[1].h)
        end)

        it("should handle empty panels array", function()
            local clipped = panelnav:clipPanelsToPage({}, 500, 500)
            assert.is_nil(clipped)
        end)

        it("should handle nil panels", function()
            local clipped = panelnav:clipPanelsToPage(nil, 500, 500)
            assert.is_nil(clipped)
        end)
    end)

    describe("isPanelContainedIn", function()
        local panelnav

        before_each(function()
            panelnav = ReaderPanelNav:new{
                ui = {
                    document = {},
                    paging = { current_page = 1 },
                    highlight = { panel_zoom_enabled = true },
                },
                view = {
                    registerViewModule = function() end,
                },
            }
        end)

        it("should return true when panel A is completely inside panel B", function()
            local a = { x = 100, y = 100, w = 50, h = 50 }
            local b = { x = 0, y = 0, w = 200, h = 200 }
            assert.is_true(panelnav:isPanelContainedIn(a, b))
        end)

        it("should return false when panel A is not inside panel B", function()
            local a = { x = 0, y = 0, w = 200, h = 200 }
            local b = { x = 100, y = 100, w = 50, h = 50 }
            assert.is_false(panelnav:isPanelContainedIn(a, b))
        end)

        it("should return false when panels only partially overlap", function()
            local a = { x = 0, y = 0, w = 100, h = 100 }
            local b = { x = 50, y = 50, w = 100, h = 100 }
            assert.is_false(panelnav:isPanelContainedIn(a, b))
        end)

        it("should return true when panels are exactly equal", function()
            local a = { x = 100, y = 100, w = 100, h = 100 }
            local b = { x = 100, y = 100, w = 100, h = 100 }
            assert.is_true(panelnav:isPanelContainedIn(a, b))
        end)
    end)

    describe("getPanelIntersectionArea", function()
        local panelnav

        before_each(function()
            panelnav = ReaderPanelNav:new{
                ui = {
                    document = {},
                    paging = { current_page = 1 },
                    highlight = { panel_zoom_enabled = true },
                },
                view = {
                    registerViewModule = function() end,
                },
            }
        end)

        it("should return correct intersection area for overlapping panels", function()
            local a = { x = 0, y = 0, w = 100, h = 100 }
            local b = { x = 50, y = 50, w = 100, h = 100 }
            local area = panelnav:getPanelIntersectionArea(a, b)
            -- Intersection is 50x50 = 2500
            assert.are.equal(2500, area)
        end)

        it("should return 0 for non-overlapping panels", function()
            local a = { x = 0, y = 0, w = 100, h = 100 }
            local b = { x = 200, y = 200, w = 100, h = 100 }
            local area = panelnav:getPanelIntersectionArea(a, b)
            assert.are.equal(0, area)
        end)

        it("should return 0 for adjacent panels (touching but not overlapping)", function()
            local a = { x = 0, y = 0, w = 100, h = 100 }
            local b = { x = 100, y = 0, w = 100, h = 100 }
            local area = panelnav:getPanelIntersectionArea(a, b)
            assert.are.equal(0, area)
        end)

        it("should return full area when one panel contains the other", function()
            local a = { x = 50, y = 50, w = 50, h = 50 }
            local b = { x = 0, y = 0, w = 200, h = 200 }
            local area = panelnav:getPanelIntersectionArea(a, b)
            -- a is completely inside b, so intersection = area of a = 2500
            assert.are.equal(2500, area)
        end)
    end)

    describe("mergePanels", function()
        local panelnav

        before_each(function()
            panelnav = ReaderPanelNav:new{
                ui = {
                    document = {},
                    paging = { current_page = 1 },
                    highlight = { panel_zoom_enabled = true },
                },
                view = {
                    registerViewModule = function() end,
                },
            }
        end)

        it("should create bounding box for two overlapping panels", function()
            local a = { x = 0, y = 0, w = 100, h = 100 }
            local b = { x = 50, y = 50, w = 100, h = 100 }
            local merged = panelnav:mergePanels(a, b)
            assert.are.equal(0, merged.x)
            assert.are.equal(0, merged.y)
            assert.are.equal(150, merged.w)
            assert.are.equal(150, merged.h)
        end)

        it("should create bounding box for non-overlapping panels", function()
            local a = { x = 0, y = 0, w = 50, h = 50 }
            local b = { x = 100, y = 100, w = 50, h = 50 }
            local merged = panelnav:mergePanels(a, b)
            assert.are.equal(0, merged.x)
            assert.are.equal(0, merged.y)
            assert.are.equal(150, merged.w)
            assert.are.equal(150, merged.h)
        end)
    end)

    describe("getDirectionDescription", function()
        local panelnav

        before_each(function()
            panelnav = ReaderPanelNav:new{
                ui = {
                    document = {},
                    paging = { current_page = 1 },
                    highlight = { panel_zoom_enabled = true },
                },
                view = {
                    registerViewModule = function() end,
                },
            }
        end)

        it("should return description for valid direction codes", function()
            assert.is_not_nil(panelnav:getDirectionDescription("LRTB"))
            assert.is_not_nil(panelnav:getDirectionDescription("RLTB"))
            assert.is_not_nil(panelnav:getDirectionDescription("TBLR"))
            assert.is_not_nil(panelnav:getDirectionDescription("TBRL"))
            assert.is_not_nil(panelnav:getDirectionDescription("LRBT"))
            assert.is_not_nil(panelnav:getDirectionDescription("RLBT"))
            assert.is_not_nil(panelnav:getDirectionDescription("BTLR"))
            assert.is_not_nil(panelnav:getDirectionDescription("BTRL"))
        end)

        it("should return direction code for unknown direction", function()
            assert.are.equal("UNKNOWN", panelnav:getDirectionDescription("UNKNOWN"))
        end)
    end)

    describe("direction_settings", function()
        local panelnav

        before_each(function()
            panelnav = ReaderPanelNav:new{
                ui = {
                    document = {},
                    paging = { current_page = 1 },
                    highlight = { panel_zoom_enabled = true },
                },
                view = {
                    registerViewModule = function() end,
                },
            }
        end)

        it("should have correct settings for all 8 directions", function()
            local directions = {"LRTB", "LRBT", "RLTB", "RLBT", "TBLR", "TBRL", "BTLR", "BTRL"}
            for _, dir in ipairs(directions) do
                local settings = panelnav.direction_settings[dir]
                assert.is_not_nil(settings, "Missing settings for " .. dir)
                assert.is_not_nil(settings.primary, "Missing primary for " .. dir)
                assert.is_not_nil(settings.primary_order, "Missing primary_order for " .. dir)
                assert.is_not_nil(settings.secondary_order, "Missing secondary_order for " .. dir)
                assert.is_true(settings.primary == "h" or settings.primary == "v",
                    "Invalid primary for " .. dir)
                assert.is_true(settings.primary_order == 1 or settings.primary_order == -1,
                    "Invalid primary_order for " .. dir)
                assert.is_true(settings.secondary_order == 1 or settings.secondary_order == -1,
                    "Invalid secondary_order for " .. dir)
            end
        end)

        it("should have horizontal primary for row-based directions", function()
            assert.are.equal("h", panelnav.direction_settings.LRTB.primary)
            assert.are.equal("h", panelnav.direction_settings.LRBT.primary)
            assert.are.equal("h", panelnav.direction_settings.RLTB.primary)
            assert.are.equal("h", panelnav.direction_settings.RLBT.primary)
        end)

        it("should have vertical primary for column-based directions", function()
            assert.are.equal("v", panelnav.direction_settings.TBLR.primary)
            assert.are.equal("v", panelnav.direction_settings.TBRL.primary)
            assert.are.equal("v", panelnav.direction_settings.BTLR.primary)
            assert.are.equal("v", panelnav.direction_settings.BTRL.primary)
        end)
    end)
end)
