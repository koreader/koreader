#!/usr/bin/lua

--- Simple CGI based XML-RPC server

dofile("cgi.lua")
dofile("xml.lua")
dofile("handler.lua")
dofile("xmlrpclib.lua")
dofile("pretty.lua")

c = CGI()
c.options.xml_parser = xmlParser
c.options.xml_handler = simpleTreeHandler
c.options.xml_handler_options = {noreduce={param=1,member=1}}
c:parse()

handler = {
    hello = function() return "Hello There" end,
    array = function() return {{1,2,3}} end,
    reverse = function(x,y) return {{y,x}} end,
}


if c.xml then
    x = xmlrpclib()
    method,params = x:parseMethodCall(c.xml)
    func = handler[method]
    if func then
        res = call(func,params,'x')
        xmlres = x:methodResponse(res)
        write("Content-Type: text/xml\n")
        write("Content-Length: "..strlen(xmlres).."\n\n")
        write(xmlres)
    end
end

