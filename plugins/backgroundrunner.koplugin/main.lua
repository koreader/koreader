local CommandRunner = require("commandrunner")
local PluginShare = require("pluginshare")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

-- BackgroundRunner is an experimental feature to execute non-critical jobs in
-- background. A job is defined as a table in PluginShare.backgroundJobs table.
-- It contains at least following items:
-- when: number, string or function
--   number: the delay in seconds
--   string: "best-effort" - the job will be started when there is no other jobs
--                           to be executed.
--           "idle"        - the job will be started when the device is idle.
--   function: if the return value of the function is true, the job will be
--             executed immediately.
-- repeated: boolean or function or nil
--   boolean: true to repeated the job once it finished.
--   function: if the return value of the function is true, repeated the job
--             once it finished.
--   nil: same as false.
--   number: times to repeat.
-- executable: string or function
--   string: the command line to be executed. The command or binary will be
--           executed in the lowest priority. Command or binary will be killed
--           if it executes for over 1 hour.
--   function: the action to be executed. The execution cannot be killed, but it
--             will be considered as timeout if it executes for more than 1
--             second.
--   If the executable times out, the job will be blocked, i.e. the repeated
--   field will be ignored.
--
-- If a job does not contain enough information, it will be ignored.
--
-- Once the job is finished, several items will be added to the table:
-- result: number, the return value of the command. For function executable, if
--         the function throws an error, it will be 1, otherwise 0.
-- exception: error, the error returned from function executable. Not available
--            for string executable.
-- timeout: boolean, whether the command times out.
-- bad_command: boolean, whether the command is not found. Not available for
--              function executable.
-- blocked: boolean, whether the job is blocked.
-- start_sec: number, the os.time() when the job was started.
-- end_sec: number, the os.time() when the job was stopped.
-- insert_sec: number, the os.time() when the job was inserted into queue.

PluginShare.backgroundJobs = PluginShare.backgroundJobs or {}

local BackgroundRunner = {
    jobs = PluginShare.backgroundJobs,
}

--- Copies required fields from |job|.
-- @return a new table with required fields of a valid job.
function BackgroundRunner:_clone(job)
    assert(job ~= nil)
    local result = {}
    result.when = job.when
    result.repeated = job.repeated
    result.executable = job.executable
    return result
end

function BackgroundRunner:_shouldRepeat(job)
    if type(job.repeated) == "nil" then return false end
    if type(job.repeated) == "boolean" then return job.repeated end
    if type(job.repeated) == "function" then
        local status, result = pcall(job.repeated)
        if status then
            return result
        else
            return false
        end
    end
    if type(job.repeated) == "number" then
        job.repeated = job.repeated - 1
        return job.repeated > 0
    end

    return false
end

function BackgroundRunner:_finishJob(job)
    assert(self ~= nil)
    local timeout_sec = type(job.executable) == "string" and 3600 or 1
    job.timeout = ((job.end_sec - job.start_sec) > timeout_sec)
    job.blocked = job.timeout
    if not job.blocked and self:_shouldRepeat(job) then
        self:_insert(self:_clone(job))
    end
end

--- Executes |job|.
-- @treturn boolean true if job is valid.
function BackgroundRunner:_executeJob(job)
    assert(not CommandRunner:pending())
    if job == nil then return false end
    if job.executable == nil then return false end

    if type(job.executable) == "string" then
        CommandRunner:start(job)
        return true
    elseif type(job.executable) == "function" then
        job.start_sec = os.time()
        local status, err = pcall(job.executable)
        if status then
            job.result = 0
        else
            job.result = 1
            job.exception = err
        end
        job.end_sec = os.time()
        self:_finishJob(job)
        return true
    else
        return false
    end
end

--- Polls the status of the pending CommandRunner.
function BackgroundRunner:_poll()
    assert(self ~= nil)
    assert(CommandRunner:pending())
    local result = CommandRunner:poll()
    if result == nil then return end

    self:_finishJob(result)
end

function BackgroundRunner:_execute()
    logger.dbg("BackgroundRunner: _execute() @ ", os.time())
    assert(self ~= nil)
    if CommandRunner:pending() then
        self:_poll()
    else
        local round = 0
        while #self.jobs > 0 do
            local job = table.remove(self.jobs, 1)
            if job.insert_sec == nil then
                -- Jobs are first inserted to jobs table from external users. So
                -- they may not have insert_sec field.
                job.insert_sec = os.time()
            end
            local should_execute = false
            local should_ignore = false
            if type(job.when) == "function" then
                local status, result = pcall(job.when)
                if status then
                    should_execute = result
                else
                    should_ignore = true
                end
            elseif type(job.when) == "number" then
                if job.when >= 0 then
                    should_execute = ((os.time() - job.insert_sec) >= job.when)
                else
                    should_ignore = true
                end
            elseif type(job.when) == "string" then
                -- TODO(Hzj_jie): Implement "idle" mode
                if job.when == "best-effort" then
                    should_execute = (round > 0)
                elseif job.when == "idle" then
                    should_execute = (round > 1)
                else
                    should_ignore = true
                end
            else
                should_ignore = true
            end

            if should_execute then
                assert(not should_ignore)
                self:_executeJob(job)
                break
            elseif not should_ignore then
                table.insert(self.jobs, job)
            end

            round = round + 1
            if round > 2 then break end
        end
    end

    if PluginShare.stopBackgroundRunner == nil then
        self:_schedule()
    end
end

function BackgroundRunner:_schedule()
    assert(self ~= nil)
    UIManager:scheduleIn(2, function() self:_execute() end)
end

function BackgroundRunner:_insert(job)
    assert(self ~= nil)
    job.insert_sec = os.time()
    table.insert(self.jobs, job)
end

BackgroundRunner:_schedule()

local BackgroundRunnerWidget = WidgetContainer:new{
    name = "backgroundrunner",
    runner = BackgroundRunner,
}

return BackgroundRunnerWidget
