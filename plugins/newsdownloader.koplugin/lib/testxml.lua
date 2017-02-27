#!/usr/bin/lua
---Simple command line test parser - applies handler[s] specified
-- to XML file (or STDIN) and dumps results<br/>
--
-- $Id: testxml.lua,v 1.1.1.1 2001/11/28 06:11:33 paulc Exp $<br/>
--
-- $Log: testxml.lua,v $<br/>
-- Revision 1.1.1.1  2001/11/28 06:11:33  paulc<br/>
-- Initial Import
--

dofile('xml.lua')
dofile('handler.lua')
dofile('pretty.lua')
dofile('xmlrpclib.lua')

-- Defaults
_print = nil
_simpletree = nil
_dom = nil 
_file = nil
_xmlrpc = nil
_debug = nil
_ws = nil
_noentity = nil

_usage = [[
textxml.lua [-print] [-simpletree] [-dom] [-xmlrpc] [-debug] 
            [-ws] [-noentity] [-help] [file]
]]

_help = [[
testxml.lua - Simple command line XML processor

Options:

    -print          : Generate event dump (default)
    -simpletree     : Generate simple tree
    -dom            : Generate DOM-like tree
    -xmlrpc         : Parse XML-RPC nethod call
    -debug          : Print debug info (filename/text)
    -ws             : Do not strip whitespace
    -noentity       : Do not expand entities
    -help           : Print help
    file            : XML File (parse stdin in nil)
]]

index = 1

function setOptions(x)
    if _ws then
        x.options.stripWS = nil
    end
    if _noentity then
        x.options.expandEntities = nil
    end
end

while arg[index] do
    --print (arg[index])
    if (string.sub(arg[index],1,1)=='-') then
        if arg[index] == "-print" then
            _print = 1
        elseif arg[index] == "-simpletree" then
            _simpletree= 1
        elseif arg[index] == "-dom" then
            _dom= 1
        elseif arg[index] == "-xmlrpc" then
            _xmlrpc= 1
        elseif arg[index] == "-debug" then
            _debug = 1
        elseif arg[index] == "-ws" then
            _ws = 1
        elseif arg[index] == "-noentity" then
            _noentity = 1
        elseif arg[index] == "-help" then
            print(_usage)
            exit()
        else 
            print(_usage)
            exit()
        end
    else 
        -- Filename is last argument if present
        if arg[index+1] then
            print(_usage)
            exit()
        else 
            _file = arg[index]
        end
    end
    index = index + 1
end

if _file then
    print("File",_file)
    if (_debug) then
        io.write ( "File: ".._file.."\n" )
    end
    --xml = read(openfile(_file,"r"),"*a")

    local f, e = io.open(_file, "r")
    if f then
      xml = f:read("*a")
    else 
      error(e)
    end

else
    xml = read("*a")
end

if _debug then
    io.write ( "----------- XML\n" )
    io.write (xml.."\n")
end

if _print or not (_print or _dom or _simpletree or _print or _xmlrpc) then
    io.write ( "----------- Print\n" )
    h = printHandler()
    x = xmlParser(h)
    setOptions(x)
    x:parse(xml)
end

if _simpletree then
    io.write ( "----------- SimpleTree\n" )
    h = simpleTreeHandler()
    x = xmlParser(h)
    setOptions(x)
    x:parse(xml)
    pretty('root',h.root)
end

if _dom then
    io.write ( "----------- Dom\n" )
    h = domHandler()
    x = xmlParser(h)
    setOptions(x)
    x:parse(xml)
    pretty('root',h.root)
    write ( "-----------\n" )
end

if _xmlrpc then
    io.write ( "----------- XMLRPC\n" )
    h = simpleTreeHandler()
    h.options = {noreduce={param=1,member=1}}
    x = xmlParser(h)
    x:parse(xml)
    rpc =  xmlrpclib()
    method,params = rpc:parseMethodCall(h.root)
    print("Method:",method)
    print("Params:")
    pretty("xmlrpc",params)
end



