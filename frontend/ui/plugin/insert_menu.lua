local reader_order = require("ui/elements/reader_menu_order")
local filemanager_order = require("ui/elements/filemanager_menu_order")

-- A "hacky" way to update plugin menu items on-the-fly.
-- Use: require("plugins/insert_menu").add("my_plugin_menu_name")

-- This piece of logic / table is singleton in the KOReader process.
-- It provides a way to add a plugin into the "More Plugins" and is useful to
-- work with contrib/plugins which are not in the core logic of KOReader.
-- To avoid duplicating the menu item, caller is expected to call the add once
-- in the KOReader process, usually it's achieveable to rely on the "require"
-- function in lua.

local PluginMenuInserter = {}

function PluginMenuInserter.add(name)
    table.insert(reader_order.more_tools, name)
    table.insert(filemanager_order.more_tools, name)
end

return PluginMenuInserter
