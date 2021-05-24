local Generic = require("device/generic/device") -- <= look at this file!
local logger = require("logger")
local ffi = require("ffi")
local C = ffi.C
local inkview = ffi.load("inkview")
local band = require("bit").band
local util = require("util")

require("ffi/posix_h")
require("ffi/linux_input_h")
require("ffi/inkview_h")

-- FIXME: Signal ffi/input.lua (brought in by device/input later on) that we want to use poll mode backend.
-- Remove this once backend becomes poll-only.
_G.POCKETBOOK_FFI = true

local function yes() return true end
local function no() return false end

local ext_path = "/mnt/ext1/system/config/extensions.cfg"
local app_name = "koreader.app"

local PocketBook = Generic:new{
    model = "PocketBook",
    isPocketBook = yes,
    hasOTAUpdates = yes,
    hasWifiToggle = yes,
    isTouchDevice = yes,
    hasKeys = yes,
    hasFrontlight = yes,
    hasSystemFonts = yes,
    canSuspend = no,
    canReboot = yes,
    canPowerOff = yes,
    needsScreenRefreshAfterResume = no,
    home_dir = "/mnt/ext1",

    -- all devices that have warmth lights use inkview api
    hasNaturalLightApi = yes,

    -- NOTE: Apparently, HW inversion is a pipedream on PB (#6669), ... well, on sunxi chipsets anyway.
    -- For which we now probe in fbinfoOverride() and tweak the flag to "no".
    -- NTX chipsets *should* work (PB631), but in case it doesn't on your device, set this to "no" in here.
    canHWInvert = yes,

    -- If we can access the necessary devices, input events can be handled directly.
    -- This improves latency (~40ms), as well as power usage - we can spend more time asleep,
    -- instead of busy looping at 50Hz the way inkview insists on doing.
    -- In case this method fails (no root), we fallback to classic inkview api.
    raw_input = nil, --[[{
        -- value or function to adjust touch matrix orientiation.
        touch_rotation = -3+4,
        -- Works same as input.event_map, but for raw input EV_KEY translation
        keymap = { [scan] = event },
    }]]
    -- Runtime state: whether raw input is actually used
    --- @fixme: Never actually set anywhere?
    is_using_raw_input = nil,

    -- Will be set appropriately at init
    isB288SoC = no,

    -- Private per-model kludges
    _fb_init = function() end,
    _model_init = function() end,
}

-- Helper to try load externally signalled book whenever we're brought to foreground
local function tryOpenBook()
    local path = os.getenv("KO_PATH_OPEN_BOOK")
    if not path then return end
    local fi = io.open(path, "r")
    if not fi then return end
    local fn = fi:read("*line")
    fi:close()
    os.remove(path)
    if fn and util.pathExists(fn) then
        require("apps/reader/readerui"):showReader(fn)
    end
end


-- A couple helper functions to compute/check aligned values...
-- c.f., <linux/kernel.h>
local function ALIGN(x, a)
    -- (x + (a-1)) & ~(a-1)
    local mask = a - 1
    return bit.band(x + mask, bit.bnot(mask))
end

local function IS_ALIGNED(x, a)
    -- (x & (a-1)) == 0
    if bit.band(x, a - 1) == 0 then
        return true
    else
        return false
    end
end

function PocketBook:init()
    local raw_input = self.raw_input
    local touch_rotation = raw_input and raw_input.touch_rotation or 0

    self.screen = require("ffi/framebuffer_mxcfb"):new {
        device = self,
        debug = logger.dbg,
        wf_level = G_reader_settings:readSetting("wf_level") or 0,
        fbinfoOverride = function(fb, finfo, vinfo)
            -- Device model caps *can* set both to indicate that either will work to get correct orientation.
            -- But for FB backend, the flags are mutually exclusive, so we nuke one of em later.
            fb.is_always_portrait = self.isAlwaysPortrait()
            fb.forced_rotation = self.usingForcedRotation()
            -- Tweak combination of alwaysPortrait/hwRot/hwInvert flags depending on probed HW and wf settings.
            if fb:isB288() then
                self.isB288SoC = yes

                -- Allow bypassing the bans for debugging purposes...
                if G_reader_settings:nilOrFalse("pb_ignore_b288_quirks") then
                    logger.dbg("mxcfb: Disabling hwinvert on B288 chipset")
                    self.canHWInvert = no
                    -- GL16 glitches with hwrot. And apparently with more stuff on newer FW (#7663)
                    logger.dbg("mxcfb: Disabling hwrot on B288 chipset")
                    fb.forced_rotation = nil
                end
            end
            -- If hwrot is still on, nuke swrot
            if fb.forced_rotation then
                fb.is_always_portrait = false
            end

            -- Legacy devices return incomplete/broken data, fix it without breaking saner devices.
            -- c.f., https://github.com/koreader/koreader-base/blob/50a965c28fd5ea2100257aa9ce2e62c9c301155c/ffi/framebuffer_linux.lua#L119-L189
            if string.byte(ffi.string(finfo.id, 16), 1, 1) == 0 then
                local xres_virtual = vinfo.xres_virtual
                if not IS_ALIGNED(vinfo.xres_virtual, 32) then
                    vinfo.xres_virtual = ALIGN(vinfo.xres, 32)
                end
                local yres_virtual = vinfo.yres_virtual
                if not IS_ALIGNED(vinfo.yres_virtual, 128) then
                    vinfo.yres_virtual = ALIGN(vinfo.yres, 128)
                end
                local line_length = finfo.line_length
                finfo.line_length = vinfo.xres_virtual * bit.rshift(vinfo.bits_per_pixel, 3)

                local fb_size = finfo.line_length * vinfo.yres_virtual
                if fb_size > finfo.smem_len then
                    if not IS_ALIGNED(yres_virtual, 32) then
                        vinfo.yres_virtual = ALIGN(vinfo.yres, 32)
                    else
                        vinfo.yres_virtual = yres_virtual
                    end
                    fb_size = finfo.line_length * vinfo.yres_virtual

                    if fb_size > finfo.smem_len then
                        --fb_size = finfo.smem_len
                        finfo.line_length = line_length
                        vinfo.xres_virtual = xres_virtual
                        vinfo.yres_virtual = yres_virtual

                        vinfo.xres_virtual = bit.lshift(finfo.line_length, 3) / vinfo.bits_per_pixel
                    end
                end
            end

            return self._fb_init(fb, finfo, vinfo)
        end,
        -- raw touch input orientiation is different from the screen
        getTouchRotation = function(fb)
            if type(touch_rotation) == "function" then
                return touch_rotation(self, fb:getRotationMode())
            end
            return (4 + fb:getRotationMode() + touch_rotation) % 4
        end,
    }

    -- Whenever we lose focus, but also get suspended for real (we can't reliably tell atm),
    -- plugins need to be notified to stop doing foreground stuff, and vice versa. To this end,
    -- we maintain pseudo suspended state just to keep plugins happy, even though it's not
    -- related real to suspend states.
    local quasiSuspended

    self.input = require("device/input"):new{
        device = self,
        raw_input = raw_input,
        event_map = setmetatable({
            [C.KEY_MENU] = "Menu",
            [C.KEY_PREV] = "LPgBack",
            [C.KEY_NEXT] = "LPgFwd",
            [C.KEY_UP] = "Up",
            [C.KEY_DOWN] = "Down",
            [C.KEY_LEFT] = "Left",
            [C.KEY_RIGHT] = "Right",
            [C.KEY_OK] = "Press",
        }, {__index=raw_input and raw_input.keymap or {}}),
        handleMiscEv = function(this, ev)
            local ui = require("ui/uimanager")
            if ev.code == C.EVT_HIDE or ev.code == C.EVT_BACKGROUND then
                ui:flushSettings()
                if not quasiSuspended then
                    quasiSuspended = true
                    return "Suspend"
                end
            elseif ev.code == C.EVT_FOREGROUND or ev.code == C.EVT_SHOW then
                tryOpenBook()
                ui:setDirty('all', 'ui')
                if quasiSuspended then
                    quasiSuspended = false
                    return "Resume"
                end
            end
        end,
    }

    -- in contrast to kobo/kindle, pocketbook-devices do not use linux/input
    -- events directly. To be able to use input.lua nevertheless, we make
    -- inkview-events look like linux/input events or handle them directly
    -- here.
    -- Unhandled events will leave Input:waitEvent() as "GenericInput"
    self.input:registerEventAdjustHook(function(_input, ev)
        if ev.type == C.EVT_KEYDOWN or ev.type == C.EVT_KEYUP then
            ev.value = ev.type == C.EVT_KEYDOWN and 1 or 0
            ev.type = C.EV_KEY
        end

        -- handle C.EVT_BACKGROUND and C.EVT_FOREGROUND as MiscEvent as this makes
        -- it easy to return a string directly which can be used in
        -- uimanager.lua as event_handler index.
        if ev.type == C.EVT_BACKGROUND or ev.type == C.EVT_FOREGROUND
        or ev.type == C.EVT_SHOW or ev.type == C.EVT_HIDE then
            ev.code = ev.type
            ev.type = C.EV_MSC -- handle as MiscEvent, see above
        end

        -- auto shutdown event from inkview framework, gracefully close
        -- everything and let the framework shutdown the device
        if ev.type == C.EVT_EXIT then
            require("ui/uimanager"):broadcastEvent(
                require("ui/event"):new("Close"))
        end
    end)

    self._model_init()
    if (not self.input.raw_input) or (not pcall(self.input.open, self.input, self.raw_input)) then
        inkview.OpenScreen()
        -- Raw mode open failed (no permissions?), so we'll run the usual way.
        -- Disable touch coordinate translation as inkview will do that.
        self.input.raw_input = nil
        self.input:open()
        touch_rotation = 0
    else
        self.canSuspend = yes
    end
    self.powerd = require("device/pocketbook/powerd"):new{device = self}
    self:setAutoStandby(true)
    Generic.init(self)
end

function PocketBook:notifyBookState(title, document)
    local fn = document and document.file or nil
    logger.dbg("Notify book state", title or "[nil]", fn or "[nil]")
    os.remove("/tmp/.current")
    if fn then
        local fo = io.open("/tmp/.current", "w+")
        fo:write(fn)
        fo:close()
    end
    inkview.SetSubtaskInfo(inkview.GetCurrentTask(), 0, title and (title .. " - koreader") or "koreader", fn)
end

function PocketBook:setDateTime(year, month, day, hour, min, sec)
    if hour == nil or min == nil then return true end
    -- If the device is rooted, we might actually have a fighting chance to change os clock.
    local su = "/mnt/secure/su"
    su = util.pathExists(su) and (su .. " ") or ""
    local command
    if year and month and day then
        command = string.format(su .. "/bin/date -s '%d-%d-%d %d:%d:%d'", year, month, day, hour, min, sec)
    else
        command = string.format(su .. "/bin/date -s '%d:%d'",hour, min)
    end
    if os.execute(command) == 0 then
        os.execute(su .. '/sbin/hwclock -u -w')
        return true
    else
        return false
    end
end

-- Predicate, so no self
function PocketBook.canAssociateFileExtensions()
    local f = io.open(ext_path, "r")
    if not f then return true end
    local l = f:read("*line")
    f:close()
    if l and not l:match("^#koreader") then
        return false
    end
    return true
end

function PocketBook:associateFileExtensions(assoc)
    -- First load the system-wide table, from which we'll snoop file types and icons
    local info = {}
    for l in io.lines("/ebrmain/config/extensions.cfg") do
        local m = { l:match("^([^:]*):([^:]*):([^:]*):([^:]*):(.*)") }
        info[m[1]] = m
    end
    local res = {"#koreader"}
    for k,v in pairs(assoc) do
        local t = info[k]
        if t then
            -- A system entry exists, so just change app, and reuse the rest
            t[4] = app_name .. "," .. t[4]
        else
            -- Doesn't exist, so hallucinate up something
            -- TBD: We have document opener in 'v', maybe consult mime in there?
            local bn = k:match("%a+"):upper()
            t = { k, '@' .. bn .. '_file', "1", app_name, "ICON_" .. bn }
        end
        table.insert(res, table.concat(t, ":"))
    end
    local out = io.open(ext_path, "w+")
    out:write(table.concat(res, "\n"))
    out:close()
end

function PocketBook:setAutoStandby(isAllowed)
    inkview.iv_sleepmode(isAllowed and 1 or 0)
end

function PocketBook:powerOff()
    inkview.PowerOff()
end

function PocketBook:suspend()
    inkview.SendGlobalRequest(C.REQ_KEYLOCK)
end

function PocketBook:reboot()
    inkview.iv_ipc_request(C.MSG_REBOOT, 1, nil, 0, 0)
end

function PocketBook:initNetworkManager(NetworkMgr)
    function NetworkMgr:turnOnWifi(complete_callback)
        if inkview.NetConnect(nil) ~= C.NET_OK then
            logger.info('NetConnect failed')
        end
        if complete_callback then
            complete_callback()
        end
    end

    function NetworkMgr:turnOffWifi(complete_callback)
        inkview.NetDisconnect()
        if complete_callback then
            complete_callback()
        end
    end

    function NetworkMgr:isWifiOn()
        return band(inkview.QueryNetwork(), C.CONNECTED) ~= 0
    end
end

function PocketBook:getSoftwareVersion()
    return ffi.string(inkview.GetSoftwareVersion())
end

function PocketBook:getDeviceModel()
    return ffi.string(inkview.GetDeviceModel())
end

function PocketBook:getDefaultCoverPath()
    return "/mnt/ext1/system/logo/offlogo/cover.bmp"
end

-- Pocketbook HW rotation modes start from landsape, CCW
local function landscape_ccw() return {
    1, 0, 3, 2,         -- PORTRAIT, LANDSCAPE, PORTRAIT_180, LANDSCAPE_180
    every_paint = true, -- inkview will try to steal the rot mode frequently
    restore = false,    -- no need, because everything using inkview forces 3 on focus
    default = nil,      -- usually 3
} end

-- PocketBook Mini (515)
local PocketBook515 = PocketBook:new{
    model = "PB515",
    display_dpi = 200,
    isTouchDevice = no,
    hasFrontlight = no,
    hasDPad = yes,
    hasFewKeys = yes,
}

-- PocketBook 606 (606)
local PocketBook606 = PocketBook:new{
    model = "PB606",
    display_dpi = 212,
    isTouchDevice = no,
    hasFrontlight = no,
    hasDPad = yes,
    hasFewKeys = yes,
}

-- PocketBook Basic (611)
local PocketBook611 = PocketBook:new{
    model = "PB611",
    display_dpi = 167,
    isTouchDevice = no,
    hasFrontlight = no,
    hasDPad = yes,
    hasFewKeys = yes,
}

-- PocketBook Basic (613)
local PocketBook613 = PocketBook:new{
    model = "PB613B",
    display_dpi = 167,
    isTouchDevice = no,
    hasWifiToggle = no,
    hasFrontlight = no,
    hasDPad = yes,
    hasFewKeys = yes,
}

-- PocketBook Basic 2 / Basic 3 (614/614W)
local PocketBook614W = PocketBook:new{
    model = "PB614W",
    display_dpi = 167,
    isTouchDevice = no,
    hasFrontlight = no,
    hasDPad = yes,
    hasFewKeys = yes,
}

-- PocketBook Basic Lux / 615 Plus (615/615W)
local PocketBook615 = PocketBook:new{
    model = "PBBLux",
    display_dpi = 212,
    isTouchDevice = no,
    hasDPad = yes,
    hasFewKeys = yes,
}

-- PocketBook Basic Lux 2 (616/616W)
local PocketBook616 = PocketBook:new{
    model = "PBBLux2",
    display_dpi = 212,
    isTouchDevice = no,
    hasDPad = yes,
    hasFewKeys = yes,
}

-- PocketBook Touch (622)
local PocketBook622 = PocketBook:new{
    model = "PBTouch",
    display_dpi = 167,
    hasFrontlight = no,
}

-- PocketBook Touch Lux (623)
local PocketBook623 = PocketBook:new{
    model = "PBTouchLux",
    display_dpi = 212,
}

-- PocketBook Basic Touch (624)
local PocketBook624 = PocketBook:new{
    model = "PBBasicTouch",
    display_dpi = 167,
    hasFrontlight = no,
}

-- PocketBook Basic Touch 2 (625)
local PocketBook625 = PocketBook:new{
    model = "PBBasicTouch2",
    display_dpi = 167,
    hasFrontlight = no,
}

-- PocketBook Touch Lux 2 / Touch Lux 3 (626)
local PocketBook626 = PocketBook:new{
    model = "PBLux3",
    display_dpi = 212,
}

-- PocketBook Touch Lux 4 (627)
local PocketBook627 = PocketBook:new{
    model = "PBLux4",
    display_dpi = 212,
    isAlwaysPortrait = yes,
}

-- PocketBook Touch Lux 5 (628)
local PocketBook628 = PocketBook:new{
    model = "PBTouchLux5",
    display_dpi = 212,
    isAlwaysPortrait = yes,
    usingForcedRotation = landscape_ccw,
    hasNaturalLight = yes,
}

-- PocketBook Sense / Sense 2 (630)
local PocketBook630 = PocketBook:new{
    model = "PBSense",
    display_dpi = 212,
}

-- PocketBook Touch HD / Touch HD 2 (631)
local PocketBook631 = PocketBook:new{
    model = "PBTouchHD",
    display_dpi = 300,
    -- see https://github.com/koreader/koreader/pull/6531#issuecomment-676629182
    hasNaturalLight = function() return inkview.GetFrontlightColor() >= 0 end,
}

-- PocketBook Touch HD Plus / Touch HD 3 (632)
local PocketBook632 = PocketBook:new{
    model = "PBTouchHDPlus",
    display_dpi = 300,
    isAlwaysPortrait = yes,
    usingForcedRotation = landscape_ccw,
    hasNaturalLight = yes,
}

-- PocketBook Color (633)
local PocketBook633 = PocketBook:new{
    model = "PBColor",
    display_dpi = 300,
    hasColorScreen = yes,
    canUseCBB = no, -- 24bpp
    isAlwaysPortrait = yes,
    usingForcedRotation = landscape_ccw,
}

-- PocketBook Aqua (640)
local PocketBook640 = PocketBook:new{
    model = "PBAqua",
    display_dpi = 167,
}

-- PocketBook Aqua 2 (641)
local PocketBook641 = PocketBook:new{
    model = "PBAqua2",
    display_dpi = 212,
}

-- PocketBook Ultra (650)
local PocketBook650 = PocketBook:new{
    model = "PBUltra",
    display_dpi = 212,
}

-- PocketBook InkPad 3 (740)
local PocketBook740 = PocketBook:new{
    model = "PBInkPad3",
    display_dpi = 300,
    isAlwaysPortrait = yes,
    usingForcedRotation = landscape_ccw,
    hasNaturalLight = yes,
}

-- PocketBook InkPad 3 Pro (740_2)
local PocketBook740_2 = PocketBook:new{
    model = "PBInkPad3Pro",
    display_dpi = 300,
    isAlwaysPortrait = yes,
    usingForcedRotation = landscape_ccw,
    hasNaturalLight = yes,
    raw_input = {
        touch_rotation = -1,
        keymap = {
            [115] = "Menu",
            [109] = "LPgFwd",
            [104] = "LPgBack",
        }
    }
}

-- PocketBook InkPad Color (741)
local PocketBook741 = PocketBook:new{
    model = "PBInkPadColor",
    display_dpi = 300,
    hasColorScreen = yes,
    canUseCBB = no, -- 24bpp
    isAlwaysPortrait = yes,
    usingForcedRotation = landscape_ccw,
}

-- PocketBook Color Lux (801)
local PocketBookColorLux = PocketBook:new{
    model = "PBColorLux",
    display_dpi = 125,
    hasColorScreen = yes,
    canUseCBB = no, -- 24bpp
}
function PocketBookColorLux:_model_init()
    self.screen.blitbuffer_rotation_mode = self.screen.ORIENTATION_PORTRAIT
    self.screen.native_rotation_mode = self.screen.ORIENTATION_PORTRAIT
end
function PocketBookColorLux._fb_init(fb, finfo, vinfo)
    -- Pocketbook Color Lux reports bits_per_pixel = 8, but actually uses an RGB24 framebuffer
    vinfo.bits_per_pixel = 24
    vinfo.xres = vinfo.xres / 3
    fb.refresh_pixel_size = 3
end

-- PocketBook InkPad / InkPad 2 (840)
local PocketBook840 = PocketBook:new{
    model = "PBInkPad",
    display_dpi = 250,
}

-- PocketBook InkPad X (1040)
local PocketBook1040 = PocketBook:new{
    model = "PB1040",
    display_dpi = 227,
    isAlwaysPortrait = yes,
    usingForcedRotation = landscape_ccw,
    hasNaturalLight = yes,
}

logger.info('SoftwareVersion: ', PocketBook:getSoftwareVersion())

local codename = PocketBook:getDeviceModel()

if codename == "PocketBook 515" then
    return PocketBook515
elseif codename == "PB606" or codename == "PocketBook 606" then
    return PocketBook606
elseif codename == "PocketBook 611" then
    return PocketBook611
elseif codename == "PocketBook 613" then
    return PocketBook613
elseif codename == "PocketBook 614" or codename == "PocketBook 614W" then
    return PocketBook614W
elseif codename == "PB615" or codename == "PB615W" or
    codename == "PocketBook 615" or codename == "PocketBook 615W" then
    return PocketBook615
elseif codename == "PB616" or codename == "PB616W" or
    codename == "PocketBook 616" or codename == "PocketBook 616W" then
    return PocketBook616
elseif codename == "PocketBook 622" then
    return PocketBook622
elseif codename == "PocketBook 623" then
    return PocketBook623
elseif codename == "PocketBook 624" then
    return PocketBook624
elseif codename == "PB625" then
    return PocketBook625
elseif codename == "PB626" or codename == "PB626(2)-TL3" or
    codename == "PocketBook 626" then
    return PocketBook626
elseif codename == "PB627" then
    return PocketBook627
elseif codename == "PB628" then
    return PocketBook628
elseif codename == "PocketBook 630" then
    return PocketBook630
elseif codename == "PB631" or codename == "PocketBook 631" then
    return PocketBook631
elseif codename == "PB632" then
    return PocketBook632
elseif codename == "PB633" then
    return PocketBook633
elseif codename == "PB640" or codename == "PocketBook 640" then
    return PocketBook640
elseif codename == "PB641" then
    return PocketBook641
elseif codename == "PB650" or codename == "PocketBook 650" then
    return PocketBook650
elseif codename == "PB740" then
    return PocketBook740
elseif codename == "PB740-2" then
    return PocketBook740_2
elseif codename == "PB741" then
    return PocketBook741
elseif codename == "PocketBook 840" then
    return PocketBook840
elseif codename == "PB1040" then
    return PocketBook1040
elseif codename == "PocketBook Color Lux" then
    return PocketBookColorLux
else
    error("unrecognized PocketBook model " .. codename)
end
