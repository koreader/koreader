-- set search path for 'require()'
package.path =
    "common/?.lua;rocks/share/lua/5.1/?.lua;frontend/?.lua;" ..
    package.path
package.cpath =
    "common/?.so;common/?.dll;/usr/lib/lua/?.so;rocks/lib/lua/5.1/?.so;" ..
    package.cpath

-- set search path for 'ffi.load()'
local ffi = require("ffi")
ffi.cdef[[
    char *getenv(const char *name);
    int putenv(const char *envvar);
    int _putenv(const char *envvar);
]]
if ffi.os == "Windows" then
    ffi.C._putenv("PATH=libs;common;")
end
local ffi_load = ffi.load
-- patch ffi.load for thirdparty luajit libraries
ffi.load = function(lib)
    io.write("ffi.load: ", lib, "\n")
    local loaded, re = pcall(ffi_load, lib)
    if loaded then return re end

    local lib_path = package.searchpath(lib, "./lib?.so;./libs/lib?.so;./libs/lib?.so.1")

    if not lib_path then
        error('Not able to load dynamic library: ' .. lib)
    else
        io.write("ffi.load (assisted searchpath): ", lib_path, "\n")
        return ffi_load(lib_path)
    end
end
