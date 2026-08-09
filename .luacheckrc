unused_args = false
std = "luajit"
-- ignore implicit self
self = false

globals = {
    "G_reader_settings",
    "G_defaults",
    "table.pack",
    "table.unpack",
}

read_globals = {
    "_ENV",
}

exclude_files = {
    "frontend/luxl.lua",
    "plugins/newsdownloader.koplugin/lib/handler.lua",
    "plugins/newsdownloader.koplugin/lib/LICENSE_LuaXML",
    "plugins/newsdownloader.koplugin/lib/xml.lua",
    "plugins/newsdownloader.koplugin/lib/LICENCE_lua-feedparser",
    "plugins/newsdownloader.koplugin/lib/dateparser.lua",
}

-- don't balk on busted stuff in spec
files["spec/unit/*"].std = "+busted"
files["spec/unit/*"].globals = {
    "package",
    "disable_plugins",
    "load_plugin",
    "fastforward_ui_events",
    "screenshot",
}

-- TODO: clean up and enforce max line width (631)
-- https://luacheck.readthedocs.io/en/stable/warnings.html
ignore = {
    "211/__*", -- Unused local variable
    "231/__",  -- Local variable is set but never accessed
    "631",     -- Line is too long
    "dummy",
}
