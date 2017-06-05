local MockTime = {
    original_os_time = os.time,
    original_util_time = nil,
    value = os.time(),
}

function MockTime:install()
    assert(self ~= nil)
    local util = require("ffi/util")
    if self.original_util_time == nil then
        self.original_util_time = util.gettime
        assert(self.original_util_time ~= nil)
    end
    os.time = function() return self.value end
    util.gettime = function() return self.value, 0 end
end

function MockTime:uninstall()
    print("MockTime:uninstall()", debug.traceback())
    assert(self ~= nil)
    local util = require("ffi/util")
    os.time = self.original_os_time
    if self.original_util_time ~= nil then
        util.gettime = self.original_util_time
    end
end

function MockTime:set(value)
    assert(self ~= nil)
    if type(value) ~= "number" then
        return false
    end
    self.value = math.floor(value)
    return true
end

function MockTime:increase(value)
    assert(self ~= nil)
    if type(value) ~= "number" then
        return false
    end
    self.value = math.floor(self.value + value)
    return true
end

return MockTime
