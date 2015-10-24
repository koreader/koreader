local A = require("android")
A.dl.library_path = A.dl.library_path .. ":" .. A.dir .. "/libs"

local ffi = require("ffi")
ffi.cdef[[
    char *getenv(const char *name);
    int putenv(const char *envvar);
    void *mmap(void *addr, size_t length, int prot, int flags, int fd, size_t offset);
    int munmap(void *addr, size_t length);
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

-- reservation enough mmap slots for mcode allocation
local reserved_slots = {}
for i = 1, 32 do
  local len = 0x80000 + i*0x2000
  local p = ffi.C.mmap(nil, len, 0x3, 0x22, -1, 0)
  A.LOGI("mmapped " ..  tostring(p))
  table.insert(reserved_slots, {p = p, len = len})
end
-- free the reservation immediately
for _, slot in ipairs(reserved_slots) do
  local res = ffi.C.munmap(slot.p, slot.len)
  A.LOGI("munmap " .. tostring(slot.p) .. " " .. res)
end
-- and allocate a large mcode segment, hopefully it will success.
require("jit.opt").start("sizemcode=512","maxmcode=512")
for i=1,100 do end  -- Force allocation of one large segment

-- run koreader patch before koreader startup
pcall(function() dofile("/sdcard/koreader/patch.lua") end)

-- set proper permission for sdcv
A.execute("chmod", "755", "./sdcv")

-- set TESSDATA_PREFIX env var
ffi.C.putenv("TESSDATA_PREFIX=/sdcard/koreader/data")

-- create fake command-line arguments
arg = {"-d", file or "/sdcard"}
dofile(A.dir.."/reader.lua")
