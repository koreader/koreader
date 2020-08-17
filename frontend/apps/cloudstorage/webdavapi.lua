local DocumentRegistry = require("document/documentregistry")
local FFIUtil = require("ffi/util")
local http = require('socket.http')
local https = require('ssl.https')
local ltn12 = require('ltn12')
local mime = require('mime')
local socket = require('socket')
local url = require('socket.url')
local util = require("util")
local _ = require("gettext")

local WebDavApi = {
}

function WebDavApi:isCurrentDirectory( current_item, address, path )
    local is_home, is_parent
    local home_path
    -- find first occurence of / after http(s)://
    local start = string.find( address, "/", 9 )
    if not start then
        home_path = "/"
    else
        home_path = string.sub( address, start )
    end
    local item
    if string.sub( current_item, -1 ) == "/" then
        item = string.sub( current_item, 1, -2 )
    else
        item = current_item
    end

    if item == home_path then
        is_home = true
    else
        local temp_path = string.sub( item, string.len(home_path) + 1 )
        if temp_path == path then
            is_parent = true
        end
    end
    return is_home or is_parent
end

-- version of urlEncode that doesn't encode the /
function WebDavApi:urlEncode(url_data)
    local char_to_hex = function(c)
        return string.format("%%%02X", string.byte(c))
    end
    if url_data == nil then
        return
    end
    url_data = url_data:gsub("([^%w%/%-%.%_%~%!%*%'%(%)])", char_to_hex)
    return url_data
end

function WebDavApi:listFolder(address, user, pass, folder_path)
    local path = self:urlEncode( folder_path )
    local webdav_list = {}
    local webdav_file = {}

    local has_trailing_slash = false
    local has_leading_slash = false
    if string.sub( address, -1 ) == "/" then has_trailing_slash = true end
    if path == nil or path == "/" then
        path = ""
    elseif string.sub( path, 1, 2 ) == "/" then
        if has_trailing_slash then
            -- too many slashes, remove one
            path = string.sub( path, 1 )
        end
        has_leading_slash = true
    end
    if not has_trailing_slash and not has_leading_slash then
        address = address .. "/"
    end
    local webdav_url = address .. path
    if not has_trailing_slash then
        webdav_url = webdav_url .. "/"
    end

    local request, sink = {}, {}
    local parsed = url.parse(webdav_url)
    local data = [[<?xml version="1.0"?><a:propfind xmlns:a="DAV:"><a:prop><a:resourcetype/></a:prop></a:propfind>]]
    local auth = string.format("%s:%s", user, pass)
    local headers = { ["Authorization"] = "Basic " .. mime.b64( auth ),
        ["Content-Type"] = "application/xml",
        ["Depth"] = "1",
        ["Content-Length"] = #data}
    request["url"] = webdav_url
    request["method"] = "PROPFIND"
    request["headers"] = headers
    request["source"] = ltn12.source.string(data)
    request["sink"] = ltn12.sink.table(sink)
    http.TIMEOUT = 5
    https.TIMEOUT = 5
    local httpRequest = parsed.scheme == "http" and http.request or https.request
    local headers_request = socket.skip(1, httpRequest(request))
    if headers_request == nil then
        return nil
    end

    local res_data = table.concat(sink)

    if res_data ~= "" then
        -- iterate through the <d:response> tags, each containing an entry
        for item in res_data:gmatch("<[^:]*:response[^>]*>(.-)</[^:]*:response>") do
            --logger.dbg("WebDav catalog item=", item)
            -- <d:href> is the path and filename of the entry.
            local item_fullpath = item:match("<[^:]*:href[^>]*>(.*)</[^:]*:href>")
            if string.sub( item_fullpath, -1 ) == "/" then
                item_fullpath = string.sub( item_fullpath, 1, -2 )
            end
            local is_current_dir = self:isCurrentDirectory( item_fullpath, address, path )
            local item_name = util.urlDecode( FFIUtil.basename( item_fullpath ) )
            local item_path = path .. "/" .. item_name
            if item:find("<[^:]*:collection/>") then
                item_name = item_name .. "/"
                if not is_current_dir then
                    table.insert(webdav_list, {
                        text = item_name,
                        url = util.urlDecode( item_path ),
                        type = "folder",
                    })
                end
            elseif item:find("<[^:]*:resourcetype/>") and (DocumentRegistry:hasProvider(item_name)
                or G_reader_settings:isTrue("show_unsupported")) then
                table.insert(webdav_file, {
                    text = item_name,
                    url = util.urlDecode( item_path ),
                    type = "file",
                })
            end
        end
    else
        return nil
    end

    --sort
    table.sort(webdav_list, function(v1,v2)
        return v1.text < v2.text
    end)
    table.sort(webdav_file, function(v1,v2)
        return v1.text < v2.text
    end)
    for _, files in ipairs(webdav_file) do
        table.insert(webdav_list, {
            text = files.text,
            url = files.url,
            type = files.type,
        })
    end
    return webdav_list
end

function WebDavApi:downloadFile(file_url, user, pass, local_path)
    local parsed = url.parse(file_url)
    local auth = string.format("%s:%s", user, pass)
    local headers = { ["Authorization"] = "Basic " .. mime.b64( auth ) }
    http.TIMEOUT = 5
    https.TIMEOUT = 5
    local httpRequest = parsed.scheme == "http" and http.request or https.request
    local _, code_return, _ = httpRequest{
        url = file_url,
        method = "GET",
        headers = headers,
        sink = ltn12.sink.file(io.open(local_path, "w"))
    }
    return code_return
end

return WebDavApi
