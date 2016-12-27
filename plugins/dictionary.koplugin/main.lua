
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Dictionary = WidgetContainer:new{
    name = "dictionary",
    exclusive_in_reader = true,
}

function Dictionary:init()
    self.readerDictionary = ReaderDictionary:new{
        ui = self.ui
    }
end

return Dictionary
