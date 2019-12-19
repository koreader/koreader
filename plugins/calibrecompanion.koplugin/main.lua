local BD = require("ui/bidi")
local InputContainer = require("ui/widget/container/inputcontainer")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local JSON = require("json")
local _ = require("gettext")
local NetworkMgr = require("ui/network/manager")
local logger = require("logger")
local util = require("frontend/util")
local T = require("ffi/util").template

require("ffi/zeromq_h")

--[[
    This plugin implements a simple Calibre Companion protocol that communicates
    with Calibre Wireless Server from which users can send documents to KOReader
    devices directly with WIFI connection.

    Note that Calibre Companion(CC) is a trade mark held by MultiPie Ltd. The
    Android app Calibre Companion provided by MultiPie is closed-source. This
    plugin only implements a subset function of CC according to the open-source
    smart device driver from Calibre source tree.

    More details can be found at calibre/devices/smart_device_app/driver.py.
--]]
local CalibreCompanion = InputContainer:new{
    name = "calibrecompanion",
    -- calibre companion local port
    port = 8134,
    -- calibre broadcast ports used to find calibre server
    broadcast_ports = {54982, 48123, 39001, 44044, 59678},
    opcodes = {
        NOOP                      = 12,
        OK                        = 0,
        BOOK_DONE                 = 11,
        CALIBRE_BUSY              = 18,
        SET_LIBRARY_INFO          = 19,
        DELETE_BOOK               = 13,
        DISPLAY_MESSAGE           = 17,
        FREE_SPACE                = 5,
        GET_BOOK_FILE_SEGMENT     = 14,
        GET_BOOK_METADATA         = 15,
        GET_BOOK_COUNT            = 6,
        GET_DEVICE_INFORMATION    = 3,
        GET_INITIALIZATION_INFO   = 9,
        SEND_BOOKLISTS            = 7,
        SEND_BOOK                 = 8,
        SEND_BOOK_METADATA        = 16,
        SET_CALIBRE_DEVICE_INFO   = 1,
        SET_CALIBRE_DEVICE_NAME   = 2,
        TOTAL_SPACE               = 4,
    },
}

function CalibreCompanion:init()
    -- reversed operator codes and names dictionary
    self.opnames = {}
    for name, code in pairs(self.opcodes) do
        self.opnames[code] = name
    end
    self.ui.menu:registerToMainMenu(self)
end

function CalibreCompanion:find_calibre_server()
    local socket = require("socket")
    local udp = socket.udp4()
    udp:setoption("broadcast", true)
    udp:setsockname("*", 8134)
    udp:settimeout(3)
    for _, port in ipairs(self.broadcast_ports) do
        -- broadcast anything to calibre ports and listen to the reply
        local _, err = udp:sendto("hello", "255.255.255.255", port)
        if not err then
            local dgram, host = udp:receivefrom()
            if dgram and host then
                -- replied diagram has greet message from calibre and calibre hostname
                -- calibre opds port and calibre socket port we will later connect to
                local _, _, _, replied_port = dgram:match("(.-)%(on (.-)%);(.-),(.-)$")
                return host, replied_port
            end
        end
    end
end

function CalibreCompanion:checkCalibreServer(host, port)
    local socket = require("socket")
    local tcp = socket.tcp()
    tcp:settimeout(5)
    local client = tcp:connect(host, port)
    -- In case of error, the method returns nil followed by a string describing the error. In case of success, the method returns 1.
    if client then
        tcp:close()
        return true
    end
    return false
end

function CalibreCompanion:addToMainMenu(menu_items)
    menu_items.calibre_wireless_connection = {
        text = _("calibre wireless connection"),
        sub_item_table = {
            {
                text_func = function()
                    if self.calibre_socket then
                        return _("Disconnect")
                    else
                        return _("Connect")
                    end
                end,
                callback = function()
                    if not self.calibre_socket then
                        self:connect()
                    else
                        self:disconnect()
                    end
                end
            },
            {
                text = _("Set inbox directory"),
                callback = function()
                    CalibreCompanion:setInboxDir()
                end
            },
            {
                text_func = function()
                    local address = _("automatic")
                    if G_reader_settings:has("calibre_wireless_url") then
                        address = G_reader_settings:readSetting("calibre_wireless_url")
                        address = string.format("%s:%s", address["address"], address["port"])
                    end
                    return T(_("Server address (%1)"), BD.ltr(address))
                end,
                sub_item_table = {
                    {
                        text = _("Automatic"),
                        checked_func = function()
                            return G_reader_settings:hasNot("calibre_wireless_url")
                        end,
                        callback = function()
                            G_reader_settings:delSetting("calibre_wireless_url")
                        end,
                    },
                    {
                        text = _("Manual"),
                        checked_func = function()
                            return G_reader_settings:has("calibre_wireless_url")
                        end,
                        callback = function(touchmenu_instance)
                            local MultiInputDialog = require("ui/widget/multiinputdialog")
                            local url_dialog
                            local calibre_url = G_reader_settings:readSetting("calibre_wireless_url")
                            local calibre_url_address, calibre_url_port
                            if calibre_url then
                                calibre_url_address = calibre_url["address"]
                                calibre_url_port = calibre_url["port"]
                            end
                            url_dialog = MultiInputDialog:new{
                                title = _("Set custom calibre address"),
                                fields = {
                                    {
                                        text = calibre_url_address,
                                        input_type = "string",
                                        hint = _("IP Address"),
                                    },
                                    {
                                        text = calibre_url_port,
                                        input_type = "number",
                                        hint = _("Port"),
                                    },
                                },
                                buttons =  {
                                    {
                                        {
                                            text = _("Cancel"),
                                            callback = function()
                                                UIManager:close(url_dialog)
                                            end,
                                        },
                                        {
                                            text = _("OK"),
                                            callback = function()
                                                local fields = url_dialog:getFields()
                                                if fields[1] ~= "" then
                                                    local port = tonumber(fields[2])
                                                    if not port or port < 1 or port > 65355 then
                                                        --default port
                                                        port = 9090
                                                    end
                                                    G_reader_settings:saveSetting("calibre_wireless_url", {address = fields[1], port = port })
                                                end
                                                UIManager:close(url_dialog)
                                                if touchmenu_instance then touchmenu_instance:updateItems() end
                                            end,
                                        },
                                    },
                                },
                            }
                            UIManager:show(url_dialog)
                            url_dialog:onShowKeyboard()
                       end,
                    },
                }
            }
        }
    }
end

function CalibreCompanion:initCalibreMQ(host, port)
    local StreamMessageQueue = require("ui/message/streammessagequeue")
    if self.calibre_socket == nil then
        self.calibre_socket = StreamMessageQueue:new{
            host = host,
            port = port,
            receiveCallback = function(data)
                self:onReceiveJSON(data)
                if not self.connect_message then
                    UIManager:show(InfoMessage:new{
                        text = T(_("Connected to calibre server at %1"), BD.ltr(T("%1:%2", host, port))),
                    })
                    self.connect_message = true
                    if self.failed_connect_callback then
                        --don't disconnect if we connect in 10 seconds
                        UIManager:unschedule(self.failed_connect_callback)
                    end
                end
            end,
        }
        self.calibre_socket:start()
        self.calibre_messagequeue = UIManager:insertZMQ(self.calibre_socket)
    end
    logger.info("connected to calibre", host, port)
end

-- will callback initCalibreMQ if inbox is confirmed to be set
function CalibreCompanion:setInboxDir(host, port)
    local calibre_device = self
    require("ui/downloadmgr"):new{
        onConfirm = function(inbox)
            logger.info("set inbox directory", inbox)
            G_reader_settings:saveSetting("inbox_dir", inbox)
            if host and port then
                calibre_device:initCalibreMQ(host, port)
            end
        end,
    }:chooseDir()
end

function CalibreCompanion:connect()
    self.connect_message = false
    local host, port
    if G_reader_settings:hasNot("calibre_wireless_url") then
        host, port = self:find_calibre_server()
    else
        local calibre_url = G_reader_settings:readSetting("calibre_wireless_url")
        host, port = calibre_url["address"], calibre_url["port"]
        if not self:checkCalibreServer(host, port) then
            host = nil
        else
            self.failed_connect_callback = function()
                UIManager:show(InfoMessage:new{
                    text = _("Cannot connect to calibre server."),
                })
                self:disconnect()
            end
            -- wait 10 seconds to connect to calibre
            UIManager:scheduleIn(10, self.failed_connect_callback)
        end
    end
    if host and port then
        local inbox_dir = G_reader_settings:readSetting("inbox_dir")
        if inbox_dir then
            self:initCalibreMQ(host, port)
        else
            self:setInboxDir(host, port)
        end
    elseif not NetworkMgr:isConnected() then
        NetworkMgr:promptWifiOn()
    else
        logger.info("cannot connect to calibre server")
        UIManager:show(InfoMessage:new{
            text = _("Cannot connect to calibre server."),
        })
        return
    end
end

function CalibreCompanion:disconnect()
    logger.info("disconnect from calibre")
    self.connect_message = false
    self.calibre_socket:stop()
    UIManager:removeZMQ(self.calibre_messagequeue)
    self.calibre_socket = nil
    self.calibre_messagequeue = nil
end

function CalibreCompanion:onReceiveJSON(data)
    self.buffer = (self.buffer or "") .. (data or "")
    --logger.info("data buffer", self.buffer)
    -- messages from calibre stream socket are encoded in JSON strings like this
    -- 34[0, {"key0":value, "key1": value}]
    -- the JSON string has a leading length string field followed by the actual
    -- JSON data in which the first element is always the operator code which can
    -- be looked up in the opnames dictionary
    while self.buffer ~= nil do
        --logger.info("buffer", self.buffer)
        local index = self.buffer:find('%[') or 1
        local size = tonumber(self.buffer:sub(1, index - 1))
        local json_data
        if size and #self.buffer >= index - 1 + size then
            json_data = self.buffer:sub(index, index - 1 + size)
            --logger.info("json_data", json_data)
            -- reset buffer to nil if all buffer is copied out to json data
            self.buffer = self.buffer:sub(index + size)
            --logger.info("new buffer", self.buffer)
        -- data is not complete which means there are still missing data not received
        else
            return
        end
        local ok, json = pcall(JSON.decode, json_data)
        if ok and json then
            logger.dbg("received json table", json)
            local opcode = json[1]
            local arg = json[2]
            if self.opnames[opcode] == 'GET_INITIALIZATION_INFO' then
                self:getInitInfo(arg)
            elseif self.opnames[opcode] == 'GET_DEVICE_INFORMATION' then
                self:getDeviceInfo(arg)
            elseif self.opnames[opcode] == 'SET_CALIBRE_DEVICE_INFO' then
                self:setCalibreInfo(arg)
            elseif self.opnames[opcode] == 'FREE_SPACE' then
                self:getFreeSpace(arg)
            elseif self.opnames[opcode] == 'SET_LIBRARY_INFO' then
                self:setLibraryInfo(arg)
            elseif self.opnames[opcode] == 'GET_BOOK_COUNT' then
                self:getBookCount(arg)
            elseif self.opnames[opcode] == 'SEND_BOOKLISTS' then
                self:sendBooklists(arg)
            elseif self.opnames[opcode] == 'SEND_BOOK' then
                self:sendBook(arg)
            elseif self.opnames[opcode] == 'NOOP' then
                self:noop(arg)
            end
        else
            logger.dbg("failed to decode json data", json_data)
        end
    end
end

function CalibreCompanion:sendJsonData(opname, data)
    local ok, json = pcall(JSON.encode, {self.opcodes[opname], data})
    if ok and json then
        -- length of json data should be before the real json data
        self.calibre_socket:send(tostring(#json)..json)
    end
end

function CalibreCompanion:getInitInfo(arg)
    logger.dbg("GET_INITIALIZATION_INFO", arg)
    self.calibre_info = arg
    local init_info = {
        canUseCachedMetadata = true,
        acceptedExtensions = {"epub", "mobi", "pdf", "djvu", "fb2", "pdb", "cbz"},
        canStreamMetadata = true,
        canAcceptLibraryInfo = true,
        extensionPathLengths = {
            epub = 42,
            mobi = 42,
            pdf = 42,
            djvu = 42,
            fb2 = 42,
            pdb = 42,
            cbz = 42,
        },
        useUuidFileNames = false,
        passwordHash = "",
        canReceiveBookBinary = true,
        maxBookContentPacketLen = 4096,
        appName = "KOReader Calibre plugin",
        ccVersionNumber = 106,
        deviceName = "KOReader",
        canStreamBooks = true,
        versionOK = true,
        canDeleteMultipleBooks = true,
        canSendOkToSendbook = true,
        coverHeight = 240,
        cacheUsesLpaths = true,
        deviceKind = "KOReader",
    }
    self:sendJsonData('OK', init_info)
end

function CalibreCompanion:getDeviceInfo(arg)
    logger.dbg("GET_DEVICE_INFORMATION", arg)
    local device_info = {
        device_info = {
           device_store_uuid = G_reader_settings:readSetting("device_store_uuid"),
           device_name = "KOReader Calibre Companion",
        },
        version  = 106,
        device_version = "KOReader",
    }
    self:sendJsonData('OK', device_info)
end

function CalibreCompanion:setCalibreInfo(arg)
    logger.dbg("SET_CALIBRE_DEVICE_INFO", arg)
    self.calibre_info = arg
    G_reader_settings:saveSetting("device_store_uuid", arg.device_store_uuid)
    self:sendJsonData('OK', {})
end

function CalibreCompanion:getFreeSpace(arg)
    logger.dbg("FREE_SPACE", arg)
    --- @todo Portable free space calculation?
    -- Assume we have 1GB of free space on device.
    local free_space = {
        free_space_on_device = 1024*1024*1024,
    }
    self:sendJsonData('OK', free_space)
end

function CalibreCompanion:setLibraryInfo(arg)
    logger.dbg("SET_LIBRARY_INFO", arg)
    self.library_info = arg
    self:sendJsonData('OK', {})
end

function CalibreCompanion:getBookCount(arg)
    logger.dbg("GET_BOOK_COUNT", arg)
    local books = {
        willStream = true,
        willScan = true,
        count = 0,
    }
    self:sendJsonData('OK', books)
end

function CalibreCompanion:noop(arg)
    logger.dbg("NOOP", arg)
    if not arg.count then
        self:sendJsonData('OK', {})
    end
end

function CalibreCompanion:sendBooklists(arg)
    logger.dbg("SEND_BOOKLISTS", arg)
end

function CalibreCompanion:sendBook(arg)
    logger.dbg("SEND_BOOK", arg)
    local inbox_dir = G_reader_settings:readSetting("inbox_dir")
    local filename = inbox_dir .. "/" .. arg.lpath
    logger.dbg("write to file", filename)
    util.makePath((util.splitFilePathName(filename)))
    local outfile = io.open(filename, "wb")
    local to_write_bytes = arg.length
    local calibre_device = self
    local calibre_socket = self.calibre_socket
    -- switching to raw data receiving mode
    self.calibre_socket.receiveCallback = function(data)
        --logger.info("receive file data", #data)
        --logger.info("Memory usage KB:", collectgarbage("count"))
        local to_write_data = data:sub(1, to_write_bytes)
        outfile:write(to_write_data)
        to_write_bytes = to_write_bytes - #to_write_data
        if to_write_bytes == 0 then
            -- close file as all file data is received and written to local storage
            outfile:close()
            logger.info("complete writing file", filename)
            UIManager:show(InfoMessage:new{
                text = _("Received file:") .. BD.filepath(filename),
                timeout = 1,
            })
            -- switch to JSON data receiving mode
            calibre_socket.receiveCallback = function(json_data)
                calibre_device:onReceiveJSON(json_data)
            end
            -- if calibre sends multiple files there may be left JSON data
            calibre_device.buffer = data:sub(#to_write_data + 1) or ""
            logger.info("device buffer", calibre_device.buffer)
            if calibre_device.buffer ~= "" then
                UIManager:scheduleIn(0.1, function()
                    -- since data is already copied to buffer
                    -- onReceiveJSON parameter should be nil
                    calibre_device:onReceiveJSON()
                end)
            end
        end
    end
    self:sendJsonData('OK', {})
end

return CalibreCompanion
