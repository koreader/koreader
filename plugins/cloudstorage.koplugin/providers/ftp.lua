local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local datetime = require("datetime")
local ftp = require("socket.ftp")
local logger = require("logger")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local url_parse = require("socket.url").parse
local util = require("util")
local _ = require("gettext")

local Ftp = {
    name = _("FTP"),
    type = "ftp",
    base = nil, -- CloudStorage self, will be filled in Cloud:onShowCloudStorageList()
}

local FtpApi = {}

function FtpApi.trim_slashes(s)
    local from = s:match"^/*()"
    return from > #s and "" or s:match(".*[^/]", from)
end

function FtpApi.rtrim_slashes(s)
    local n = #s
    while n > 0 and s:find("^/", n) do
        n = n - 1
    end
    return s:sub(1, n)
end

function FtpApi.getJoinedPath(address, path)
    local path_encoded = util.urlEncode(path, "/") or ""
    local sane_path = FtpApi.trim_slashes(path_encoded)
    local sane_address = FtpApi.rtrim_slashes(address)
    return sane_address .. "/" .. sane_path
end

function FtpApi.generateUrl(address, user, pass)
    local colon_sign = ""
    local at_sign = ""
    if user ~= "" then
        at_sign = "@"
    end
    if pass ~= "" then
        colon_sign = ":"
    end
    local generated_url = "ftp://" .. user .. colon_sign .. pass .. at_sign .. address:gsub("ftp://", "")
    return generated_url
end

function FtpApi.ftpGet(u, command, sink)
    local p = url_parse(u)
    p.user = util.urlDecode(p.user)
    p.password = util.urlDecode(p.password)
    p.command = command
    p.sink = sink
    p.type = "i"  -- binary
    local r, e = ftp.get(p)
    if r == nil then
        logger.warn("Ftp get:", e)
    end
    return r, e
end

function FtpApi.parseMlsdLine(line)
    local facts, name = line:match("^([^%s]+)%s+(.*)$")
    if name and name ~= "." and name ~= ".." then
        local t = {}
        for k, v in facts:gmatch("(%w+)=([^;]+);") do
            t[k:lower()] = v
        end
        return {
            name = name,
            size = t.size,
            modify = t.modify,
        }
    end
end

function FtpApi.parseNlstLine(line, address_path)
    local name = line:match("([^/]+)$")
    if name then
        return {
            name = name,
            size = FtpApi.getSize(address_path .. "/" .. name),
        }
    end
end

function FtpApi.listFolder(address_path, folder_path, include_folders)
    local parse_func
    local tbl = {}
    local sink = ltn12.sink.table(tbl)
    local res
    if FtpApi.getFeat(address_path):find("mlsd") then
        res = FtpApi.ftpGet(address_path, "mlsd", sink)
    end
    if res then
        parse_func = FtpApi.parseMlsdLine
    else
        res = FtpApi.ftpGet(address_path, "nlst", sink)
        if res == nil then return end
        parse_func = FtpApi.parseNlstLine
    end

    if folder_path == "/" then
        folder_path = ""
    end
    local show_unsupported = G_reader_settings:isTrue("show_unsupported")
    local item_list = {}
    for line in (table.concat(tbl).."\n"):gmatch("(.-)\r?\n") do
        if line ~= "" then
            local item = parse_func(line, address_path)
            if item then
                if item.size then -- file
                    if show_unsupported or DocumentRegistry:hasProvider(item.name) then
                        local filesize, suffix, mandatory
                        filesize = tonumber(item.size)
                        if include_folders then
                            suffix = util.getFileNameSuffix(item.name)
                            mandatory = util.getFriendlySize(filesize)
                        end
                        table.insert(item_list, {
                            is_file = true,
                            text = item.name,
                            url = folder_path .. "/" .. item.name,
                            filesize = filesize,
                            modification = item.modify and datetime.stringRFC3659ToSeconds(item.modify),
                            suffix = suffix,
                            mandatory = mandatory,
                        })
                    end
                else -- folder
                    if include_folders then
                        table.insert(item_list, {
                            is_folder = true,
                            text = item.name .. "/",
                            url = folder_path .. "/" .. item.name,
                        })
                    end
                end
            end
        end
    end
    return item_list
end

function FtpApi.getFeat(address_path)
    local p = url_parse(address_path)
    p.user = util.urlDecode(p.user)
    p.password = util.urlDecode(p.password)
    p.command = "feat"
    p.check = 250
    local _, status = ftp.command(p)
    return status and status:lower()
end

function FtpApi.getSize(address_path)
    local p = url_parse(address_path)
    p.user = util.urlDecode(p.user)
    p.password = util.urlDecode(p.password)
    p.argument = string.gsub(p.path, "^/", "")
    p.command = "size"
    p.check = 250
    local _, status = ftp.command(p)
    return tonumber(status and status:match("%d.* (%d.*)")) -- "213 1234567"
end

function FtpApi.uploadFile(address_path, username, password, file_path)
    local file_name = file_path:gsub(".*/", "")
    local p = url_parse(address_path)
    p.user = util.urlDecode(username)
    p.password = util.urlDecode(password)
    p.path = p.path == "/" and file_name or p.path .. "/" .. file_name
    p.source = ltn12.source.file(io.open(file_path, "rb"))
    local code, status = ftp.put(p)
    local ok = code ~= nil -- file size
    if not ok then
        logger.warn("Ftp upload file:", status)
    end
    return ok
end

function FtpApi.deleteFile(address_path, username, password)
    local p = url_parse(address_path)
    p.user = util.urlDecode(username)
    p.password = util.urlDecode(password)
    p.argument = util.urlDecode(string.gsub(p.path, "^/", ""))
    p.command = "dele"
    p.check = 250
    local code, status = ftp.command(p)
    local ok = code == 1
    if not ok then
        logger.warn("Ftp delete file:", status)
    end
    return ok
end

function FtpApi.createFolder(address_path, username, password, folder_name)
    local p = url_parse(address_path)
    p.user = util.urlDecode(username)
    p.password = util.urlDecode(password)
    p.argument = util.urlDecode(p.path == "/" and folder_name or string.gsub(p.path, "^/", "") .. "/" .. folder_name)
    p.command = "mkd"
    local code, status = ftp.command(p)
    local ok = code == 1
    if not ok then
        logger.warn("Ftp create folder:", status)
    end
    return ok
end

-- Ftp

function Ftp.run(url, run_callback, include_folders)
    local base = Ftp.base
    if NetworkMgr:willRerunWhenConnected(function() Ftp.run(url, run_callback, include_folders) end) then
        return
    end
    local path = FtpApi.generateUrl(base.address, util.urlEncode(base.username), util.urlEncode(base.password)) .. url
    return run_callback(FtpApi.listFolder(path, url, include_folders))
end

function Ftp.downloadFile(url, local_path, progress_callback)
    local base = Ftp.base
    local path = FtpApi.generateUrl(base.address, util.urlEncode(base.username), util.urlEncode(base.password)) .. url
    local handle = ltn12.sink.file(io.open(local_path, "w"))
    if progress_callback then
        handle = socketutil.chainSinkWithProgressCallback(handle, progress_callback)
    end
    return FtpApi.ftpGet(path, "retr", handle)
end

function Ftp.uploadFile(url, local_path)
    local base = Ftp.base
    local path = FtpApi.getJoinedPath(base.address, url)
    return FtpApi.uploadFile(path, base.username, base.password, local_path)
end

function Ftp.deleteFile(url)
    local base = Ftp.base
    local path = FtpApi.getJoinedPath(base.address, url)
    return FtpApi.deleteFile(path, base.username, base.password)
end

function Ftp.createFolder(url, folder_name)
    local base = Ftp.base
    local path = FtpApi.getJoinedPath(base.address, url)
    return FtpApi.createFolder(path, base.username, base.password, folder_name)
end

function Ftp.config(server_idx, caller_callback)
    local text_info = _([[
The FTP address must be in the following format:
Ftp.//example.domain.com
An IP address is also supported, for example:
Ftp.//10.10.10.1
Username and password are optional.]])
    local item = server_idx and Ftp.base.servers[server_idx] or { type = Ftp.type }
    local settings_dialog
    settings_dialog = MultiInputDialog:new{
        title = _("FTP cloud storage"),
        fields = {
            {
                text = item.name,
                hint = _("Cloud storage displayed name"),
            },
            {
                text = item.address,
                hint = _("FTP address, for example ftp://example.com"),
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

return Ftp
