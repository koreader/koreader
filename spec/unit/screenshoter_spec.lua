require("commonrequire")
local DocumentRegistry = require("document/documentregistry")
local ReaderUI = require("apps/reader/readerui")
local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Event = require("ui/event")
local DEBUG = require("dbg")

describe("ReaderScreenshot module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui
    setup(function()
        readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
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
    end)
end)
