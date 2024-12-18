describe("ReaderScreenshot module", function()
    local DataStorage, DocumentRegistry, ReaderUI, lfs, UIManager, Event, Screen
    local readerui

    setup(function()
        require("commonrequire")
        disable_plugins()
        DataStorage = require("datastorage")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        lfs = require("libs/libkoreader-lfs")
        UIManager = require("ui/uimanager")
        Event = require("ui/event")
        Screen = require("device").screen

        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument("spec/front/unit/data/sample.txt"),
        }
    end)

    teardown(function()
        readerui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT))
        readerui:onClose()
    end)

    after_each(function()
        UIManager:quit()
    end)

    it("should get screenshot in portrait", function()
        local name = DataStorage:getDataDir() .. "/screenshots/reader_screenshot_portrait.png"
        readerui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT))
        UIManager:show(readerui)
        fastforward_ui_events()
        readerui.screenshot:onScreenshot(name)
        assert.truthy(lfs.attributes(name, "mode"))
    end)

    it("should get screenshot in landscape", function()
        local name = DataStorage:getDataDir() .. "/screenshots/reader_screenshot_landscape.png"
        readerui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_CLOCKWISE))
        UIManager:show(readerui)
        fastforward_ui_events()
        readerui.screenshot:onScreenshot(name)
        assert.truthy(lfs.attributes(name, "mode"))
    end)
end)
