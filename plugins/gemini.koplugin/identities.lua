local Persist = require("persist")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local CheckButton = require("ui/widget/checkbutton")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local DataStorage = require("datastorage")
local url = require("socket.url")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local gemini = require("gemini")

local gemini_dir = DataStorage:getDataDir() .. "/gemini"
local ids_dir = gemini_dir .. "/identities"

local Identities = {
    active_identities_persist = Persist:new{ path = gemini_dir .. "/identities.lua" },
}

local function normaliseIdentUrl(u)
    local purl = url.parse(u, {scheme = "gemini", port = "1965"})
    if purl.scheme == "titan" then
        purl.scheme = "gemini"
    end
    if purl == nil or purl.scheme ~= "gemini" then
        return nil
    end
    purl.query = nil

    -- strip trailing slashes
    while purl.path and purl.path:sub(-1) == "/" do
        purl.path = purl.path:sub(1,-2)
    end

    return url.build(purl)
end

function Identities:setup()
    util.makePath(ids_dir)
    self.active_identities = self.active_identities_persist:load() or {}

    self:renormaliseIdentityUris()
end

function Identities:renormaliseIdentityUris()
    local renormalised = false
    for u,__ in pairs(self.active_identities) do
        local n = normaliseIdentUrl(u)
        if n ~= u then
            if not self.active_identities[n] then
                self.active_identities[n] = self.active_identities[u]
            end
            self.active_identities[u] = nil
            renormalised = true
        end
    end
    if renormalised then
        self.active_identities_persist:save(self.active_identities)
    end
end

function Identities:set(u, id)
    local n = normaliseIdentUrl(u)
    if n then
        self.active_identities[n] = id
        self.active_identities_persist:save(self.active_identities)
    end
end

-- Searches for first identity at or above u.
-- Returns identity, url where it was found, and prefix to key and crt paths.
function Identities:get(u)
    local n = normaliseIdentUrl(u)
    if n == nil then
        return nil
    end

    local id = self.active_identities[n]
    if id then
        return id, n, ids_dir.."/"..id
    end

    local up = gemini.upUrl(u)
    if up ~= u then
        return self:get(up)
    end
end

local function getIds()
    local ids = {}
    util.findFiles(ids_dir, function(path,crt)
        if crt:find("%.crt$") then
            table.insert(ids, crt:sub(0,-5))
        end
    end)
    table.sort(ids)
    return ids
end

local function chooseIdentity(callback)
    local ids = getIds()

    local widget
    local items = {}
    for _i,id in ipairs(ids) do
        table.insert(items,
        {
            text = id,
            callback = function()
                callback(id)
                UIManager:close(widget)
            end,
        })
    end
    widget = Menu:new{
        title = _("Choose identity"),
        item_table = items,
        width = Screen:getWidth(),   -- backwards compatibility;
        height = Screen:getHeight(), -- can delete for KOReader >= 2023.04
    }
    UIManager:show(widget)
end

local function createIdentityInteractive(callback)
    local widget
    local rsa_button
    local function createId(id, common_name, rsa)
        local path = ids_dir.."/"..id
        local shell_quoted_name = common_name:gsub("'","'\\''")
        local subj = shell_quoted_name == "" and "/" or "/CN="..shell_quoted_name
        if not rsa then
            os.execute("openssl ecparam -genkey -name prime256v1 > "..path..".key")
            os.execute("openssl req -x509 -new -key "..path..".key -sha256 -out "..path..".crt -days 2000000 -subj '"..subj.."'")
        else
            os.execute("openssl req -x509 -newkey rsa:2048 -keyout "..path..".key -sha256 -out "..path..".crt -days 2000000 -nodes -subj '"..subj.."'")
        end
        UIManager:close(widget)
        callback(id)
    end
    local function create_cb()
        local fields = widget:getFields()
        if fields[1] == "" then
            UIManager:show(InfoMessage:new{text = _("Enter a petname for this identity, to be used in this client to refer to the identity.")})
        elseif not fields[1]:match("^[%w_%-]+$") then
            UIManager:show(InfoMessage:new{text = _("Punctuation not allowed in petname.")})
        elseif fields[1]:len() > 12 then
            UIManager:show(InfoMessage:new{text = _("Petname too long.")})
        elseif util.fileExists(ids_dir.."/"..fields[1]..".crt") then
            UIManager:show(ConfirmBox:new{
                text = _("Identity already exists. Overwrite?"),
                ok_text = _("Destroy existing identity"),
                cancel_text = _("Cancel"),
                ok_callback = function()
                    createId(fields[1], fields[2], rsa_button.checked)
                end,
            })
        else
            createId(fields[1], fields[2])
        end
    end
    widget = MultiInputDialog:new{
        title = _("Create identity"),
        fields = {
            {
                description = _("Identity petname"),
            },
            {
                description = _("Name (optional, sent to server)"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(widget)
                    end,
                },
                {
                    text = _("Create"),
                    callback = function()
                        create_cb()
                    end
                }
            }
        },
    }
    widget.input_field[1].enter_callback = create_cb
    widget.input_field[2].enter_callback = create_cb

    --- @fixme: Seems checkbuttons added to MultiInputDialog don't appear...
    rsa_button = CheckButton:new{
        text = _("Use RSA instead of ECDSA"),
        checked = false,
        parent = widget,
    }
    widget:addWidget(rsa_button)

    UIManager:show(widget)
    widget:onShowKeyboard()
end

function Identities:confAt(u, cb)
    local n = normaliseIdentUrl(u)
    if n == nil then
        return
    end

    local widget
    local id = self:get(n)
    local function set_id(new_id)
        if new_id then
            self:set(n, new_id)
            id = new_id
            UIManager:close(widget)
            if cb then
                cb(id)
            else
                self:confAt(n)
            end
        end
    end

    widget = ButtonDialogTitle:new{
        title = T(_("Identity at %1"), gemini.showUrl(n)),
        buttons = {
            {
                {
                    text = id and T(_("Stop using identity %1"), id) or _("No identity in use"),
                    enabled = id ~= nil,
                    callback = function()
                        local delId
                        delId = function()
                            local c_id, at = self:get(n)
                            if c_id then
                                self:set(at, nil)
                                delId()
                            end
                        end
                        delId()
                        UIManager:close(widget)
                        if cb then
                            cb(nil)
                        end
                    end,
                },
            },
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(widget)
                    end
                },
                {
                    text = _("Choose identity"),
                    callback = function()
                        chooseIdentity(set_id)
                    end,
                },
                {
                    text = _("Create identity"),
                    enabled = os.execute("openssl version >& /dev/null"),
                    callback = function()
                        createIdentityInteractive(set_id)
                    end,
                },
            },
        },
    }
    UIManager:show(widget)
end

function Identities:edit()
    local menu
    local items = {}
    for u,id in pairs(self.active_identities) do
        local show_u = gemini.showUrl(u)
        table.insert(items, {
            text = T("%1: %2", id, show_u),
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = T(_("Stop using identity %1 at %2?"), id, show_u),
                    ok_text = _("Stop"),
                    cancel_text = _("Cancel"),
                    ok_callback = function()
                        UIManager:close(menu)
                        self:set(u, nil)
                        self:edit()
                    end,
                })
            end,
        })
    end
    table.sort(items, function(i1,i2) return i1.text < i2.text end)
    menu = Menu:new{
        title = _("Active identities"),
        item_table = items,
        width = Screen:getWidth(),   -- backwards compatibility;
        height = Screen:getHeight(), -- can delete for KOReader >= 2023.04
    }
    UIManager:show(menu)
end

return Identities
