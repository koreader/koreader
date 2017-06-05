describe("ReaderScreenshot module", function()
    local DocumentRegistry, ReaderUI, lfs, UIManager, Screen, Event
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui
    setup(function()
        require("commonrequire")
        DocumentRegistry = package.reload("document/documentregistry")
        Event = package.reload("ui/event")
        ReaderUI = package.reload("apps/reader/readerui")
        Screen = package.reload("device").screen
        UIManager = package.reload("ui/uimanager")
        lfs = require("libs/libkoreader-lfs")

        readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
    end)

    teardown(function()
        readerui:handleEvent(Event:new("ChangeScreenMode", "portrait"))
    end)

    it("should get screenshot in portrait", function()
        local name = "screenshots/reader_screenshot_portrait.png"
        readerui:handleEvent(Event:new("ChangeScreenMode", "portrait"))
        UIManager:quit()
        UIManager:show(readerui)
        UIManager:scheduleIn(1, function() UIManager:close(readerui) end)
        UIManager:run()
        readerui.screenshot:onScreenshot(name)
        assert.truthy(lfs.attributes(name, "mode"))
        UIManager:quit()
    end)

    it("should get screenshot in landscape", function()
        local name = "screenshots/reader_screenshot_landscape.png"
        readerui:handleEvent(Event:new("ChangeScreenMode", "landscape"))
        UIManager:quit()
        UIManager:show(readerui)
        UIManager:scheduleIn(2, function() UIManager:close(readerui) end)
        UIManager:run()
        readerui.screenshot:onScreenshot(name)
        assert.truthy(lfs.attributes(name, "mode"))
        UIManager:quit()
    end)
end)
