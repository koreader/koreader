local DocumentRegistry = require("document/documentregistry")
local ffiUtil = require("ffi/util")
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

-- Trim leading & trailing slashes from string `s` (based on util.trim)
function WebDavApi.trim_slashes(s)
    local from = s:match"^/*()"
    return from > #s and "" or s:match(".*[^/]", from)
end

-- Trim trailing slashes from string `s` (based on util.rtrim)
function WebDavApi.rtrim_slashes(s)
    local n = #s
    while n > 0 and s:find("^/", n) do
        n = n - 1
    end
    return s:sub(1, n)
end

-- Variant of util.urlEncode that doesn't encode the /
function WebDavApi.urlEncode(url_data)
    local char_to_hex = function(c)
        return string.format("%%%02X", string.byte(c))
    end
    if url_data == nil then
        return
    end
    url_data = url_data:gsub("([^%w%/%-%.%_%~%!%*%'%(%)])", char_to_hex)
    return url_data
end

-- Append path to address with a slash separator, trimming any unwanted slashes in the process.
function WebDavApi:getJoinedPath(address, path)
    local path_encoded = self.urlEncode(path) or ""
    -- Strip leading & trailing slashes from `path`
    local sane_path = self.trim_slashes(path_encoded)
    -- Strip trailing slashes from `address` for now
    local sane_address = self.rtrim_slashes(address)
    -- Join our final URL
    return sane_address .. "/" .. sane_path
end

function WebDavApi:listFolder(address, user, pass, folder_path, folder_mode)
    local path = folder_path or ""
    local webdav_list = {}
    local webdav_file = {}

    -- Strip leading & trailing slashes from `path`
    path = self.trim_slashes(path)
    -- Strip trailing slashes from `address` for now
    address = self.rtrim_slashes(address)
    -- Join our final URL, which *must* have a trailing / (it's a URL)
    -- This is where we deviate from getJoinedPath ;).
    local webdav_url = address .. "/" .. self.urlEncode(path)
    if webdav_url:sub(-1) ~= "/" then
        webdav_url = webdav_url .. "/"
    end

    local sink = {}
    local data = [[<?xml version="1.0"?><a:propfind xmlns:a="DAV:"><a:prop><a:resourcetype/><a:getcontentlength/></a:prop></a:propfind>]]
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
            local item_name = ffiUtil.basename(util.htmlEntitiesToUtf8(util.urlDecode(item_fullpath)))
            local is_current_dir = self.trim_slashes(item_fullpath) == path
            local is_not_collection = item:find("<[^:]*:resourcetype%s*/>") or
                                      item:find("<[^:]*:resourcetype></[^:]*:resourcetype>")
            local item_path = path .. "/" .. item_name

            -- only available for files, not directories/collections
            local item_filesize = item:match("<[^:]*:getcontentlength[^>]*>(%d+)</[^:]*:getcontentlength>")

            if item:find("<[^:]*:collection[^<]*/>") then
                item_name = item_name .. "/"
                if not is_current_dir then
                    table.insert(webdav_list, {
                        text = item_name,
                        url = item_path,
                        type = "folder",
                    })
                end
            elseif is_not_collection and (DocumentRegistry:hasProvider(item_name)
                or G_reader_settings:isTrue("show_unsupported")) then
                table.insert(webdav_file, {
                    text = item_name,
                    url = item_path,
                    type = "file",
                    filesize = tonumber(item_filesize)
                })
            end
        end
    else
        return nil
    end

    --sort
    table.sort(webdav_list, function(v1,v2)
        return ffiUtil.strcoll(v1.text, v2.text)
    end)
    table.sort(webdav_file, function(v1,v2)
        return ffiUtil.strcoll(v1.text, v2.text)
    end)
    for _, files in ipairs(webdav_file) do
        table.insert(webdav_list, {
            text = files.text,
            url = files.url,
            type = files.type,
            filesize = files.filesize or nil,
            mandatory = util.getFriendlySize(files.filesize) or nil
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

function WebDavApi:downloadFile(file_url, user, pass, local_path, progress_callback)
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    logger.dbg("WebDavApi: downloading file: ", file_url)

    local handle = ltn12.sink.file(io.open(local_path, "w"))
    handle = socketutil.chainSinkWithProgressCallback(handle, progress_callback)

    local code, headers, status = socket.skip(1, http.request {
        url      = file_url,
        method   = "GET",
        sink     = handle,
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
    if type(code) ~= "number" or code < 200 or code > 299 then
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
