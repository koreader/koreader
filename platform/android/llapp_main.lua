local A = require("android")
A.dl.library_path = A.dl.library_path .. ":" .. A.dir .. "/libs"
A.log_name = 'KOReader'

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

-- update koreader from ota
local function update()
    local new_update = "/sdcard/koreader/ota/koreader.update.tar"
    local installed = "/sdcard/koreader/ota/koreader.installed.tar"
    local update_file = io.open(new_update, "r")
    if update_file ~= nil then
        io.close(update_file)
        A.showProgress()
        if os.execute("tar xf " .. new_update) == 0 then
            os.execute("mv " .. new_update .. " " .. installed)
        end
        A.dismissProgress()
    end

end

-- (Disabled, since we hide navbar on start now no need for this hack)
-- run koreader patch before koreader startup
pcall(dofile, "/sdcard/koreader/patch.lua")

-- set proper permission for sdcv
A.execute("chmod", "755", "./sdcv")
A.execute("chmod", "755", "./tar")
A.execute("chmod", "755", "./zsync")

-- set TESSDATA_PREFIX env var
ffi.C.putenv("TESSDATA_PREFIX=/sdcard/koreader/data")

-- create fake command-line arguments
arg = {"-d", file or "/sdcard"}
dofile(A.dir.."/reader.lua")
