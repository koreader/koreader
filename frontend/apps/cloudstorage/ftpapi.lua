local DocumentRegistry = require("document/documentregistry")
local ftp = require("socket.ftp")
local ltn12 = require("ltn12")
local util = require("util")
local url = require("socket.url")

local FtpApi = {
}

function FtpApi:generateUrl(address, user, pass)
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

function FtpApi:ftpGet(u, command)
    local t = {}
    local p = url.parse(u)
    p.user = util.urlDecode(p.user)
    p.password = util.urlDecode(p.password)
    p.command = command
    p.sink = ltn12.sink.table(t)
    p.type = "i"  -- binary
    local r, e = ftp.get(p)
    return r and table.concat(t), e
end

function FtpApi:listFolder(address_path, folder_path)
    local ftp_list = {}
    local ftp_file = {}
    local type
    local extension
    local file_name
    local ls_ftp = self:ftpGet(address_path, "nlst")
    if ls_ftp == nil then return false end
    if folder_path == "/" then
        folder_path = ""
    end
    for item in (ls_ftp..'\n'):gmatch'(.-)\r?\n' do
        if item ~= '' then
            file_name = item:match("([^/]+)$")
            extension = item:match("^.+(%..+)$")
            if not extension then
                type = "folder"
                table.insert(ftp_list, {
                    text = file_name .. "/",
                    url = string.format("%s/%s",folder_path, file_name),
                    type = type,
                })
            --show only file with supported formats
            elseif extension  and (DocumentRegistry:hasProvider(item)
                or G_reader_settings:isTrue("show_unsupported")) then
                type = "file"
                table.insert(ftp_file, {
                    text = file_name,
                    url = string.format("%s/%s",folder_path, file_name),
                    type = type,
                })
            end
        end
    end
    --sort
    table.sort(ftp_list, function(v1,v2)
        return v1.text < v2.text
    end)
    table.sort(ftp_file, function(v1,v2)
        return v1.text < v2.text
    end)
    for _, files in ipairs(ftp_file) do
        table.insert(ftp_list, {
            text = files.text,
            url = files.url,
            type = files.type
        })
    end
    return ftp_list
end

function FtpApi:delete(file_path)
    local p = url.parse(file_path)
    p.user = util.urlDecode(p.user)
    p.password = util.urlDecode(p.password)
    p.argument = string.gsub(p.path, "^/", "")
    p.command = "dele"
    p.check = 250
    return ftp.command(p)
end

return FtpApi
