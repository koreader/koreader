describe("Readerview module", function()
    local DocumentRegistry, Blitbuffer, ReaderUI, UIManager, Event, Screen

    setup(function()
        require("commonrequire")
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        Blitbuffer = require("ffi/blitbuffer")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
        Event = require("ui/event")
        Screen = require("device").screen
    end)

    it("should stop hinting on document close event", function()
        local sample_epub = "spec/front/unit/data/leaves.epub"
        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
        for i = #UIManager._task_queue, 1, -1 do
            local task = UIManager._task_queue[i]
            if task.action == readerui.view.emitHintPageEvent then
                error("UIManager's task queue should be empty.")
            end
        end

        local bb = Blitbuffer.new(1000, 1000)
        readerui.view:drawSinglePage(bb, 0, 0)

        local found = false
        for i = #UIManager._task_queue, 1, -1 do
            local task = UIManager._task_queue[i]
            if task.action == readerui.view.emitHintPageEvent then
                found = true
            end
        end
        assert.is.truthy(found)

        readerui:onClose()

        for i = #UIManager._task_queue, 1, -1 do
            local task = UIManager._task_queue[i]
            if task.action == readerui.view.emitHintPageEvent then
                error("UIManager's task queue should be empty.")
            end
        end

        if readerui.document then
            readerui:closeDocument()
        end
    end)

    it("should return and restore view context in page mode", function()
        -- we don't want a footer for this test
        G_reader_settings:saveSetting("reader_footer_mode", 0)
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        readerui:handleEvent(Event:new("SetScrollMode", false))
        readerui.zooming:setZoomMode("page")
        local view = readerui.view
        local ctx = view:getViewContext()
        local zoom = ctx[1].zoom
        ctx[1].zoom = nil
        local saved_ctx = {
            {
                page = 1,
                pos = 0,
                gamma = 1,
                offset = {
                    x = 17, y = 0,
                    h = 0, w = 0,
                },
                rotation = 0,
            },
            -- visible_area
            {
                x = 0, y = 0,
                h = 800, w = 566,
            },
            -- page_area
            {
                x = 0, y = 0,
                h = 800, w = 566,
            },
        }
        assert.are.same(saved_ctx, ctx)
        assert.is.near(0.95024316487116200491, zoom, 0.0001)

        assert.is.same(view.state.page, 1)
        assert.is.same(view.visible_area.x, 0)
        assert.is.same(view.visible_area.y, 0)
        saved_ctx[1].page = 2
        saved_ctx[1].zoom = zoom
        saved_ctx[2].y = 10
        view:restoreViewContext(saved_ctx)
        assert.is.same(view.state.page, 2)
        assert.is.same(view.visible_area.x, 0)
        assert.is.same(view.visible_area.y, 10)
        G_reader_settings:delSetting("reader_footer_mode")
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should return and restore view context in scroll mode", function()
        -- we don't want a footer for this test
        G_reader_settings:saveSetting("reader_footer_mode", 0)
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        readerui:handleEvent(Event:new("SetScrollMode", true))
        readerui:handleEvent(Event:new("SetZoomMode", "page"))
        readerui.zooming:setZoomMode("page")
        local view = readerui.view
        local ctx = view:getViewContext()
        local zoom = ctx[1].zoom
        ctx[1].zoom = nil
        local saved_ctx = {
            {
                 gamma = 1,
                 offset = {x = 17, y = 0},
                 page = 1,
                 page_area = {
                     h = 800,
                     w = 566,
                     x = 0,
                     y = 0,
                 },
                 rotation = 0,
                 visible_area = {
                     h = 800,
                     w = 566,
                     x = 0,
                     y = 0,
                 },
            },
        }

        assert.are.same(saved_ctx, ctx)
        assert.is.near(0.95024316487116200491, zoom, 0.0001)

        assert.is.same(view.state.page, 1)
        assert.is.same(view.visible_area.x, 0)
        assert.is.same(view.visible_area.y, 0)
        saved_ctx[1].page = 2
        saved_ctx[1].zoom = zoom
        saved_ctx[1].visible_area.y = 10
        view:restoreViewContext(saved_ctx)
        assert.is.same(#view.page_states, 1)
        assert.is.same(view.page_states[1].page, 2)
        assert.is.same(view.page_states[1].visible_area.x, 0)
        assert.is.same(view.page_states[1].visible_area.y, 10)
        G_reader_settings:delSetting("reader_footer_mode")
        readerui:closeDocument()
        readerui:onClose()
    end)
end)
