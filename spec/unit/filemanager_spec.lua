require("commonrequire")
local FileManager = require("apps/filemanager/filemanager")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local DEBUG = require("dbg")

describe("FileManager module", function()
    it("should show file manager", function()
        FileManager:showFiles("../../test")
        UIManager:scheduleIn(1, function() UIManager:quit() end)
        UIManager:run()
    end)
end)
