-- lulip: LuaJIT line level profiler
--
-- Copyright (c) 2013 John Graham-Cumming
--
-- License: http://opensource.org/licenses/MIT 

local io_lines = io.lines
local io_open = io.open
local pairs = pairs
local print = print
local debug = debug
local tonumber = tonumber
local setmetatable = setmetatable
local table_sort = table.sort
local table_insert = table.insert
local string_find = string.find
local string_sub = string.sub
local string_gsub = string.gsub
local string_format = string.format
local ffi = require("ffi")

ffi.cdef[[
  typedef long time_t;

  typedef struct timeval {
    time_t tv_sec;
    time_t tv_usec;
  } timeval;
 
  int gettimeofday(struct timeval* t, void* tzp);
]]

module(...)

local gettimeofday_struct = ffi.new("timeval")
local function gettimeofday()
   ffi.C.gettimeofday(gettimeofday_struct, nil)
   return tonumber(gettimeofday_struct.tv_sec) * 1000000 + tonumber(gettimeofday_struct.tv_usec)
end

local mt = { __index = _M }

-- new: create new profiler object
function new(self)
   return setmetatable({
 
      -- Time when start() and stop() were called in microseconds

      start_time = 0,
      stop_time = 0,

      -- Per line timing information

      lines = {},

      -- The current line being processed and when it was startd

      current_line = nil,
      current_start = 0,

      -- List of files to ignore. Set patterns using dont()

      ignore = {},

      -- List of short file names used as a cache

      short = {},

      -- Maximum number of rows of output data, set using maxrows()

      rows = 20,
   }, mt)
end

-- event: called when a line is executed
function event(self, event, line)
   local now = gettimeofday()

   local f = string_sub(debug.getinfo(3).source,2)
   for i=1,#self.ignore do
      if string_find(f, self.ignore[i], 1, true) then
         return
      end
   end

   local short = self.short[f]
   if not short then
      local start = string_find(f, "[^/]+$")
      self.short[f] = string_sub(f, start)
      short = self.short[f]
   end

   if self.current_line ~= nil then
      self.lines[self.current_line][1] =
         self.lines[self.current_line][1] + 1
      self.lines[self.current_line][2] =
         self.lines[self.current_line][2] + (now - self.current_start)
   end

   self.current_line = short .. ':' .. line

   if self.lines[self.current_line] == nil then
      self.lines[self.current_line] = {0, 0.0, f}
   end
   
   self.current_start = gettimeofday()
end

-- dont: tell the profiler to ignore files that match these patterns
function dont(self, file)
   table_insert(self.ignore, file)
end

-- maxrows: set the maximum number of rows of output
function maxrows(self, max)
   self.rows = max
end

-- start: begin profiling
function start(self)
   self:dont('lulip.lua')
   self.start_time = gettimeofday()
   self.current_line = nil
   self.current_start = 0
   debug.sethook(function(e,l) self:event(e, l) end, "l")
end

-- stop: end profiling
function stop(self)
   self.stop_time = gettimeofday()
   debug.sethook()
end

-- readfile: turn a file into an array for line-level access
local function readfile(file)
   local lines = {}
   local ln = 1
   for line in io_lines(file) do
      lines[ln] = string_gsub(line, "^%s*(.-)%s*$", "%1")
      ln = ln + 1
   end
   return lines
end

-- dump: dump profile information to the named file
function dump(self, file)
   local t = {}
   for l,d in pairs(self.lines) do
      table_insert(t, {line=l, data=d})
   end
   table_sort(t, function(a,b) return a["data"][2] > b["data"][2] end)

   local files = {}

   local f = io_open(file, "w")
   if not f then
      print("Failed to open output file " .. file)
      return
   end
   f:write([[
<html>
<head>
<script src="https://google-code-prettify.googlecode.com/svn/loader/run_prettify.js">
</script>
<style>.code { padding-left: 20px; }</style>
</head>
<body>
<table width="100%">
<thead><tr><th align="left">file:line</th><th align="right">count</th>
<th align="right">elapsed (ms)</th><th align="left" class="code">line</th>
</tr></thead>
<tbody>
]])

   for j=1,self.rows do
      if not t[j] then break end
      local l = t[j]["line"]
      local d = t[j]["data"]
      if not files[d[3]] then 
         files[d[3]] = readfile(d[3])
      end
      local ln = tonumber(string_sub(l, string_find(l, ":", 1, true)+1))
      f:write(string_format([[
<tr><td>%s</td><td align="right">%i</td><td align="right">%.3f</td>
<td class="code"><code class="prettyprint">%s</code></td></tr>]],
l, d[1], d[2]/1000, files[d[3]][ln]))
   end
   f:write('</tbody></table></body></html')
   f:close()
end
