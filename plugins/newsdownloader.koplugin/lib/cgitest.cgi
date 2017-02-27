#!/usr/bin/lua

dofile("cgi.lua")
dofile("xml.lua")
dofile("handler.lua")
dofile("pretty.lua")

c = CGI()
c.options.xml_parser = xmlParser
c.options.xml_handler = simpleTreeHandler
c:parse()

print [[Content-Type: text/plain

LUA CGI
=======

Env:
---
]]

for k,v in pairs(c.env) do
    io.write(string.format("%-20s : %s\n",k,v))
end

print [[
Headers:
--------
]]

for k,v in pairs(c.headers) do
    io.write(string.format("%-20s : %s\n",k,v))
end

print [[
Fields:
-------
]]

for k,v in pairs(c.fields) do
    io.write(string.format("%-20s : %s\n",k,v))
end

print [[
Files:
-------
]]

for k,v in pairs(c.files) do
    io.write(string.format("%-20s : %s\n","Name",k))
    for k,v2 in pairs(v) do
        if k ~= 'data' then
            io.write(string.format("%-20s : %s\n",k,v2))
        end
    end
end

print [[
XML:
----
]]

pretty("XML", c.xml)
