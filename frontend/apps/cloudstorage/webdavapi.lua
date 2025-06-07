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
local SyncCommon = require("apps/cloudstorage/synccommon")

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

-- listFolder now takes an optional options table for backward compatibility.
-- options can be:
-- - boolean (legacy): treated as folder_mode
-- - table: {folder_mode=boolean, sync_mode=boolean}
function WebDavApi:listFolder(address, user, pass, folder_path, options)
    -- Handle backward compatibility
    local folder_mode = false
    local sync_mode = false
    
    if type(options) == "boolean" then
        -- Legacy boolean folder_mode parameter
        folder_mode = options
    elseif type(options) == "table" then
        folder_mode = options.folder_mode or false
        sync_mode = options.sync_mode or false
    end

    local path = folder_path or ""
    local webdav_list = {}
    local webdav_file = {}
    local webdav_url = self:getJoinedPath(address, path)

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
        logger.err("WebDavApi:listFolder: No response:", status or code)
        return nil
    elseif not code or code < 200 or code > 299 then
        -- got a response, but it wasn't a success (e.g. auth failure)
        logger.err("WebDavApi:listFolder: Request failed:", status or code)
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
            
            -- For sync mode, we need just the item name, not the full path
            local item_path = item_name
            if not sync_mode and path and path ~= "" then
                item_path = path .. "/" .. item_name
            end

            -- only available for files, not directories/collections
            local item_filesize = item:match("<[^:]*:getcontentlength[^>]*>(%d+)</[^:]*:getcontentlength>")

            if item:find("<[^:]*:collection[^<]*/>") then
                item_name = item_name .. "/"
                if not is_current_dir then -- Always include folders unless it's current directory
                    local folder_type = "folder"
                    if folder_mode then
                        folder_type = "folder_long_press"
                    end
                    table.insert(webdav_list, {
                        text = item_name,
                        url = item_path,
                        type = folder_type,
                    })
                end
            elseif is_not_collection and (DocumentRegistry:hasProvider(item_name)
                or G_reader_settings:isTrue("show_unsupported")) and not folder_mode then
                table.insert(webdav_file, {
                    text = item_name,
                    url = item_path, -- This is the relative path
                    type = "file",
                    filesize = tonumber(item_filesize) or 0,
                })
            end
        end
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
            url = files.url, -- This is the relative path
            type = files.type,
            filesize = files.filesize or nil,
            mandatory = util.getFriendlySize(files.filesize) or nil
        })
    end
    if folder_mode and not sync_mode then -- Don't add "Long-press" item in sync_mode
        table.insert(webdav_list, 1, {
            text = _("Long-press to choose current folder"),
            url = folder_path,
            type = "folder_long_press",
            bold = true
        })
    end
    return webdav_list
end

function WebDavApi:downloadFile(url, user, pass, local_path)
    -- Ensure HTTPS by default for security
    if not url:match("^https://") and not url:match("^http://localhost") and not url:match("^http://127%.0%.0%.1") then
        logger.err("WebDavApi:downloadFile: Insecure connection not allowed. Use HTTPS.")
        return nil
    end
    
    logger.dbg("WebDavApi:downloadFile url=", url, " local_path=", local_path)
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code, headers, status = socket.skip(1, http.request{
        url = url,
        user = user,
        password = pass,
        sink = ltn12.sink.file(io.open(local_path, "w")),
    })
    socketutil:reset_timeout()
    if code ~= 200 then
        logger.err("WebDavApi:downloadFile: Request failed:", status or code)
    end
    return code
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
