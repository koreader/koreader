--[[--
Network setting widget.

Example:

    local network_list = {
        {
            ssid = "foo",
            signal_level = -58,
            flags = "[WPA2-PSK-CCMP][ESS]",
            signal_quality = 84,
            password = "123abc",
            connected = true,
        },
        {
            ssid = "bar",
            signal_level = -258,
            signal_quality = 44,
            flags = "[WEP][ESS]",
        },
    }
    UIManager:show(require("ui/widget/networksetting"):new{
        network_list = network_list,
        connect_callback = function()
            -- connect_callback will be called when a *connect* (NOT disconnect)
            -- attempt has been successful.
            -- You can update UI widgets in the callback.
        end,
        disconnect_callback = function()
            -- This one will fire unconditionally after a disconnect attempt.
        end,
    })

]]

local BD = require("ui/bidi")
local bit = require("bit")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LeftContainer = require("ui/widget/container/leftcontainer")
local ListView = require("ui/widget/listview")
local RightContainer = require("ui/widget/container/rightcontainer")
local NetworkMgr = require("ui/network/manager")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local util = require("util")
local VerticalGroup = require("ui/widget/verticalgroup")
local Widget = require("ui/widget/widget")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = Device.screen

local band = bit.band

local function obtainIP()
    --- @todo check for DHCP result
    local info = InfoMessage:new{text = _("Obtaining IP address…")}
    UIManager:show(info)
    UIManager:forceRePaint()
    NetworkMgr:obtainIP()
    UIManager:close(info)
end


local MinimalPaginator = Widget:extend{
    width = nil,
    height = nil,
    progress = nil,
}

function MinimalPaginator:getSize()
    return Geom:new{w = self.width, h = self.height}
end

function MinimalPaginator:paintTo(bb, x, y)
    self.dimen = self:getSize()
    self.dimen.x, self.dimen.y = x, y
    -- paint background
    bb:paintRoundedRect(x, y,
                        self.dimen.w, self.dimen.h,
                        Blitbuffer.COLOR_LIGHT_GRAY)
    -- paint percentage infill
    bb:paintRect(x, y,
                 math.ceil(self.dimen.w*self.progress), self.dimen.h,
                 Blitbuffer.COLOR_DARK_GRAY)
end

function MinimalPaginator:setProgress(progress) self.progress = progress end


local NetworkItem = InputContainer:extend{
    dimen = nil,
    height = Screen:scaleBySize(44),
    icon_size = Screen:scaleBySize(32),
    width = nil,
    info = nil,
    display_ssid = nil,
    background = Blitbuffer.COLOR_WHITE,
}

function NetworkItem:init()
    self.dimen = Geom:new{x = 0, y = 0, w = self.width, h = self.height}
    if not self.info.ssid then
        self.info.ssid = "[hidden]"
    end
    self.display_ssid = util.fixUtf8(self.info.ssid, "�")

    local wifi_icon
    if string.find(self.info.flags, "WPA") then
        wifi_icon = "wifi.secure.%d"
    else
        wifi_icon = "wifi.open.%d"
    end
    -- Based on NetworkManager's nmc_wifi_strength_bars
    -- c.f., https://github.com/NetworkManager/NetworkManager/blob/2fa8ef9fb9c7fe0cc2d9523eed6c5a3749b05175/clients/common/nm-client-utils.c#L585-L612
    if self.info.signal_quality > 80 then
        wifi_icon = string.format(wifi_icon, 100)
    elseif self.info.signal_quality > 55 then
        wifi_icon = string.format(wifi_icon, 75)
    elseif self.info.signal_quality > 30 then
        wifi_icon = string.format(wifi_icon, 50)
    elseif self.info.signal_quality > 5 then
        wifi_icon = string.format(wifi_icon, 25)
    else
        wifi_icon = string.format(wifi_icon, 0)
    end

    local horizontal_space = HorizontalSpan:new{width = Size.span.horizontal_default}
    self.content_container = OverlapGroup:new{
        dimen = self.dimen:copy(),
        LeftContainer:new{
            dimen = self.dimen:copy(),
            HorizontalGroup:new{
                horizontal_space,
                IconWidget:new{
                    icon = wifi_icon,
                    width = self.icon_size,
                    height = self.icon_size,
                },
                horizontal_space,
                TextWidget:new{
                    text = self.display_ssid,
                    face = Font:getFace("cfont"),
                },
            },
        }
    }
    self.btn_disconnect = nil
    self.btn_edit_nw = nil
    if self.info.connected then
        self.btn_disconnect = FrameContainer:new{
            bordersize = 0,
            padding = 0,
            TextWidget:new{
                text = _("disconnect"),
                face = Font:getFace("cfont"),
            }
        }

        table.insert(self.content_container, RightContainer:new{
            dimen = self.dimen:copy(),
            HorizontalGroup:new{
                self.btn_disconnect,
                horizontal_space,
            }
        })
        self.setting_ui:setConnectedItem(self)
    elseif self.info.password then
        self.btn_edit_nw = FrameContainer:new{
            bordersize = 0,
            padding = 0,
            TextWidget:new{
                text = _("edit"),
                face = Font:getFace("cfont"),
            }
        }

        table.insert(self.content_container, RightContainer:new{
            dimen = self.dimen:copy(),
            HorizontalGroup:new{
                self.btn_edit_nw,
                horizontal_space,
            }
        })
    end

    self[1] = FrameContainer:new{
        padding = 0,
        margin = 0,
        background = self.background,
        bordersize = 0,
        width = self.width,
        self.content_container,
    }

    if Device:isTouchDevice() then
        self.ges_events.TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            }
        }
    end
end

function NetworkItem:refresh()
    self:init()
    UIManager:setDirty(self.setting_ui, function() return "ui", self.dimen end)
end

function NetworkItem:connect()
    local connected_item = self.setting_ui:getConnectedItem()
    if connected_item then connected_item:disconnect() end

    local success, err_msg = NetworkMgr:authenticateNetwork(self.info)

    local text
    if success then
        obtainIP()
        self.info.connected = true
        self.setting_ui:setConnectedItem(self)
        text = _("Connected.")
    else
        text = err_msg
    end

    -- Do what it says on the tin, and only trigger the connect_callback on a *successful* connect.
    -- NOTE: This callback comes from NetworkManager, where it's named complete_callback.
    if success and self.setting_ui.connect_callback then
        self.setting_ui.connect_callback()
    end

    self:refresh()
    UIManager:show(InfoMessage:new{text = text, timeout = 3})
end

function NetworkItem:disconnect()
    local info = InfoMessage:new{text = _("Disconnecting…")}
    UIManager:show(info)
    UIManager:forceRePaint()

    NetworkMgr:disconnectNetwork(self.info)
    NetworkMgr:releaseIP()

    UIManager:close(info)
    self.info.connected = nil
    self:refresh()
    self.setting_ui:setConnectedItem(nil)
    if self.setting_ui.disconnect_callback then
        self.setting_ui.disconnect_callback()
    end
end

function NetworkItem:saveAndConnectToNetwork(password_input)
    local new_passwd = password_input:getInputText()
    -- Dont set a empty password if WPA encryption, go through if it’s an open AP
    if (new_passwd == nil or #new_passwd == 0) and string.find(self.info.flags, "WPA") then
        UIManager:show(InfoMessage:new{
            text = _("Password cannot be empty."),
        })
    else
        if new_passwd ~= self.info.password then
            self.info.password = new_passwd
            self.info.psk = nil
            NetworkMgr:saveNetwork(self.info)
        end
        self:connect()
    end

    UIManager:close(password_input)
end

function NetworkItem:onEditNetwork()
    local password_input
    password_input = InputDialog:new{
        title = self.display_ssid,
        input = self.info.password,
        input_hint = _("password (leave empty for open networks)"),
        input_type = "text",
        text_type = "password",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(password_input)
                    end,
                },
                {
                    text = _("Forget"),
                    callback = function()
                        NetworkMgr:deleteNetwork(self.info)
                        self.info.password = nil
                        -- remove edit button
                        table.remove(self.content_container, 2)
                        UIManager:close(password_input)
                        self:refresh()
                    end,
                },
                {
                    text = _("Connect"),
                    is_enter_default = true,
                    callback = function()
                        self:saveAndConnectToNetwork(password_input)
                    end,
                },
            },
        },
    }
    UIManager:show(password_input)
    password_input:onShowKeyboard()
    return true
end

function NetworkItem:onAddNetwork()
    local password_input
    password_input = InputDialog:new{
        title = self.display_ssid,
        input = "",
        input_hint = _("password (leave empty for open networks)"),
        input_type = "text",
        text_type = "password",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(password_input)
                    end,
                },
                {
                    text = _("Connect"),
                    is_enter_default = true,
                    callback = function()
                        self:saveAndConnectToNetwork(password_input)
                    end,
                },
            },
        },
    }
    UIManager:show(password_input)
    password_input:onShowKeyboard()
    return true
end

function NetworkItem:onTapSelect(arg, ges_ev)
    -- Open AP dont have specific flag so we can’t include them alongside WPA
    -- so we exclude WEP instead (more encryption to exclude? not really future proof)
    if string.find(self.info.flags, "WEP") then
        UIManager:show(InfoMessage:new{
            text = _("Networks with WEP encryption are not supported.")
        })
        return
    end
    if self.btn_disconnect then
        -- noop if touch is not on disconnect button
        if ges_ev.pos:intersectWith(self.btn_disconnect.dimen) then
            self:disconnect()
        end
    elseif self.info.password then
        if self.btn_edit_nw and ges_ev.pos:intersectWith(self.btn_edit_nw.dimen) then
            self:onEditNetwork()
        else
            self:connect()
        end
    else
        self:onAddNetwork()
    end
    return true
end


local NetworkSetting = InputContainer:extend{
    width = nil,
    height = nil,
    -- sample network_list entry: {
    --   bssid = "any",
    --   ssid = "foo",
    --   signal_level = -58,
    --   signal_quality = 84,
    --   frequency = 5660,
    --   flags = "[WPA2-PSK-CCMP][ESS]",
    -- }
    network_list = nil,
    connect_callback = nil,
    disconnect_callback = nil,
}

function NetworkSetting:init()
    self.width = self.width or Screen:getWidth() - Screen:scaleBySize(50)
    self.width = math.min(self.width, Screen:scaleBySize(600))

    local gray_bg = Blitbuffer.COLOR_GRAY_E
    local items = {}
    table.sort(self.network_list,
               function(l, r) return l.signal_quality > r.signal_quality end)
    for idx, network in ipairs(self.network_list) do
        local bg
        if band(idx, 1) == 0 then
            bg = gray_bg
        else
            bg = Blitbuffer.COLOR_WHITE
        end
        table.insert(items, NetworkItem:new{
            width = self.width,
            info = network,
            background = bg,
            setting_ui = self,
        })
    end

    self.status_text = TextWidget:new{
        text = "",
        face = Font:getFace("ffont"),
    }
    self.page_text = TextWidget:new{
        text = "",
        face = Font:getFace("ffont"),
    }

    self.pagination = MinimalPaginator:new{
        width = self.width,
        height = Screen:scaleBySize(8),
        percentage = 0,
        progress = 0,
    }

    self.height = self.height or math.min(Screen:getHeight()*3/4,
                                          Screen:scaleBySize(800))
    self.popup = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        padding = 0,
        bordersize = Size.border.window,
        VerticalGroup:new{
            align = "left",
            self.pagination,
            ListView:new{
                padding = 0,
                items = items,
                width = self.width,
                height = self.height-self.pagination:getSize().h,
                page_update_cb = function(curr_page, total_pages)
                    self.pagination:setProgress(curr_page/total_pages)
                    -- self.page_text:setText(curr_page .. "/" .. total_pages)
                    UIManager:setDirty(self, function()
                        return "ui", self.popup.dimen
                    end)
                end
            },
        },
    }

    self[1] = CenterContainer:new{
        dimen = {w = Screen:getWidth(), h = Screen:getHeight()},
        self.popup,
    }

    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                }
            }
        }
    end

    -- If the backend is already authenticated,
    -- and NetworkMgr:reconnectOrShowNetworkMenu somehow missed it,
    -- expedite the process.
    -- Yes, this is a very old codepath that's hardly ever exercised anymore...
    if not self.connect_callback then
        return
    end

    UIManager:nextTick(function()
        local connected_item = self:getConnectedItem()
        if connected_item ~= nil then
            obtainIP()
            if G_reader_settings:nilOrTrue("auto_dismiss_wifi_scan") then
                UIManager:close(self)
            end
            UIManager:show(InfoMessage:new{
                text = T(_("Connected to network %1"), BD.wrap(connected_item.display_ssid)),
                timeout = 3,
            })
            self.connect_callback()
        end
    end)
end

function NetworkSetting:setConnectedItem(item)
    self.connected_item = item
end

function NetworkSetting:getConnectedItem()
    return self.connected_item
end

function NetworkSetting:onTapClose(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.popup.dimen) then
        UIManager:close(self)
        return true
    end
end

function NetworkSetting:onCloseWidget()
    -- If we don't have a connectivity check ticking, assume we're done with this connection attempt *now*
    if not NetworkMgr.pending_connectivity_check then
        NetworkMgr.pending_connection = false
    end
    UIManager:setDirty(nil, "ui", self.popup.dimen)
end

return NetworkSetting
