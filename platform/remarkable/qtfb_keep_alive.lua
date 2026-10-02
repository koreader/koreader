-- qtfb_keep_alive.lua
-- Background process to keep the QTFB socket connection active across KOReader restarts.
-- This prevents the rm-appload launcher from destroying the QML window canvas.

local ffi = require("ffi")
require("ffi/posix_h")
local qtfb = require("ffi/qtfb")
local C = ffi.C

local key_str = os.getenv("QTFB_KEY")
local key = key_str and tonumber(key_str) or 245209899 -- QTFB_DEFAULT_FRAMEBUFFER

local addr = ffi.new("struct sockaddr_un", C.AF_UNIX, "/tmp/qtfb.sock")

-- Connects to the QTFB server and asks for our framebuffer in the given format.
-- Returns the socket, or nil if the server refused that format.
local function qtfb_connect(shmType)
    -- Create UNIX domain socket
    local sock = C.socket(C.AF_UNIX, C.SOCK_SEQPACKET, 0)
    assert(sock >= 0, "Failed to create UNIX socket")

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

    -- Wait for the server's reply
    local respMsg = ffi.new("struct ServerMessage")
    if C.recv(sock, respMsg, ffi.sizeof(respMsg), 0) == 0 then
        -- Orderly close without a reply: that is how AppLoad refuses us.
        C.close(sock)
        return nil
    end
    return sock
end

-- Must be the format ffi/framebuffer_qtfb.lua asks for:
-- AppLoad refuses mismatched formats on the same key.
local sock = qtfb_connect(qtfb.fb_format)
if not sock and qtfb.fb_format_fallback then
    -- Same fallback as ffi/framebuffer_qtfb.lua
    sock = qtfb_connect(qtfb.fb_format_fallback)
end
assert(sock, "QTFB server refused our framebuffer format")

-- Keep the socket open indefinitely until killed by the parent process.
-- pause() blocks the process indefinitely until a signal is received.
ffi.cdef[[int pause(void);]]
while true do
    C.pause()
end
