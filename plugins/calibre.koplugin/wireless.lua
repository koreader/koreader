--[[
    This module implements the 'smart device app' protocol that communicates with calibre wireless server.
    More details can be found at calibre/devices/smart_device_app/driver.py.
--]]

local BD = require("ui/bidi")
local CalibreMetadata = require("metadata")
local CalibreSearch = require("search")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local FFIUtil = require("ffi/util")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local rapidjson = require("rapidjson")
local sha = require("ffi/sha2")
local util = require("util")
local _ = require("gettext")
local T = FFIUtil.template

require("ffi/zeromq_h")

-- supported formats
local extensions = require("extensions")
local function getExtensionPathLengths()
    local t = {}
    for _, v in ipairs(extensions) do
        -- magic number from calibre, see
        -- https://github.com/koreader/koreader/pull/6177#discussion_r430753964
        t[v] = 37
    end
    return t
end

-- get real free space on disk or fallback to 1GB
local function getFreeSpace(dir)
    return util.diskUsage(dir).available or 1024 * 1024 * 1024
end

-- update the view of the dir if we are currently browsing it.
local function updateDir(dir)
    local FileManager = require("apps/filemanager/filemanager")
    if FileManager:getCurrentDir() == dir then
        -- getCurrentDir() will return nil (well, nothing, technically) if there isn't an FM instance, so,
        -- unless we were passed a nil, this is technically redundant.
        if FileManager.instance then
            FileManager.instance:reinit(dir)
        end
    end
end

local CalibreWireless = InputContainer:new{
    id = "KOReader",
    model = require("device").model,
    version = require("version"):getCurrentRevision(),
    -- calibre companion local port
    port = 8134,
    -- calibre broadcast ports used to find calibre server
    broadcast_ports = {54982, 48123, 39001, 44044, 59678},
    opcodes = {
        NOOP                      = 12,
        OK                        = 0,
        ERROR                     = 20,
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
    calibre = {},
}

function CalibreWireless:init()
    -- reversed operator codes and names dictionary
    self.opnames = {}
    for name, code in pairs(self.opcodes) do
        self.opnames[code] = name
    end
end

function CalibreWireless:find_calibre_server()
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

function CalibreWireless:checkCalibreServer(host, port)
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

-- Standard JSON/control opcodes receive callback
function CalibreWireless:JSONReceiveCallback(host, port)
    -- NOTE: Closure trickery because we need a reference to *this* self *inside* the callback,
    --       which will be called as a function from another object (namely, StreamMessageQueue).
    local this = self
    return function(t)
        local data = table.concat(t)
        this:onReceiveJSON(data)
        if not this.connect_message then
            this.password_check_callback = function()
                local msg
                if this.invalid_password then
                    msg = _("Invalid password")
                    this.invalid_password = nil
                    this:disconnect()
                elseif this.disconnected_by_server then
                    msg = _("Disconnected by calibre")
                    this.disconnected_by_server = nil
                else
                    msg = T(_("Connected to calibre server at %1"),
                        BD.ltr(T("%1:%2", this.calibre_socket.host, this.calibre_socket.port)))
                end
                UIManager:show(InfoMessage:new{
                    text = msg,
                    timeout = 2,
                })
            end
            this.connect_message = true
            UIManager:scheduleIn(1, this.password_check_callback)
            if this.failed_connect_callback then
                -- Don't disconnect if we connect in 10 seconds
                UIManager:unschedule(this.failed_connect_callback)
            end
        end
    end
end

function CalibreWireless:initCalibreMQ(host, port)
    local StreamMessageQueue = require("ui/message/streammessagequeue")
    if self.calibre_socket == nil then
        self.calibre_socket = StreamMessageQueue:new{
            host = host,
            port = port,
            receiveCallback = self:JSONReceiveCallback(),
        }
        self.calibre_socket:start()
        self.calibre_messagequeue = UIManager:insertZMQ(self.calibre_socket)
    end
    logger.info("connected to calibre", host, port)
end

-- will callback initCalibreMQ if inbox is confirmed to be set
function CalibreWireless:setInboxDir(host, port)
    local force_chooser_dir
    if Device:isAndroid() then
        force_chooser_dir = Device.home_dir
    end

    local calibre_device = self

    require("ui/downloadmgr"):new{
        onConfirm = function(inbox)
            local driver = CalibreMetadata:getDeviceInfo(inbox, "device_name")
            local warning = function()
                if not driver then return end
                return not driver:lower():match("koreader") and not driver:lower():match("folder")
            end
            local save_and_resume = function()
                logger.info("set inbox directory", inbox)
                G_reader_settings:saveSetting("inbox_dir", inbox)
                if host and port then
                    CalibreMetadata:init(inbox)
                    calibre_device:initCalibreMQ(host, port)
                end
            end
            -- probably not a good idea to mix calibre drivers because
            -- their default settings usually don't match (lpath et al)
            if warning() then
                UIManager:show(ConfirmBox:new{
                    text = T(_([[This folder is already initialized as a %1.

Mixing calibre libraries is not recommended unless you know what you're doing.

Do you want to continue? ]]), driver),

                    ok_text = _("Continue"),
                    ok_callback = function()
                        save_and_resume()
                    end,
                })
            else
                save_and_resume()
            end
        end,
    }:chooseDir(force_chooser_dir)
end

function CalibreWireless:connect()
    if NetworkMgr:willRerunWhenConnected(function() self:connect() end) then
        return
    end

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
            CalibreMetadata:init(inbox_dir)
            self:initCalibreMQ(host, port)
        else
            self:setInboxDir(host, port)
        end
    else
        logger.info("cannot connect to calibre server")
        UIManager:show(InfoMessage:new{
            text = _("Cannot connect to calibre server."),
        })
        return
    end
end

function CalibreWireless:disconnect()
    logger.info("disconnect from calibre")
    self.connect_message = false
    if self.calibre_socket then
        self.calibre_socket:stop()
        self.calibre_socket = nil
    end
    if self.calibre_messagequeue then
        UIManager:removeZMQ(self.calibre_messagequeue)
        self.calibre_messagequeue = nil
    end
    CalibreMetadata:clean()

    -- Assume the library content was modified, as such, invalidate our Search metadata cache.
    CalibreSearch:invalidateCache()
end

function CalibreWireless:reconnect()
    -- to use when something went wrong and we aren't in sync with calibre
    FFIUtil.sleep(1)
    self:disconnect()
    FFIUtil.sleep(1)
    self:connect()
end

function CalibreWireless:onReceiveJSON(data)
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
        local json, err = rapidjson.decode(json_data)
        if json then
            --logger.dbg("received json table", json)
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
            elseif self.opnames[opcode] == 'SEND_BOOK' then
                self:sendBook(arg)
            elseif self.opnames[opcode] == 'DELETE_BOOK' then
                self:deleteBook(arg)
            elseif self.opnames[opcode] == 'GET_BOOK_FILE_SEGMENT' then
                self:sendToCalibre(arg)
            elseif self.opnames[opcode] == 'DISPLAY_MESSAGE' then
                self:serverFeedback(arg)
            elseif self.opnames[opcode] == 'NOOP' then
                self:noop(arg)
            end
        else
            logger.warn("failed to decode json data", err)
        end
    end
end

function CalibreWireless:sendJsonData(opname, data)
    local json, err = rapidjson.encode(rapidjson.array({self.opcodes[opname], data}))
    if json then
        -- length of json data should be before the real json data
        self.calibre_socket:send(tostring(#json)..json)
    else
        logger.warn("failed to encode json data", err)
    end
end

function CalibreWireless:getInitInfo(arg)
    logger.dbg("GET_INITIALIZATION_INFO", arg)
    local s = ""
    for i, v in ipairs(arg.calibre_version) do
        if i == #arg.calibre_version then
            s = s .. v
        else
            s = s .. v .. "."
        end
    end
    self.calibre.version = arg.calibre_version
    self.calibre.version_string = s
    local getPasswordHash = function()
        local password = G_reader_settings:readSetting("calibre_wireless_password")
        local challenge = arg.passwordChallenge
        if password and challenge then
            return sha.sha1(password..challenge)
        else
            return ""
        end
    end

    local init_info = {
        appName = self.id,
        acceptedExtensions = extensions,
        cacheUsesLpaths = true,
        canAcceptLibraryInfo = true,
        canDeleteMultipleBooks = true,
        canReceiveBookBinary = true,
        canSendOkToSendbook = true,
        canStreamBooks = true,
        canStreamMetadata = true,
        canUseCachedMetadata = true,
        ccVersionNumber = self.version,
        coverHeight = 240,
        deviceKind = self.model,
        deviceName = T("%1 (%2)", self.id, self.model),
        extensionPathLengths = getExtensionPathLengths(),
        passwordHash = getPasswordHash(),
        maxBookContentPacketLen = 4096,
        useUuidFileNames = false,
        versionOK = true,
    }
    self:sendJsonData('OK', init_info)
end

function CalibreWireless:setPassword()
    local function passwordCheck(p)
        local t = type(p)
        if t == "number" or (t == "string" and p:match("%S")) then
            return true
        end
        return false
    end
    local password_dialog
    password_dialog = InputDialog:new{
        title = _("Set a password for calibre wireless server"),
        input = G_reader_settings:readSetting("calibre_wireless_password") or "",
        buttons = {{
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(password_dialog)
                end,
            },
            {
                text = _("Set password"),
                callback = function()
                    local pass = password_dialog:getInputText()
                    if passwordCheck(pass) then
                        G_reader_settings:saveSetting("calibre_wireless_password", pass)
                    else
                        G_reader_settings:delSetting("calibre_wireless_password")
                    end
                    UIManager:close(password_dialog)
                end,
            },
        }},
    }
    UIManager:show(password_dialog)
    password_dialog:onShowKeyboard()
end

function CalibreWireless:getDeviceInfo(arg)
    logger.dbg("GET_DEVICE_INFORMATION", arg)
    local device_info = {
        device_info = {
           device_store_uuid = CalibreMetadata.drive.device_store_uuid,
           device_name = T("%1 (%2)", self.id, self.model),
        },
        version  = self.version,
        device_version = self.version,
    }
    self:sendJsonData('OK', device_info)
end

function CalibreWireless:setCalibreInfo(arg)
    logger.dbg("SET_CALIBRE_DEVICE_INFO", arg)
    CalibreMetadata:saveDeviceInfo(arg)
    self:sendJsonData('OK', {})
end

function CalibreWireless:getFreeSpace(arg)
    logger.dbg("FREE_SPACE", arg)
    local free_space = {
        free_space_on_device = getFreeSpace(G_reader_settings:readSetting("inbox_dir")),
    }
    self:sendJsonData('OK', free_space)
end

function CalibreWireless:setLibraryInfo(arg)
    logger.dbg("SET_LIBRARY_INFO", arg)
    self:sendJsonData('OK', {})
end

function CalibreWireless:getBookCount(arg)
    logger.dbg("GET_BOOK_COUNT", arg)
    local books = {
        willStream = true,
        willScan = true,
        count = #CalibreMetadata.books,
    }
    self:sendJsonData('OK', books)
    for index, _ in ipairs(CalibreMetadata.books) do
        local book = CalibreMetadata:getBookId(index)
        logger.dbg(string.format("sending book id %d/%d", index, #CalibreMetadata.books))
        self:sendJsonData('OK', book)
    end
end

function CalibreWireless:noop(arg)
    logger.dbg("NOOP", arg)
    -- calibre wants to close the socket, time to disconnect
    if arg.ejecting then
        self:sendJsonData('OK', {})
        self.disconnected_by_server = true
        self:disconnect()
        return
    end
    -- calibre announces the count of books that need more metadata
    if arg.count then
        self.pending = arg.count
        self.current = 1
        return
    end
    -- calibre requests more metadata for a book by its index
    if arg.priKey then
        local book = CalibreMetadata:getBookMetadata(arg.priKey)
        logger.dbg(string.format("sending book metadata %d/%d", self.current, self.pending))
        self:sendJsonData('OK', book)
        if self.current == self.pending then
            self.current = nil
            self.pending = nil
            return
        end
        self.current = self.current + 1
        return
    end
    -- keep-alive NOOP
    self:sendJsonData('OK', {})
end

function CalibreWireless:sendBook(arg)
    logger.dbg("SEND_BOOK", arg)
    local inbox_dir = G_reader_settings:readSetting("inbox_dir")
    local filename = inbox_dir .. "/" .. arg.lpath
    local fits = getFreeSpace(inbox_dir) >= (arg.length + 128 * 1024)
    local to_write_bytes = arg.length
    local calibre_device = self
    local calibre_socket = self.calibre_socket
    local outfile
    if fits then
        logger.dbg("write to file", filename)
        util.makePath((util.splitFilePathName(filename)))
        outfile = io.open(filename, "wb")
    else
        local msg = T(_("Can't receive file %1/%2: %3\nNo space left on device"),
            arg.thisBook + 1, arg.totalBooks, BD.filepath(filename))
        if self:isCalibreAtLeast(4, 18, 0) then
            -- report the error back to calibre
            self:sendJsonData('ERROR', {message = msg})
            return
        else
            -- report the error in the client
            UIManager:show(InfoMessage:new{
                text = msg,
                timeout = 2,
            })
            self.error_on_copy = true
        end
    end
    -- switching to raw data receiving mode
    self.calibre_socket.receiveCallback = function(t)
        local data = table.concat(t)
        --logger.info("receive file data", #data)
        --logger.info("Memory usage KB:", collectgarbage("count"))
        local to_write_data = data:sub(1, to_write_bytes)
        if fits then
            outfile:write(to_write_data)
        end
        to_write_bytes = to_write_bytes - #to_write_data
        if to_write_bytes == 0 then
            if fits then
                -- close file as all file data is received and written to local storage
                outfile:close()
                logger.dbg("complete writing file", filename)
                -- add book to local database/table
                CalibreMetadata:addBook(arg.metadata)
                UIManager:show(InfoMessage:new{
                    text = T(_("Received file %1/%2: %3"),
                        arg.thisBook + 1, arg.totalBooks, BD.filepath(filename)),
                    timeout = 2,
                })
                CalibreMetadata:saveBookList()
                updateDir(inbox_dir)
            end
            -- switch back to JSON data receiving mode
            calibre_socket.receiveCallback = calibre_device:JSONReceiveCallback()
            -- if calibre sends multiple files there may be leftover JSON data
            calibre_device.buffer = data:sub(#to_write_data + 1) or ""
            --logger.info("device buffer", calibre_device.buffer)
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
    -- end of the batch
    if (arg.thisBook + 1) == arg.totalBooks then
        if not self.error_on_copy then return end
        self.error_on_copy = nil
        UIManager:show(ConfirmBox:new{
            text = T(_("Insufficient disk space.\n\ncalibre %1 will report all books as in device. This might lead to errors. Please reconnect to get updated info"),
                self.calibre.version_string),
            ok_text = _("Reconnect"),
            ok_callback = function()
                -- send some info to avoid harmless but annoying exceptions in calibre
                self:getFreeSpace()
                self:getBookCount()
                -- scheduled because it blocks!
                UIManager:scheduleIn(1, function()
                    self:reconnect()
                end)
            end,
        })
    end
end

function CalibreWireless:deleteBook(arg)
    logger.dbg("DELETE_BOOK", arg)
    self:sendJsonData('OK', {})
    local inbox_dir = G_reader_settings:readSetting("inbox_dir")
    if not inbox_dir then return end
    -- remove all books requested by calibre
    local titles = ""
    for i, v in ipairs(arg.lpaths) do
        local book_uuid, index = CalibreMetadata:getBookUuid(v)
        if not index then
            logger.warn("requested to delete a book no longer on device", arg.lpaths[i])
        else
            titles = titles .. "\n" .. CalibreMetadata.books[index].title
            util.removeFile(inbox_dir.."/"..v)
            CalibreMetadata:removeBook(v)
        end
        self:sendJsonData('OK', { uuid = book_uuid })
        -- do things once at the end of the batch
        if i == #arg.lpaths then
            local msg
            if i == 1 then
                msg = T(_("Deleted file: %1"), BD.filepath(arg.lpaths[1]))
            else
                msg = T(_("Deleted %1 files in %2:\n %3"),
                    #arg.lpaths, BD.filepath(inbox_dir), titles)
            end
            UIManager:show(InfoMessage:new{
                text = msg,
                timeout = 2,
            })
            CalibreMetadata:saveBookList()
            updateDir(inbox_dir)
        end
    end
end

function CalibreWireless:serverFeedback(arg)
    logger.dbg("DISPLAY_MESSAGE", arg)
    -- here we only care about password errors
    if arg.messageKind == 1 then
        self.invalid_password = true
    end
end

function CalibreWireless:sendToCalibre(arg)
    logger.dbg("GET_BOOK_FILE_SEGMENT", arg)
    local inbox_dir = G_reader_settings:readSetting("inbox_dir")
    local path = inbox_dir .. "/" .. arg.lpath

    local file_size = lfs.attributes(path, "size")
    if not file_size then
        self:sendJsonData("NOOP", {})
        return
    end

    local file = io.open(path, "rb")
    if not file then
        self:sendJsonData("NOOP", {})
        return
    end

    self:sendJsonData("OK", { fileLength = file_size })

    while true do
        local data = file:read(4096)
        if not data then break end
        self.calibre_socket:send(data)
    end

    file:close()
end

function CalibreWireless:isCalibreAtLeast(x, y, z)
    local v = self.calibre.version
    local function semanticVersion(a, b, c)
        return ((a * 100000) + (b * 1000)) + c
    end
    return semanticVersion(v[1], v[2], v[3]) >= semanticVersion(x, y, z)
end

return CalibreWireless
