local reader_order = require("ui/elements/reader_menu_order")
local filemanager_order = require("ui/elements/filemanager_menu_order")

-- May want to move to frontend/ui/elements

local PluginMenuInserter = {}

function PluginMenuInserter.add(name)
    table.insert(reader_order.more_tools, name)
    table.insert(filemanager_order.more_tools, name)
end

return PluginMenuInserter
