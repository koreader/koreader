local A = require("android")
A.dl.library_path = A.dl.library_path .. ":" .. A.dir .. "/libs"

local ffi = require("ffi")
ffi.cdef[[
    char *getenv(const char *name);
    int putenv(const char *envvar);
]]

-- check uri of the intent that starts this application
local file = A.jni:context(A.app.activity.vm, function(JNI)
    local uri = JNI:callObjectMethod(
        JNI:callObjectMethod(
            A.app.activity.clazz,
            "getIntent",
            "()Landroid/content/Intent;"
        ),
        "getData",
        "()Landroid/net/Uri;"
    )
    if uri ~= nil then
        local path = JNI:callObjectMethod(
            uri,
            "getPath",
            "()Ljava/lang/String;"
        )
        return JNI:to_string(path)
    end
end)
A.LOGI("intent file path " .. (file or ""))

-- run koreader patch before koreader startup
pcall(function() dofile("/sdcard/koreader/patch.lua") end)

-- set proper permission for sdcv
A.execute("chmod", "755", "./sdcv")

-- set TESSDATA_PREFIX env var
ffi.C.putenv("TESSDATA_PREFIX=/sdcard/koreader/data")

-- create fake command-line arguments
arg = {"-d", file or "/sdcard"}
dofile(A.dir.."/reader.lua")
