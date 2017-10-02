local ffi = require("ffi")
local C = ffi.C

-- Utilities functions needed by this plugin, but that may be added to
-- existing base/ffi/ files
local xutil = {}


-- Sub-process management (may be put into base/ffi/util.lua)
function xutil.runInSubProcess(func)
    local pid = C.fork()
    if pid == 0 then -- child process
        -- Just run the provided lua code object in this new process,
        -- and exit immediatly (so we do not release drivers and
        -- resources still used by parent process)
        func()
        os.exit(0)
    end
    -- parent/main process, return pid of child
    if pid == -1 then -- On failure, -1 is returned in the parent
        return false
    end
    return pid
end

function xutil.isSubProcessDone(pid)
    local status = ffi.new('int[1]')
    local ret = C.waitpid(pid, status, 1) -- 1 = WNOHANG : don't wait, just tell
    -- status = tonumber(status[0])
    -- local logger = require("logger")
    -- logger.dbg("waitpid for", pid, ":", ret, "/", status)
    -- still running: ret = 0 , status = 0
    -- exited: ret = pid , status = 0 or 9 if killed
    -- no more running: ret = -1 , status = 0
    if ret == pid or ret == -1 then
        return true
    end
end

function xutil.terminateSubProcess(pid)
    local done = xutil.isSubProcessDone(pid)
    if not done then
        -- local logger = require("logger")
        -- logger.dbg("killing subprocess", pid)
        -- we kill with signal 9/SIGKILL, which may be violent, but ensures
        -- that it is terminated (a process may catch or ignore SIGTERM)
        C.kill(pid, 9)
        -- process will still have to be collected with calls to util.isSubProcessDone(),
        -- which may still return false for some small amount of time after our kill()
    end
end


-- Data compression/decompression of strings thru zlib (may be put in a new base/ffi/zlib.lua)
-- from http://luajit.org/ext_ffi_tutorial.html
ffi.cdef[[
unsigned long compressBound(unsigned long sourceLen);
int compress2(uint8_t *dest, unsigned long *destLen,
              const uint8_t *source, unsigned long sourceLen, int level);
int uncompress(uint8_t *dest, unsigned long *destLen,
               const uint8_t *source, unsigned long sourceLen);
]]
local zlib = ffi.load(ffi.os == "Windows" and "zlib1" or "z")

function xutil.zlib_compress(data)
    local n = zlib.compressBound(#data)
    local buf = ffi.new("uint8_t[?]", n)
    local buflen = ffi.new("unsigned long[1]", n)
    local res = zlib.compress2(buf, buflen, data, #data, 9)
    assert(res == 0)
    return ffi.string(buf, buflen[0])
end

function xutil.zlib_uncompress(zdata, datalen)
    local buf = ffi.new("uint8_t[?]", datalen)
    local buflen = ffi.new("unsigned long[1]", datalen)
    local res = zlib.uncompress(buf, buflen, zdata, #zdata)
    assert(res == 0)
    return ffi.string(buf, buflen[0])
end


-- Not provided by base/thirdparty/lua-ljsqlite3/init.lua
-- Add a timeout to a lua-ljsqlite3 connection
-- We need that if we have multiple processes accessing the same
-- SQLite db for reading or writting (read lock and write lock can't be
-- obtained at the same time, so waiting & retry is needed)
-- SQLite will retry getting a lock every 1ms to 100ms for
-- the timeout_ms given here
local sql = ffi.load("sqlite3")
function xutil.sqlite_set_timeout(conn, timeout_ms)
    sql.sqlite3_busy_timeout(conn._ptr, timeout_ms)
end
-- For reference, SQ3 doc at: http://scilua.org/ljsqlite3.html

return xutil
