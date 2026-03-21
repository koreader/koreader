local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local datetime = require("datetime")
local ffiUtil = require("ffi/util")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local util = require("util")
local _ = require("gettext")

local WebDav = {
    name = _("WebDAV"),
    type = "webdav",
    base = nil, -- CloudStorage self, will be filled in Cloud:onShowCloudStoragePlus()
}

local WebDavApi = {}

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

-- Append path to address with a slash separator, trimming any unwanted slashes in the process.
function WebDavApi.getJoinedPath(address, path)
    local path_encoded = util.urlEncode(path, "/") or ""
    -- Strip leading & trailing slashes from `path`
    local sane_path = WebDavApi.trim_slashes(path_encoded)
    -- Strip trailing slashes from `address` for now
    local sane_address = WebDavApi.rtrim_slashes(address)
    -- Join our final URL
    return sane_address .. "/" .. sane_path
end

function WebDavApi.listFolder(address, user, pass, folder_path, include_folders)
    local path = folder_path or ""
    path = WebDavApi.trim_slashes(path)
    address = WebDavApi.rtrim_slashes(address)
    -- Join our final URL, which *must* have a trailing / (it's a URL)
    -- This is where we deviate from getJoinedPath ;).
    local webdav_url = address .. "/" .. util.urlEncode(path, "/")
    if webdav_url:sub(-1) ~= "/" then
        webdav_url = webdav_url .. "/"
    end

    local sink = {}
    local data = [[<?xml version="1.0"?><a:propfind xmlns:a="DAV:"><a:prop><a:resourcetype/><a:getcontentlength/><a:getlastmodified/></a:prop></a:propfind>]]
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
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
        return
    elseif not code or code < 200 or code > 299 then
        -- got a response, but it wasn't a success (e.g. auth failure)
        logger.dbg("WebDavApi:listFolder: Request failed:", status or code)
        logger.dbg("WebDavApi:listFolder: Response headers:", headers)
        logger.dbg("WebDavApi:listFolder: Response body:", table.concat(sink))
        return
    end
    local res = table.concat(sink)
    if res == "" then return end

    local show_unsupported = G_reader_settings:isTrue("show_unsupported")
    local item_list = {}
    -- iterate through the <d:response> tags, each containing an entry
    for item in res:gmatch("<[^:]*:response[^>]*>(.-)</[^:]*:response>") do
        --logger.dbg("WebDav catalog item=", item)
        -- <d:href> is the path and filename of the entry.
        local item_fullpath = util.urlDecode(item:match("<[^:]*:href[^>]*>(.*)</[^:]*:href>"))
        local item_name = ffiUtil.basename(util.htmlEntitiesToUtf8(item_fullpath))
        local is_not_collection = item:find("<[^:]*:resourcetype%s*/>") or
                                  item:find("<[^:]*:resourcetype></[^:]*:resourcetype>")
        if is_not_collection then
            if show_unsupported or DocumentRegistry:hasProvider(item_name) then
                local file_size = tonumber(item:match("<[^:]*:getcontentlength[^>]*>(%d+)</[^:]*:getcontentlength>"))
                local modification, suffix, mandatory
                if include_folders then
                    local item_modified = item:match("<[^:]*:getlastmodified[^>]*>(.*)</[^:]*:getlastmodified>")
                    modification = item_modified and datetime.stringRFC1123ToSeconds(item_modified)
                    suffix = util.getFileNameSuffix(item_name)
                    mandatory = util.getFriendlySize(file_size)
                end
                table.insert(item_list, {
                    is_file = true,
                    text = item_name,
                    url = path .. "/" .. item_name,
                    filesize = file_size,
                    modification = modification,
                    suffix = suffix,
                    mandatory = mandatory,
                })
            end
        elseif item:find("<[^:]*:collection[^<]*/>") then
            if include_folders then
                local is_not_current_dir = WebDavApi.trim_slashes(item_fullpath) ~= path
                if is_not_current_dir then
                    table.insert(item_list, {
                        is_folder = true,
                        text = item_name .. "/",
                        url = path .. "/" .. item_name,
                    })
                end
            end
        end
    end
    return item_list
end

function WebDavApi.downloadFile(file_url, user, pass, local_path, progress_callback)
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    logger.dbg("WebDavApi: downloading file: ", file_url)
    local handle = ltn12.sink.file(io.open(local_path, "w"))
    if progress_callback then
        handle = socketutil.chainSinkWithProgressCallback(handle, progress_callback)
    end
    local code, headers, status = socket.skip(1, http.request {
        url      = file_url,
        method   = "GET",
        sink     = handle,
        user     = user,
        password = pass,
    })
    socketutil:reset_timeout()
    if code ~= 200 then
        logger.warn("WebDavApi: cannot download file:", status or code)
        logger.dbg("WebDavApi: Response headers:", headers)
    end
    return code, headers and headers.etag
end

function WebDavApi.uploadFile(file_url, user, pass, local_path, etag)
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code, _, status = socket.skip(1, http.request{
        url      = file_url,
        method   = "PUT",
        source   = ltn12.source.file(io.open(local_path, "r")),
        user     = user,
        password = pass,
        headers  = {
            ["Content-Length"] = lfs.attributes(local_path, "size"),
            ["If-Match"] = etag,
        },
    })
    socketutil:reset_timeout()
    local ok = type(code) == "number" and code >= 200 and code <= 299
    if not ok then
        logger.warn("WebDavApi: cannot upload file:", status or code)
    end
    return ok
end

function WebDavApi.deleteFile(file_url, user, pass)
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code, _, status = socket.skip(1, http.request{
        url      = file_url,
        method   = "DELETE",
        user     = user,
        password = pass,
    })
    socketutil:reset_timeout()
    local ok = type(code) == "number" and code >= 200 and code <= 299
    if not ok then
        logger.warn("WebDavApi: cannot delete file:", status or code)
    end
    return ok
end

function WebDavApi.createFolder(folder_url, user, pass)
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code, _, status = socket.skip(1, http.request{
        url      = folder_url,
        method   = "MKCOL",
        user     = user,
        password = pass,
    })
    socketutil:reset_timeout()
    local ok = type(code) == "number" and code >= 200 and code <= 299
    if not ok then
        logger.warn("WebDavApi: cannot create folder:", status or code)
    end
    return ok
end

-- WebDav

function WebDav.run(url, run_callback, include_folders)
    local base = WebDav.base
    if NetworkMgr:willRerunWhenConnected(function() WebDav.run(url, run_callback, include_folders) end) then
        return
    end
    return run_callback(WebDavApi.listFolder(base.address, base.username, base.password, url, include_folders))
end

function WebDav.downloadFile(url, local_path, progress_callback)
    local base = WebDav.base
    local path = WebDavApi.getJoinedPath(base.address, url)
    local code = WebDavApi.downloadFile(path, base.username, base.password, local_path, progress_callback)
    return code == 200
end

function WebDav.uploadFile(url, local_path)
    local base = WebDav.base
    local path = WebDavApi.getJoinedPath(base.address, url)
    path = WebDavApi.getJoinedPath(path, ffiUtil.basename(local_path))
    return WebDavApi.uploadFile(path, base.username, base.password, local_path)
end

function WebDav.deleteFile(url)
    local base = WebDav.base
    local path = WebDavApi.getJoinedPath(base.address, url)
    return WebDavApi.deleteFile(path, base.username, base.password)
end

function WebDav.createFolder(url, folder_name)
    local base = WebDav.base
    local path = WebDavApi.getJoinedPath(base.address, url)
    path = WebDavApi.getJoinedPath(path, folder_name)
    return WebDavApi.createFolder(path, base.username, base.password)
end

function WebDav.config(server_idx, caller_callback)
    local text_info = _([[Server address must be of the form http(s)://domain.name/path
This can point to a sub-directory of the WebDAV server.
The start folder is appended to the server path.]])
    local item = server_idx and WebDav.base.servers[server_idx] or { type = WebDav.type }
    local settings_dialog
    settings_dialog = MultiInputDialog:new{
        title = _("WebDAV cloud storage"),
        fields = {
            {
                text = item.name,
                hint = _("Cloud storage displayed name"),
            },
            {
                text = item.address,
                hint = _("WebDAV address, for example https://example.com/dav"),
            },
            {
                text = item.username,
                hint = _("Username"),
            },
            {
                text = item.password,
                text_type = "password",
                hint = _("Password"),
            },
            {
                text = item.url,
                hint = _("Start folder, for example /books"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(settings_dialog)
                    end,
                },
                {
                    text = _("Info"),
                    callback = function()
                        UIManager:show(InfoMessage:new{ text = text_info })
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local fields = settings_dialog:getFields()
                        -- make sure the URL is a valid path
                        if fields[5] ~= "" then
                            if not fields[5]:match('^/') then
                                fields[5] = '/' .. fields[5]
                            end
                            fields[5] = fields[5]:gsub("/$", "")
                        end
                        item.name     = fields[1]
                        item.address  = fields[2]
                        item.username = fields[3]
                        item.password = fields[4]
                        item.url      = fields[5]
                        UIManager:close(settings_dialog)
                        caller_callback(item)
                    end,
                },
            },
        },
    }
    UIManager:show(settings_dialog)
    settings_dialog:onShowKeyboard()
end

return WebDav
