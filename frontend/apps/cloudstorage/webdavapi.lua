local DocumentRegistry = require("document/documentregistry")
local FFIUtil = require("ffi/util")
local http = require("socket.http")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local util = require("util")
local _ = require("gettext")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")

local WebDavApi = {
}

function WebDavApi:getJoinedPath( address, path )
    local path_encoded = self:urlEncode( path ) or ""
    local address_strip = address:sub(-1) == "/" and address:sub(1, -2) or address
    local path_strip = path_encoded:sub(1, 1) == "/" and path_encoded:sub(2) or path_encoded
    return address_strip .. "/" .. path_strip
end

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
        if string.sub( path, -1 ) == "/" then path = string.sub( path, 1, -2 ) end
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

function WebDavApi:listFolder(address, user, pass, folder_path, folder_mode)
    local path = self:urlEncode( folder_path )
    local webdav_list = {}
    local webdav_file = {}

    local has_trailing_slash = false
    local has_leading_slash = false
    if string.sub( address, -1 ) == "/" then has_trailing_slash = true end
    if path == nil or path == "/" then
        path = ""
    elseif string.sub( path, 1, 1 ) == "/" then
        if has_trailing_slash then
            -- too many slashes, remove one
            path = string.sub( path, 2 )
        end
        has_leading_slash = true
    end
    if not has_trailing_slash and not has_leading_slash then
        address = address .. "/"
    end
    local webdav_url = address .. path
    if string.sub(webdav_url, -1) ~= "/" then
        webdav_url = webdav_url .. "/"
    end

    local sink = {}
    local data = [[<?xml version="1.0"?><a:propfind xmlns:a="DAV:"><a:prop><a:resourcetype/></a:prop></a:propfind>]]
    socketutil:set_timeout()
    local request = {
        url      = webdav_url,
        method   = "PROPFIND",
        headers  = {
            ["Content-Type"]   = "application/xml",
            ["Depth"]          = "1",
            ["Content-Length"] = #data,
        },
        user     = user,
        password = pass,
        source   = ltn12.source.string(data),
        sink     = ltn12.sink.table(sink),
    }
    local code, headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    if headers == nil then
        logger.dbg("WebDavApi:listFolder: No response:", status or code)
        return nil
    elseif not code or code < 200 or code > 299 then
        -- got a response, but it wasn't a success (e.g. auth failure)
        logger.dbg("WebDavApi:listFolder: Request failed:", status or code)
        logger.dbg("WebDavApi:listFolder: Response headers:", headers)
        logger.dbg("WebDavApi:listFolder: Response body:", table.concat(sink))
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
            local is_current_dir = self:isCurrentDirectory( util.urlDecode(item_fullpath), address, folder_path )

            local item_name = util.urlDecode( FFIUtil.basename( item_fullpath ) )
            item_name = util.htmlEntitiesToUtf8(item_name)

            local is_not_collection = item:find("<[^:]*:resourcetype/>") or
                item:find("<[^:]*:resourcetype></[^:]*:resourcetype>")

            local item_path = (path == "" and has_trailing_slash) and item_name or path .. "/" .. item_name
            if item:find("<[^:]*:collection[^<]*/>") then
                item_name = item_name .. "/"
                if not is_current_dir then
                    table.insert(webdav_list, {
                        text = item_name,
                        url = util.urlDecode( item_path ),
                        type = "folder",
                    })
                end
            elseif is_not_collection and (DocumentRegistry:hasProvider(item_name)
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
    if folder_mode then
        table.insert(webdav_list, 1, {
            text = _("Long-press to choose current folder"),
            url = folder_path,
            type = "folder_long_press",
            bold = true
        })
    end
    return webdav_list
end

function WebDavApi:downloadFile(file_url, user, pass, local_path)
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    logger.dbg("WebDavApi: downloading file: ", file_url)
    local code, headers, status = socket.skip(1, http.request{
        url      = file_url,
        method   = "GET",
        sink     = ltn12.sink.file(io.open(local_path, "w")),
        user     = user,
        password = pass,
    })
    socketutil:reset_timeout()
    if code ~= 200 then
        logger.warn("WebDavApi: Download failure:", status or code or "network unreachable")
        logger.dbg("WebDavApi: Response headers:", headers)
    end
    return code, (headers or {}).etag
end

function WebDavApi:uploadFile(file_url, user, pass, local_path, etag)
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code, _, status = socket.skip(1, http.request{
        url      = file_url,
        method   = "PUT",
        source   = ltn12.source.file(io.open(local_path, "r")),
        user     = user,
        password = pass,
        headers = {
            ["Content-Length"] = lfs.attributes(local_path, "size"),
            ["If-Match"] = etag,
        }
    })
    socketutil:reset_timeout()
    if code < 200 or code > 299 then
        logger.warn("WebDavApi: upload failure:", status or code or "network unreachable")
    end
    return code
end

function WebDavApi:createFolder(folder_url, user, pass, folder_name)
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code, _, status = socket.skip(1, http.request{
        url      = folder_url,
        method   = "MKCOL",
        user     = user,
        password = pass,
    })
    socketutil:reset_timeout()
    if code ~= 201 then
        logger.warn("WebDavApi: create folder failure:", status or code or "network unreachable")
    end
    return code
end


return WebDavApi
