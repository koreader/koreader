---
--  Overview:
--  =========
--      This module provide a CGI request parser library for Lua
--  
--  Features:
--  =========
--      * Handles both 'application/x-www-form-urlencoded' and 'multipart/form-data' content-types
--      * Handles file uploads
--      * Handles multi-valued fields
--      * Optional hooks for XML handler to handle 'text/xml' content-types (eg xmlrpc etc)
--      * Parses request data into following tables
--          self.env        - CGI Environment
--          self.headers    - Request Headers
--          self.fields     - Form Data
--          self.files      - File Uploads
--          self.xml        - Parsed XML Data
--          self.cookies    - NOT IMPLEMENTED (yet)
--  
--      As Lua by default cant iterate through env (can only 
--      read specific values) it is not possible to pass through
--      non-standard env variables (eg HTTP_xxxx) other than those
--      predefined below (_HTTP_ENV)
--
--  NOTE:
--      I wasnt able to find a complete CGI library for Lua & also 
--      wanted to be able to handle file uploads and xml payloads so 
--      wrote this (LuaCGI only seemed to be available in binary and
--      wasnt available for MacOSX). This was my first attempt at Lua
--      so the code is pretty ugly (particularly the multipart mime
--      handling) and needs to be refactored.
--      
--  Limitations/Todo:
--  =================
--      * Restucture to meet LTN7 & refactor code
--      * Cookie processing
--      * Implement response object for output
--      * Complete Docs(!)
--
--  API/Options/Usage:
--  ==================
--      [To follow - see code]
--
--          c = CGI()
--          c.options.xxxx = ....
--          c.parse()
--          for k,v in pairs(c.fields) do print(k,v) end
--
--      [See cgitest.cgi for example]
--
--  License:
--  ========
--      This code is freely distributable under the terms of the Lua license
--      (<a href="http://www.lua.org/copyright.html">http://www.lua.org/copyright.html</a>)
--
--  History
--  =======
--  $Id: cgi.lua,v 1.1.1.1 2001/11/28 06:11:33 paulc Exp $
--
--  $Log: cgi.lua,v $
--  Revision 1.1.1.1  2001/11/28 06:11:33  paulc
--  Initial Import
--@author Paul Chakravarti (paulc@passtheaardvark.com)<p/>

_CGI_ENV = {  "AUTH_TYPE", 
              "CONTENT_LENGTH",
              "CONTENT_TYPE",
              "GATEWAY_INTERFACE",
              "PATH_INFO",
              "PATH_TRANSLATED",
              "QUERY_STRING",
              "REMOTE_ADDR",
              "REMOTE_HOST",
              "REMOTE_IDENT",
              "REMOTE_USER",
              "REQUEST_METHOD",
              "SCRIPT_NAME",
              "SERVER_NAME",
              "SERVER_PORT",
              "SERVER_PROTOCOL",
              "SERVER_SOFTWARE",
            }

_HTTP_ENV = { 
              "HTTP_ACCEPT",
              "HTTP_ACCEPT_CHARSET",
              "HTTP_ACCEPT_ENCODING",
              "HTTP_ACCEPT_LANGUAGE",
              "HTTP_CACHE_CONTROL",
              "HTTP_COOKIE",
              "HTTP_COOKIE2",
              "HTTP_FROM",
              "HTTP_HOST",
              "HTTP_NEGOTIATE",
              "HTTP_PRAGMA",
              "HTTP_REFERER",
              "HTTP_USER_AGENT",
}


function CGI() 
    return {
        env = {},
        headers = {},
        fields = {},
        files = {},
        cookies = nil,
        xml = nil,
        multipart = { offset = 1, boundary = "" },
        buf = "",
        rfile = _INPUT,
        wfile = _OUTPUT,

        options = { 
            parse_qs = 1,
            max_post = 2000,
            error_handler = function (x) _ALERT("CGI Error:"..x.."\n") end,
            xml_parser = nil,
            xml_parser_options = nil,
            xml_handler = nil,
            xml_handler_options = nil,
        },

        parse = function(self) 
            self:parse_env()
            self.env.content_length = tonumber(self.env.content_length) or 0
            if self.env.request_method == 'GET' or self.options.parse_qs then
                self:parse_get()
            end
            if self.env.request_method == 'POST' then
                if self.env.content_type == 'application/x-www-form-urlencoded' then
                    self:parse_post()
                elseif strfind(self.env.content_type, 'multipart/form-data',1,1) then
                    self:parse_multipart()
                elseif self.env.content_type == 'text/xml' then
                    if self.options.xml_parser and self.options.xml_handler then
                        self:parse_xml()
                    else
                        self.options.error_handler("Invalid Content-Type:"..self.env.content_type)
                    end
                else
                    self.options.error_handler("Invalid Content-Type:"..self.env.content_type)
                end
            else 
            end
        end,

        parse_env = function(self)
            foreach (_CGI_ENV, function (k,v) self.env[strlower(v)] = getenv(v) end)
            foreach (_HTTP_ENV, function (k,v) self.headers[strlower(gsub(v,'HTTP_',''))] = getenv(v) end)
        end,

        parse_qs = function(self,qs)
            local str = qs or ""
            while str ~= "" do
                local i,j,k,v = strfind(str,"(.-)=([^&]*)")
                if i == nil then break end
                self:insert_formval(self:decode_url(k),self:decode_url(v))
                str = strsub(str,j+2)
            end
        end,

        parse_get = function(self)
            self:parse_qs(self.env.query_string)
        end,

        parse_post = function(self)
            local len = self.env.content_length or 0
            if self.options.max_post and len > self.options.max_post then
                self.options.error_handler("Max Post Length Exceeded")
            else 
                local qs = read(self.rfile,len)
                self:parse_qs(qs)
            end
        end,

        parse_xml = function(self)
            local handler = self.options.xml_handler()
            if self.options.xml_handler_options then
                handler.options = self.options.xml_handler_options
            end
            local parser = self.options.xml_parser(handler)
            if self.options.xml_parser_options then
                parser.options = self.options.xml_parser_options
            end
            local len = self.env.content_length or 0
            if self.options.max_post and len > self.options.max_post then
                self.options.error_handler("Max Post Length Exceeded")
            else 
                local xml = read(self.rfile,len)
                parser:parse(xml)
                self.xml = handler.root
            end
        end,

        parse_multipart = function(self)
            local _,_,bdy = strfind(self.env.content_type,[[[Bb]oundary="?([^";,]+)"?]])
            self.multipart.boundary = "--"..(bdy or "")
            local len = self.env.content_length or 0
            if self.options.max_post and len > self.options.max_post then
                self.options.error_handler("Max Post Length Exceeded")
            else 
                self.buf = read(self.rfile,len)
                while self:read_part() do end
                self.buf = nil
            end
        end,

        read_part = function(self)
            local start,ends,data,name,filename,key,val,_
            -- Get multipart header
            starts,ends = strfind(self.buf,self.multipart.boundary.."\r\n",self.multipart.offset,1) 
            if starts ~= self.multipart.offset then
                self.options.error_handler("Invalid Multipart Data: Boundary Not Found")
                return nil
            else
                self.multipart.offset = ends + 1
            end
            -- Get header fields
            while 1 do
                starts,ends,data = strfind(self.buf,"(.-)\r\n",self.multipart.offset)
                if starts ~= self.multipart.offset then
                    self.options.error_handler("Invalid Multipart Data: Headers Not Found")
                    return nil
                elseif data == "" then
                    self.multipart.offset = ends + 1
                    break
                else
                    if strlower(strsub(data,1,19)) == 'content-disposition' then
                        _,_,name = strfind(data,[[[Nn]ame="?([^";,]+)"?]])
                        _,_,filename = strfind(data,[[[Ff]ilename="?([^";,]+)"?]])
                        if filename then 
                            self.files[name] = {}
                            self.files[name].filename = filename
                        end
                    elseif filename then
                        _,_,key,val = strfind(data,"(.-):%s+(.+)")
                        self.files[name][key] = val
                    end
                    self.multipart.offset = ends + 1
                end
            end
            -- Get data
            starts,ends = strfind(self.buf,"\r\n"..self.multipart.boundary,self.multipart.offset,1)
            if starts then
                data = strsub(self.buf,self.multipart.offset,starts - 1)
                if filename then
                    self.files[name].data = data
                else
                    self:insert_formval(name,data)
                end
                if strsub(self.buf,ends+1,ends+2) == "--" then
                    return nil
                else
                    self.multipart.offset = starts + 2
                end
            else
                self.options.error_handler("Invalid Multipart Data: End Separator Not Found")
                return nil
            end
            return 1
        end,

        insert_formval = function(self,key,val)
            local cval = self.fields[key]
            if type(cval) == 'nil' then
                self.fields[key] = val
            elseif type(cval) == 'string' then
                self.fields[key] = {cval,val}
            elseif type(cval) == 'table' then
                cval[getn(cval)+1] = val
                self.fields[key] = cval
            else
                self.options.error_handler("Field Type Error")
            end
        end,

        hexchar = function(x)
            return string.char(tonumber(x,16))
        end,

        decode_url = function(self,s)
            s = string.gsub(s,"+"," ")
            s = string.gsub(s,"%%(%x%x)",self.hexchar)
            return s
        end,
    }
end
