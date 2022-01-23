-- Stupid wrapper so that we can send simple ntx_io ioctls from shell scripts...

local ffi = require("ffi")
local bor = bit.bor
local C = ffi.C

require("ffi/posix_h")

assert(#arg == 2, "must pass an ioctl command & an ioctl argument")
local ioc_cmd = tonumber(arg[1])
local ioc_arg = tonumber(arg[2])

local fd = C.open("/dev/ntx_io", bor(C.O_RDONLY, C.O_NONBLOCK, C.O_CLOEXEC))
assert(fd ~= -1, "cannot open ntx_io character device")

assert(C.ioctl(fd, ioc_cmd, ffi.cast("int", ioc_arg)) == 0, "ioctl failed")

C.close(fd)
