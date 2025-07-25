-- Set search path for `require()`.
package.path =
    "common/?.lua;frontend/?.lua;plugins/exporter.koplugin/?.lua;" ..
    package.path
package.cpath =
    "common/?.so;common/?.dll;/usr/lib/lua/?.so;" ..
    package.cpath

-- Add custom searcher for plugins folder modules
table.insert(package.loaders, 2, function(modulename)
    -- Handle modules in plugins folder, e.g., "plugins/cloudstorage.koplugin/synccommon"
    if modulename:match("^plugins/[^/]+%.koplugin/") then
        local filename = modulename .. ".lua"
        local file = io.open(filename, "r")
        if file then
            file:close()
            return assert(loadfile(filename))
        else
            return string.format("\n\tno file '%s'", filename)
        end
    end
    -- Not a plugins module, return nil to continue with other loaders
    return nil
end)

-- Setup `ffi.load` override and 'loadlib' helper.
require("ffi/loadlib")
