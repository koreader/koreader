require("commonrequire")
local FileManager = require("apps/filemanager/filemanager")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local DEBUG = require("dbg")

describe("FileManager module", function()
    it("should show file manager", function()
        UIManager:quit()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "../../test",
        }
        UIManager:show(filemanager)
        UIManager:scheduleIn(1, function() UIManager:close(filemanager) end)
        UIManager:run()
    end)
end)
