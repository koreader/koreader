local InputContainer = require("ui/widget/container/inputcontainer")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local ltn12 = require("ltn12")
local DEBUG = require("dbg")
local _ = require("gettext")

local ffi = require("ffi")
ffi.cdef[[
int remove(const char *);
int rmdir(const char *);
]]

require("ffi/zeromq_h")
local ZSync = InputContainer:new{
    name = "zsync",
    is_doc_only = true,
}

function ZSync:init()
    self.ui.menu:registerToMainMenu(self)
    self.outbox = self.path.."/outbox"
    self.server_config = self.path.."/server.cfg"
    self.client_config = self.path.."/client.cfg"
end

function ZSync:addToMainMenu(menu_items)
    menu_items.zsync = {
        text = _("ZSync"),
        sub_item_table = {
            {
                text_func = function()
                    return not self.filemq_server
                        and _("Share this document")
                        or _("Stop sharing books")
                end,
                enabled_func = function()
                    return self.filemq_client == nil
                end,
                callback = function()
                    if not self.filemq_server then
                        self:publish()
                    else
                        self:unpublish()
                    end
                end
            },
            {
                text_func = function()
                    return not self.filemq_client
                        and _("Subscribe to book share")
                        or _("Unsubscribe from book share")
                end,
                enabled_func = function()
                    return self.filemq_server == nil
                end,
                callback = function()
                    if not self.filemq_client then
                        self:subscribe()
                    else
                        self:unsubscribe()
                    end
                end
            }
        }
    }
end

function ZSync:initServerZyreMQ()
    local ZyreMessageQueue = require("ui/message/zyremessagequeue")
    if self.zyre_messagequeue == nil then
        self.server_zyre = ZyreMessageQueue:new{
            header = {["FILEMQ-SERVER"] = tostring(self.fmq_port)},
        }
        self.server_zyre:start()
        self.zyre_messagequeue = UIManager:insertZMQ(self.server_zyre)
    end
end

function ZSync:initClientZyreMQ()
    local ZyreMessageQueue = require("ui/message/zyremessagequeue")
    if self.zyre_messagequeue == nil then
        self.client_zyre = ZyreMessageQueue:new{}
        self.client_zyre:start()
        self.zyre_messagequeue = UIManager:insertZMQ(self.client_zyre)
    end
end

function ZSync:initServerFileMQ(outboxes)
    local FileMessageQueue = require("ui/message/filemessagequeue")
    local filemq = ffi.load("libs/libfmq.so.1")
    if self.file_messagequeue == nil then
        self.filemq_server = filemq.fmq_server_new()
        self.file_messagequeue = UIManager:insertZMQ(FileMessageQueue:new{
            server = self.filemq_server
        })
        self.fmq_port = filemq.fmq_server_bind(self.filemq_server, "tcp://*:*")
        filemq.fmq_server_configure(self.filemq_server, self.server_config)
        filemq.fmq_server_set_anonymous(self.filemq_server, true)
    end
    UIManager:scheduleIn(1, function()
        for _, outbox in ipairs(outboxes) do
            DEBUG("publish", outbox.path, outbox.alias)
            filemq.fmq_server_publish(self.filemq_server, outbox.path, outbox.alias)
        end
    end)
end

function ZSync:initClientFileMQ(inbox)
    local FileMessageQueue = require("ui/message/filemessagequeue")
    local filemq = ffi.load("libs/libfmq.so.1")
    if self.file_messagequeue == nil then
        self.filemq_client = filemq.fmq_client_new()
        self.file_messagequeue = UIManager:insertZMQ(FileMessageQueue:new{
            client = self.filemq_client
        })
        filemq.fmq_client_configure(self.filemq_client, self.client_config)
    end
    UIManager:scheduleIn(1, function()
        filemq.fmq_client_set_inbox(self.filemq_client, inbox)
    end)
end

local function clearDirectory(dir, rmdir)
    for f in lfs.dir(dir) do
        local path = dir.."/"..f
        local mode = lfs.attributes(path, "mode")
        if mode == "file" then
            ffi.C.remove(path)
        elseif mode == "directory" and f ~= "." and f ~= ".." then
            clearDirectory(path, true)
        end
    end
    if rmdir then
        ffi.C.rmdir(dir)
    end
end

local function mklink(path, filename)
    local basename = filename:match(".*/(.*)") or filename
    local linkname = path .. "/" .. basename .. ".ln"
    local linkfile = io.open(linkname, "w")
    if linkfile then
        linkfile:write(filename .. "\n")
        linkfile:close()
    end
end

-- add directory directly into outboxes
function ZSync:outboxesAddDirectory(outboxes, dir)
    if lfs.attributes(dir, "mode") == "directory" then
        local basename = dir:match(".*/(.*)") or dir
        table.insert(outboxes, {
            path = dir,
            alias = "/"..basename,
        })
    end
end

-- link file in root outbox
function ZSync:outboxAddFileLink(filename)
    local mode = lfs.attributes(filename, "mode")
    if mode == "file" then
        mklink(self.outbox, filename)
    end
end

-- copy directory content into root outbox(no recursively)
function ZSync:outboxCopyDirectory(dir)
    local basename = dir:match(".*/(.*)") or dir
    local newdir = self.outbox.."/"..basename
    lfs.mkdir(newdir)
    if pcall(lfs.dir, dir) then
        for f in lfs.dir(dir) do
            local filename = dir.."/"..f
            if lfs.attributes(filename, "mode") == "file" then
                local newfile = newdir.."/"..f
                ltn12.pump.all(
                    ltn12.source.file(assert(io.open(filename, "rb"))),
                    ltn12.sink.file(assert(io.open(newfile, "wb")))
                )
            end
        end
    end
end

function ZSync:publish()
    DEBUG("publish document", self.view.document.file)
    lfs.mkdir(self.outbox)
    clearDirectory(self.outbox)
    local file = self.view.document.file
    local sidecar = file:match("(.*)%.")..".sdr"
    self:outboxAddFileLink(file)
    self:outboxCopyDirectory(sidecar)
    local outboxes = {}
    table.insert(outboxes, {
        path = self.outbox,
        alias = "/",
    })
    -- init filemq first to get filemq port
    self:initServerFileMQ(outboxes)
    self:initServerZyreMQ()
end

function ZSync:unpublish()
    DEBUG("ZSync unpublish")
    clearDirectory(self.outbox)
    self:stopZyreMQ()
    self:stopFileMQ()
end

function ZSync:onChooseInbox(inbox)
    DEBUG("choose inbox", inbox)
    self.inbox = inbox
    -- init zyre first for filemq endpoint
    self:initClientZyreMQ()
    self:initClientFileMQ(inbox)
    return true
end

function ZSync:subscribe()
    DEBUG("subscribe documents")
    self.received = {}
    local zsync = self
    require("ui/downloadmgr"):new{
        title = _("Choose inbox"),
        onConfirm = function(inbox)
            G_reader_settings:saveSetting("inbox_dir", inbox)
            zsync:onChooseInbox(inbox)
        end,
    }:chooseDir()
end

function ZSync:unsubscribe()
    DEBUG("ZSync unsubscribe")
    self.received = {}
    self:stopFileMQ()
    self:stopZyreMQ()
end

function ZSync:onZyreEnter(id, name, header, endpoint)
    local filemq = ffi.load("libs/libfmq.so.1")
    if header and endpoint and header["FILEMQ-SERVER"] then
        self.server_zyre_endpoint = endpoint
        local port = header["FILEMQ-SERVER"]
        local host = endpoint:match("(.*:)") or "*:"
        local fmq_server_endpoint = host..port
        DEBUG("connect filemq server at", fmq_server_endpoint)
        -- wait for filemq server setup befor connecting
        UIManager:scheduleIn(2, function()
            filemq.fmq_client_set_resync(self.filemq_client, true)
            filemq.fmq_client_subscribe(self.filemq_client, "/")
            filemq.fmq_client_connect(self.filemq_client, fmq_server_endpoint)
        end)
    end
    return true
end

function ZSync:onFileDeliver(filename, fullname)
    -- sometimes several FileDelever msgs are sent from filemq
    if self.received[filename] then return end
    UIManager:show(InfoMessage:new{
        text = _("Received file:") .. "\n" .. filename,
        timeout = 1,
    })
    self.received[filename] = true
end

--[[
-- We assume that ZSync is running in either server mode or client mode
-- but never both. The zyre_messagequeue may be a server_zyre or client_zyre.
-- And the file_messagequeue may be a filemq_server or filemq_client.
--]]
function ZSync:stopZyreMQ()
    if self.zyre_messagequeue then
        self.zyre_messagequeue:stop()
        UIManager:removeZMQ(self.zyre_messagequeue)
        self.zyre_messagequeue = nil
        self.server_zyre = nil
        self.client_zyre = nil
    end
end

function ZSync:stopFileMQ()
    if self.file_messagequeue then
        self.file_messagequeue:stop()
        UIManager:removeZMQ(self.file_messagequeue)
        self.file_messagequeue = nil
        self.filemq_server = nil
        self.filemq_client = nil
    end
end

function ZSync:onCloseReader()
    self:stopZyreMQ()
    self:stopFileMQ()
end

return ZSync

