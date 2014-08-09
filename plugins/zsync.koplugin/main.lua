local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local FileManager = require("apps/filemanager/filemanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local ButtonDialog = require("ui/widget/buttondialog")
local FileChooser = require("ui/widget/filechooser")
local InfoMessage = require("ui/widget/infomessage")
local TextWidget = require("ui/widget/textwidget")
local DocSettings = require("docsettings")
local UIManager = require("ui/uimanager")
local Screen = require("ui/screen")
local Event = require("ui/event")
local Font = require("ui/font")
local ltn12 = require("ltn12")
local DEBUG = require("dbg")
local _ = require("gettext")
local util = require("ffi/util")
-- lfs

local ffi = require("ffi")
ffi.cdef[[
int remove(const char *);
int rmdir(const char *);
]]

local dummy = require("ffi/zeromq_h")
local ZSync = InputContainer:new{
}

function ZSync:init()
    self.ui.menu:registerToMainMenu(self)
    self.outbox = self.path.."/outbox"
    self.server_config = self.path.."/server.cfg"
    self.client_config = self.path.."/client.cfg"
end

function ZSync:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, {
        text = "ZSync",
        sub_item_table = {
            {
                text_func = function()
                    return not self.filemq_server
                        and _("Publish this document")
                        or _("Stop publisher")
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
                        and _("Subscribe documents")
                        or _("Stop subscriber")
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
    })
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

local InboxChooser = InputContainer:new{
    title = _("Choose inbox"),
    dimen = Screen:getSize(),
    exclude_dirs = {"%.sdr$"},
}

function InboxChooser:init()
    self.show_parent = self.show_parent or self
    local banner = VerticalGroup:new{
        TextWidget:new{
            face = Font:getFace("tfont", 24),
            text = _("Choose inbox"),
        },
        VerticalSpan:new{ width = Screen:scaleByDPI(10) }
    }

    local g_show_hidden = G_reader_settings:readSetting("show_hidden")
    local show_hidden = g_show_hidden == nil and DSHOWHIDDENFILES or g_show_hidden
    local root_path = G_reader_settings:readSetting("lastdir") or lfs.currentdir()
    local file_chooser = FileChooser:new{
        -- remeber to adjust the height when new item is added to the group
        path = root_path,
        show_parent = self.show_parent,
        show_hidden = show_hidden,
        height = Screen:getHeight() - banner:getSize().h,
        is_popout = false,
        is_borderless = true,
        dir_filter = function(dirname)
            for _, pattern in ipairs(self.exclude_dirs) do
                if dirname:match(pattern) then return end
            end
            return true
        end,
        file_filter = function(filename) end,
        close_callback = function() UIManager:close(self) end,
    }

    local on_close_chooser = function() self:onClose() end
    local on_confirm_inbox = function(inbox) self:onConfirm(inbox) end

    function file_chooser:onFileHold(dir)
        self.chooser_dialog = self
        self.button_dialog = ButtonDialog:new{
            buttons = {
                {
                    {
                        text = _("Confirm"),
                        callback = function()
                            UIManager:close(self.button_dialog)
                            on_confirm_inbox(dir)
                            on_close_chooser()
                        end,
                    },
                    {
                        text = _("Cancel"),
                        callback = function()
                            UIManager:close(self.button_dialog)
                            on_close_chooser()
                        end,
                    },
                },
            },
        }
        UIManager:show(self.button_dialog)
        return true
    end

    self[1] = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        background = 0,
        VerticalGroup:new{
            banner,
            file_chooser,
        }
    }
end

function InboxChooser:onClose()
    UIManager:close(self)
    return true
end

function InboxChooser:onConfirm(inbox)
    if inbox:sub(-3, -1) == "/.." then
        inbox = inbox:sub(1, -4)
    end
    G_reader_settings:saveSetting("lastdir", inbox)
    self.zsync:onChooseInbox(inbox)
    return true
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
    self.inbox_chooser = InboxChooser:new{zsync = self}
    UIManager:show(self.inbox_chooser)
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

