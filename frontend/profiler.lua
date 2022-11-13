--[[
@title lua-profiler
@version 1.1
@description Code profiling for Lua based code;
The output is a report file (text) and optionally to a console or other logger.

The initial reason for this project was to reduce  misinterpretations of code profiling
caused by the lengthy measurement time of the 'ProFi' profiler v1.3;
and then to remove the self-profiler functions from the output report.

The profiler code has been substantially rewritten to remove dependence to the 'OO'
class definitions, and repetitions in code;
thus this profiler has a smaller code footprint and reduced execution time up to ~900% faster.

The second purpose was to allow slight customisation of the output report,
which I have parametrised the output report and rewritten.

Caveats: I didn't include an 'inspection' function that ProFi had, also the RAM
output is gone. Please configure the profiler output in top of the code, particularly the
location of the profiler source file (if not in the 'main' root source directory).

@authors Charles Mallah
@copyright (c) 2018-2020 Charles Mallah
@license MIT license

@sample Output will be generated like this, all output here is ordered by time (seconds):
`> TOTAL TIME   = 0.030000 s
`--------------------------------------------------------------------------------------
`| FILE                : FUNCTION                    : LINE   : TIME   : %     : #    |
`--------------------------------------------------------------------------------------
`| map                 : new                         :   301  : 0.1330 : 52.2  :    2 |
`| map                 : unpackTileLayer             :   197  : 0.0970 : 38.0  :   36 |
`| engine              : loadAtlas                   :   512  : 0.0780 : 30.6  :    1 |
`| map                 : init                        :   292  : 0.0780 : 30.6  :    1 |
`| map                 : setTile                     :    38  : 0.0500 : 19.6  : 20963|
`| engine              : new                         :   157  : 0.0220 : 8.6   :    1 |
`| map                 : unpackObjectLayer           :   281  : 0.0190 : 7.5   :    2 |
`--------------------------------------------------------------------------------------
`| ui                  : sizeCharLimit               :   328  : ~      : ~     :    2 |
`| modules/profiler    : stop                        :   192  : ~      : ~     :    1 |
`| ui                  : sizeWidthToScreenWidthHalf  :   301  : ~      : ~     :    4 |
`| map                 : setRectGridTo               :   255  : ~      : ~     :    7 |
`| ui                  : sizeWidthToScreenWidth      :   295  : ~      : ~     :   11 |
`| character           : warp                        :    32  : ~      : ~     :   15 |
`| panels              : Anon                        :     0  : ~      : ~     :    1 |
`--------------------------------------------------------------------------------------

The partition splits the notable code that is running the slowest, all other code is running
too fast to determine anything specific, instead of displaying "0.0000" the script will tidy
this up as "~". Table headers % and # refer to percentage total time, and function call count.

@example Print a profile report of a code block
`local profiler = require("profiler")
`profiler.start()
`-- Code block and/or called functions to profile --
`profiler.stop()
`profiler.report("profiler.log")

@example Profile a code block and allow mirror print to a custom print function
`local profiler = require("profiler")
`function exampleConsolePrint()
`  -- Custom function in your code-base to print to file or console --
`end
`profiler.attachPrintFunction(exampleConsolePrint, true)
`profiler.start()
`-- Code block and/or called functions to profile --
`profiler.stop()
`profiler.report("profiler.log") -- exampleConsolePrint will now be called from this

@example Override a configuration parameter programmatically; insert your override values into a
new table using the matched key names:

`local overrides = {
`                    fW = 100, -- Change the file column to 100 characters (from 20)
`                    fnW = 120, -- Change the function column to 120 characters (from 28)
`                  }
`profiler.configuration(overrides)
]]

--[[ Configuration ]]--

local config = {
  outputFile = "profiler.lua", -- Name of this profiler (to remove itself from reports)
  emptyToThis = "~", -- Rows with no time are set to this value
  fW = 20, -- Width of the file column
  fnW = 28, -- Width of the function name column
  lW = 7, -- Width of the line column
  tW = 7, -- Width of the time taken column
  rW = 6, -- Width of the relative percentage column
  cW = 5, -- Width of the call count column
  reportSaved = "> Report saved to: ", -- Text for the file output confirmation
}

--[[ Locals ]]--

local module = {}
local getTime = os.clock
local string, debug, table = string, debug, table
local reportCache = {}
local allReports = {}
local reportCount = 0
local startTime = 0
local stopTime = 0
local printFun = nil
local verbosePrint = false

local outputHeader, formatHeader, outputTitle, formatOutput, formatTotalTime
local formatFunLine, formatFunTime, formatFunRelative, formatFunCount, divider, nilTime

local function deepCopy(input)
  if type(input) == "table" then
    local output = {}
    for i, o in next, input, nil do
      output[deepCopy(i)] = deepCopy(o)
    end
    return output
  else
    return input
  end
end

local function charRepetition(n, character)
  local s = ""
  character = character or " "
  for _ = 1, n do
    s = s..character
  end
  return s
end

local function singleSearchReturn(inputString, search)
  for _ in string.gmatch(inputString, search) do -- luacheck: ignore
    return true
  end
  return false
end

local function rebuildColumnPatterns()
  local c = config
  local str = "s: %-"
  outputHeader = "| %-"..c.fW..str..c.fnW..str..c.lW..str..c.tW..str..c.rW..str..c.cW.."s|\n"
  formatHeader = string.format(outputHeader, "FILE", "FUNCTION", "LINE", "TIME", "%", "#")
  outputTitle = "%-"..c.fW.."."..c.fW..str..c.fnW.."."..c.fnW..str..c.lW.."s"
  formatOutput = "| %s: %-"..c.tW..str..c.rW..str..c.cW.."s|\n"
  formatTotalTime = "Total time: %f s\n"
  formatFunLine = "%"..(c.lW - 2).."i"
  formatFunTime = "%04.4f"
  formatFunRelative = "%03.1f"
  formatFunCount = "%"..(c.cW - 1).."i"
  divider = charRepetition(#formatHeader - 1, "-").."\n"
  -- nilTime = "0."..charRepetition(c.tW - 3, "0")
  nilTime = "0.0000"
end

local function functionReport(information)
  local src = information.short_src
  if not src then
    src = "<C>"
  elseif string.sub(src, #src - 3, #src) == ".lua" then
    src = string.sub(src, 1, #src - 4)
  end
  local name = information.name
  if not name then
    name = "Anon"
  elseif string.sub(name, #name - 1, #name) == "_l" then
    name = string.sub(name, 1, #name - 2)
  end
  local title = string.format(outputTitle, src, name,
  string.format(formatFunLine, information.linedefined or 0))
  local report = reportCache[title]
  if not report then
    report = {
      title = string.format(outputTitle, src, name,
      string.format(formatFunLine, information.linedefined or 0)),
      count = 0, timer = 0,
    }
    reportCache[title] = report
    reportCount = reportCount + 1
    allReports[reportCount] = report
  end
  return report
end

local onDebugHook = function(hookType)
  local information = debug.getinfo(2, "nS")
  if hookType == "call" then
    local funcReport = functionReport(information)
    funcReport.callTime = getTime()
    funcReport.count = funcReport.count + 1
  elseif hookType == "return" then
    local funcReport = functionReport(information)
    if funcReport.callTime and funcReport.count > 0 then
      funcReport.timer = funcReport.timer + (getTime() - funcReport.callTime)
    end
  end
end

--[[ Functions ]]--

--[[Attach a print function to the profiler, to receive a single string parameter
@param fn (function) <required>
@param verbose (boolean) <default: false>
]]
function module.attachPrintFunction(fn, verbose)
  printFun = fn
  verbosePrint = verbose or false
end

--[[Start the profiling
]]
function module.start()
  if not outputHeader then
    rebuildColumnPatterns()
  end
  reportCache = {}
  allReports = {}
  reportCount = 0
  startTime = getTime()
  stopTime = nil
  debug.sethook(onDebugHook, "cr", 0)
end

--[[Stop profiling
]]
function module.stop()
  stopTime = getTime()
  debug.sethook()
end

--[[Writes the profile report to file (will stop profiling if not stopped already)
@param filename (string) <default: "profiler.log"> [File will be created and overwritten]
]]
function module.report(filename)
  if not stopTime then
    module.stop()
  end
  filename = filename or "profiler.log"
  table.sort(allReports, function(a, b) return a.timer > b.timer end)
  local fileWriter = io.open(filename, "w+")
  local divide = false
  local totalTime = stopTime - startTime
  local totalTimeOutput = "> "..string.format(formatTotalTime, totalTime)
  fileWriter:write(totalTimeOutput)
  if printFun ~= nil then
    printFun(totalTimeOutput)
  end
  fileWriter:write(divider)
  fileWriter:write(formatHeader)
  fileWriter:write(divider)
  for i = 1, reportCount do
    local funcReport = allReports[i]
    if funcReport.count > 0 and funcReport.timer <= totalTime then
      local printThis = true
      if config.outputFile ~= "" then
        if singleSearchReturn(funcReport.title, config.outputFile) then
          printThis = false
        end
      end
      if printThis then -- Remove lines that are not needed
        if singleSearchReturn(funcReport.title, "[[C]]") then
          printThis = false
        end
      end
      if printThis then
        local count = string.format(formatFunCount, funcReport.count)
        local timer = string.format(formatFunTime, funcReport.timer)
        local relTime = string.format(formatFunRelative, (funcReport.timer / totalTime) * 100)
        if not divide and timer == nilTime then
          fileWriter:write(divider)
          divide = true
        end
        if timer == nilTime then
          timer = config.emptyToThis
          relTime = config.emptyToThis
        end
        -- Build final line
        local output = string.format(formatOutput, funcReport.title, timer, relTime, count)
        fileWriter:write(output)
        -- This is a verbose print to the attached print function
        if printFun ~= nil and verbosePrint then
          printFun(output)
        end
      end
    end
  end
  fileWriter:write(divider)
  fileWriter:close()
  if printFun ~= nil then
    printFun(config.reportSaved.."'"..filename.."'")
  end
end

--[[Modify the configuration of this module programmatically;
Provide a table with keys that share the same name as the configuration parameters:
@param overrides (table) <required> [Each key is from a valid name, the value is the override]
@unpack config
]]
function module.configuration(overrides)
  local safe = deepCopy(overrides)
  for k, v in pairs(safe) do
    if config[k] == nil then
      print("error: override field '"..k.."' not found (configuration)")
    else
      config[k] = v
    end
  end
  rebuildColumnPatterns()
end

--[[ End ]]--
return module
