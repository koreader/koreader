local PluginShare = require("pluginshare")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

-- BackgroundRunner is an experimental feature to execute non-critical jobs in
-- background. A job is defined as a table in PluginShare.backgroundJobs table.
-- It contains at least following items:
-- when: integer, string or function
--   integer: the delay in seconds
--   string: "best-effort" - the job will be started when there is no other jobs
--                           to be executed.
--           "idle"        - the job will be started when the device is idle.
--   function: if the return value of the function is true, the job will be
--             executed immediately.
-- repeat: boolean or function or nil
--   boolean: true to repeat the job once it finished.
--   function: if the return value of the function is true, repeat the job once
--             it finished.
--   nil: same as false.
-- executable: string or function
--   string: the command line to be executed. The command or binary will be
--           executed in the lowest priority. Command or binary will be killed
--           if it executes for over 1 hour.
--   function: the action to be executed. The execution cannot be killed, but it
--             will be considered as timeout if it executes for more than 1
--             second.
--   If the executable times out, the job will be blocked, i.e. the repeat field
--   will be ignored.
--
-- If a job does not contain enough information, it will be ignored.
--
-- Once the job is finished, several items will be added to the table:
-- result: integer, the return value of the command. Not available for function
--         executable.
-- timeout: boolean, whether the command times out.
-- badcommand: boolean, whether the command is not found. Not available for
--             function executable.
-- blocked: boolean, whether the job is blocked.
local BackgroundRunner = {
    jobs = {},
    pio = nil,
}

function BackgroundRunner:_insert(job)
    assert(self ~= nil)
    table.insert(self.jobs, job)
end

function BackgroundRunner:_execute(job)
    assert(pio == nil)
    if job == nil then return end
    if job.executable == nil then return end

    if type(job.executable) == "string" then
       pio = io.popen("sh koplugins/backgroundrunner.koplugin/luawrapper.sh " .. job.executable) 
    elseif type(job.executable) == "function" then
    end
end

local BackgroundRunnerWidget = WidgetContainer:new{
    name = "backgroundrunner",
    runner = BackgroundRunner,
}

return BackgroundRunnerWidget
