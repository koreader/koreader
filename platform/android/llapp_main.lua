local A = require("android")
A.dl.library_path = A.dl.library_path .. ":" .. A.dir .. "/libs"

-- create fake command-line arguments
arg = {"-d", "/sdcard"}
dofile(A.dir.."/reader.lua")
