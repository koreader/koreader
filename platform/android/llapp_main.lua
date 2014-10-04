local A = require("android")
A.dl.library_path = A.dl.library_path .. ":" .. A.dir .. "/libs"

ARGV = {"-d", "/sdcard"}
dofile(A.dir.."/reader.lua")
