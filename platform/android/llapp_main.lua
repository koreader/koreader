local A = require("android")
A.dl.library_path = A.dl.library_path .. ":" .. A.dir .. "/libs"

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

-- create fake command-line arguments
arg = {"-d", file or "/sdcard"}
dofile(A.dir.."/reader.lua")
