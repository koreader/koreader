-- qtfb_keep_alive.lua
-- Background process to keep the QTFB socket connection active across KOReader restarts.
-- This prevents the rm-appload launcher from destroying the QML window canvas.

local ffi = require("ffi")
require("ffi/posix_h")
local qtfb = require("ffi/qtfb")
local C = ffi.C

local key_str = os.getenv("QTFB_KEY")
local key = key_str and tonumber(key_str) or 245209899 -- QTFB_DEFAULT_FRAMEBUFFER

local shmType = 0 -- FBFMT_RM2FB as default
if qtfb.is_rmpp then
    shmType = 3 -- FBFMT_RMPP_RGB565
elseif qtfb.is_rmppm then
    shmType = 6 -- FBFMT_RMPPM_RGB565
end

-- Create UNIX domain socket
local sock = C.socket(C.AF_UNIX, C.SOCK_SEQPACKET, 0)
assert(sock >= 0, "Failed to create UNIX socket")

local addr = ffi.new("struct sockaddr_un", C.AF_UNIX, "/tmp/qtfb.sock")

-- Retry loop to wait for the QTFB server (xochitl/rm-appload) to start listening
while C.connect(sock, ffi.cast("const struct sockaddr *", addr), ffi.sizeof(addr)) ~= 0 do
    C.sleep(1)
end

-- Send MESSAGE_INITIALIZE (0)
local initMsg = ffi.new("struct ClientMessage")
initMsg.type = qtfb.MESSAGE_INITIALIZE
initMsg.init.framebufferKey = key
initMsg.init.framebufferType = shmType

local bytes_sent = C.send(sock, initMsg, ffi.sizeof(initMsg), 0)
assert(bytes_sent >= 0, "Failed to send init message to QTFB server")

-- Keep the socket open indefinitely until killed by the parent process.
-- C.sleep is wrapped in a loop because signals (e.g. SIGCHLD) interrupt C.sleep.
while true do
    C.sleep(86400)
end
