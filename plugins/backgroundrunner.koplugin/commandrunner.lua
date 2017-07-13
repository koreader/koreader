local logger = require("logger")

local CommandRunner = {
    pio = nil,
    job = nil,
}

function CommandRunner:start(job)
    assert(self ~= nil)
    assert(self.pio == nil)
    assert(self.job == nil)
    self.job = job
    self.job.start_sec = os.time()
    assert(type(self.job.executable) == "string")
    self.pio = io.popen("sh plugins/backgroundrunner.koplugin/luawrapper.sh " ..
                        "\"" .. self.job.executable .. "\"")
end

--- Polls the status of self.pio.
-- @return a table contains the result from luawrapper.sh. Returns nil if the
--         command has not been finished.
function CommandRunner:poll()
    assert(self ~= nil)
    assert(self.pio ~= nil)
    assert(self.job ~= nil)
    local line = self.pio:read()
    if line == "" then
        return nil
    else
        if line == nil then
            -- The binary crashes without output. This should not happen.
            self.job.result = 223
        else
            line = line .. self.pio:read("*a")
            logger.dbg("CommandRunner: Receive output " .. line)
            local status, result = pcall(loadstring(line))
            if status and result ~= nil then
                for k, v in pairs(result) do
                    self.job[k] = v
                end
            else
                -- The output from binary is invalid.
                self.job.result = 222
            end
        end
        self.pio:close()
        self.pio = nil
        self.job.end_sec = os.time()
        local job = self.job
        self.job = nil
        return job
    end
end

--- Whether this is a running job.
-- @treturn boolean
function CommandRunner:pending()
    assert(self ~= nil)
    return self.pio ~= nil
end

return CommandRunner
