require("commonrequire")
local DocumentRegistry = require("document/documentregistry")
local Blitbuffer = require("ffi/blitbuffer")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")

describe("Readerview module", function()
    it("should stop hinting on document close event", function()
        local sample_epub = "spec/front/unit/data/leaves.epub"
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
        for i = #UIManager._task_queue, 1, -1 do
            local task = UIManager._task_queue[i]
            if task.action == readerui.view.emitHintPageEvent then
                error("UIManager's task queue should be emtpy.")
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

        assert.is.falsy(readerui.view.hinting)
        for i = #UIManager._task_queue, 1, -1 do
            local task = UIManager._task_queue[i]
            if task.action == readerui.view.emitHintPageEvent then
                error("UIManager's task queue should be emtpy.")
            end
        end
    end)
end)
