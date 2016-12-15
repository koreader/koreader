local ftp = require("socket.ftp")
local ltn12 = require("ltn12")
local url = require("socket.url")
local InputContainer = require("ui/widget/container/inputcontainer")
local DocumentRegistry = require("document/documentregistry")

local FtpApi = InputContainer:new{
}
function FtpApi:nlst(u)
    local t = {}
    local p = url.parse(u)
    p.command = "nlst"
    p.sink = ltn12.sink.table(t)
    local r, e = ftp.get(p)
    return r and table.concat(t), e
end

function FtpApi:listFolder(address_path)
    local ftp_list = {}
    local ftp_file = {}
    local type
    local extension
    local file_name
    local ls_ftp = self:nlst(address_path)
    if ls_ftp == nil then return false end
    for item in (ls_ftp..'\n'):gmatch'(.-)\r?\n' do
        if item ~= '' then
            file_name = item:match("([^/]+)$")
            extension = item:match("^.+(%..+)$")
            item = "/" .. item
            if not extension then
                type = "folder"
                table.insert(ftp_list, {
                    text = file_name .. "/",
                    url = item,
                    type = type,
                })
            --show only file with supported formats
            elseif extension  and DocumentRegistry:getProvider(item) then
                type = "file"
                table.insert(ftp_file, {
                    text = file_name,
                    url = item,
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

function FtpApi:downloadFile(file_path)
    return ftp.get(file_path ..";type=i")
end

return FtpApi
