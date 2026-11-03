describe("Readerzooming module", function()
    local ReaderZooming

    setup(function()
        require("commonrequire")
        disable_plugins()
        ReaderZooming = require("apps/reader/modules/readerzooming")
    end)

    local function new_zooming(page_width, page_height, threshold, rotation)
        local zooming = ReaderZooming:new{
            rotation = rotation or 0,
            auto_zoom_aspect_ratio = threshold or 1.5,
            ui = {
                document = {
                    getNativePageDimensions = function()
                        return { w = page_width, h = page_height }
                    end,
                },
            },
        }
        return zooming
    end

    describe("Auto mode page classification", function()
        it("treats portrait pages as normal pages", function()
            local zooming = new_zooming(612, 792)
            assert.are.equal("page", zooming:getAutoZoomMode(1))
        end)

        it("treats pages at the threshold as spreads", function()
            local zooming = new_zooming(1188, 792)
            assert.are.equal("columns", zooming:getAutoZoomMode(1))
        end)

        it("supports a user-defined spread threshold", function()
            local zooming = new_zooming(1188, 792, 1.6)
            assert.are.equal("page", zooming:getAutoZoomMode(1))
        end)

        it("classifies pages using their rotated dimensions", function()
            local zooming = new_zooming(792, 1224, 1.5, 90)
            assert.are.equal("columns", zooming:getAutoZoomMode(1))
        end)
    end)

    describe("Auto mode zoom", function()
        local function zoom_for_overlap(overlap)
            local zooming = new_zooming(1224, 792)
            zooming.zoom_mode = "auto"
            zooming.effective_zoom_mode = "columns"
            zooming.zoom_overlap_h = overlap
            zooming.dimen = { w = 612, h = 792 }
            zooming.ui.dimen = zooming.dimen
            zooming.ui.view = {
                footer_visible = false,
                footer = { settings = { reclaim_height = true } },
            }
            zooming.ui.document.configurable = { trim_page = 3 }
            zooming.ui.doc_settings = {
                readSetting = function() return nil end,
            }
            zooming.view = {
                onBBoxUpdate = function() end,
            }
            return zooming:getZoom(1)
        end

        it("fits a two-panel spread without overlap", function()
            assert.is.near(1, zoom_for_overlap(0), 0.0001)
        end)

        it("increases overlap without changing the panel count", function()
            local no_overlap = zoom_for_overlap(0)
            local overlap = zoom_for_overlap(40)
            assert.is.near(0.8, overlap, 0.0001)
            assert.is_true(overlap < no_overlap)
            assert.is_true(overlap > 0)
        end)

        it("uses native dimensions for panel count when content is cropped", function()
            local zooming = new_zooming(1224, 792)
            zooming.zoom_mode = "auto"
            zooming.effective_zoom_mode = "columns"
            zooming.zoom_overlap_h = 40
            zooming.dimen = { w = 612, h = 792 }
            zooming.ui.dimen = zooming.dimen
            zooming.ui.view = {
                footer_visible = false,
                footer = { settings = { reclaim_height = true } },
            }
            zooming.ui.document.configurable = { trim_page = 0 }
            zooming.ui.document.getUsedBBoxDimensions = function()
                return { w = 1224, h = 500 }
            end
            zooming.ui.doc_settings = {
                readSetting = function() return nil end,
            }
            zooming.view = {
                onBBoxUpdate = function() end,
            }

            assert.is.near((792 / 500) * 0.8, zooming:getZoom(1), 0.0001)
        end)

        it("uses four panels for a page twice as wide as a spread", function()
            local zooming = new_zooming(2480, 800)
            zooming.zoom_mode = "auto"
            zooming.effective_zoom_mode = "columns"
            zooming.zoom_overlap_h = 0
            zooming.dimen = { w = 620, h = 800 }
            zooming.ui.dimen = zooming.dimen
            zooming.ui.view = {
                footer_visible = false,
                footer = { settings = { reclaim_height = true } },
            }
            zooming.ui.document.configurable = { trim_page = 3 }
            zooming.ui.doc_settings = {
                readSetting = function() return nil end,
            }
            zooming.view = {
                onBBoxUpdate = function() end,
            }

            assert.is.near(1, zooming:getZoom(1), 0.0001)
        end)

        it("fits an unrotated spread vertically on a landscape screen", function()
            local zooming = new_zooming(1224, 792)
            zooming.zoom_mode = "auto"
            zooming.effective_zoom_mode = "columns"
            zooming.zoom_overlap_h = 0
            zooming.dimen = { w = 1200, h = 800 }
            zooming.ui.dimen = zooming.dimen
            zooming.ui.view = {
                footer_visible = false,
                footer = { settings = { reclaim_height = true } },
            }
            zooming.ui.document.configurable = { trim_page = 3 }
            zooming.ui.doc_settings = {
                readSetting = function() return nil end,
            }
            zooming.view = {
                onBBoxUpdate = function() end,
            }

            assert.is.near(800 / 792, zooming:getZoom(1), 0.0001)
        end)

        it("does not apply spread overlap to portrait pages", function()
            local zooming = new_zooming(612, 792)
            zooming.zoom_mode = "auto"
            zooming.effective_zoom_mode = "page"
            zooming.zoom_overlap_h = 84
            zooming.dimen = { w = 612, h = 792 }
            zooming.ui.dimen = zooming.dimen
            zooming.ui.view = {
                footer_visible = false,
                footer = { settings = { reclaim_height = true } },
            }
            zooming.ui.document.configurable = { trim_page = 3 }
            zooming.ui.doc_settings = {
                readSetting = function() return nil end,
            }
            zooming.view = {
                onBBoxUpdate = function() end,
            }

            assert.is.near(1, zooming:getZoom(1), 0.0001)
        end)

        it("fits rotated spreads to the available vertical space", function()
            local zooming = new_zooming(1224, 792, 1.5, 90)
            zooming.zoom_mode = "auto"
            zooming.effective_zoom_mode = "columns"
            zooming.zoom_overlap_h = 0
            zooming.dimen = { w = 800, h = 600 }
            zooming.ui.dimen = zooming.dimen
            zooming.ui.view = {
                footer_visible = false,
                footer = { settings = { reclaim_height = true } },
            }
            zooming.ui.document.configurable = { trim_page = 3 }
            zooming.ui.doc_settings = {
                readSetting = function() return nil end,
            }
            zooming.view = {
                onBBoxUpdate = function() end,
            }

            assert.is.near(600 / 1224, zooming:getZoom(1), 0.0001)
        end)
    end)
end)
