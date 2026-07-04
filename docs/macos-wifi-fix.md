# macOS WiFi Fix

## Problem

The packaged KOReader macOS `.app` bundle sets `KO_MULTIUSER=1`, which instantiates the
`Desktop` SDL device class. Unlike the `Emulator` device (used for development builds
run via `./luajit reader.lua`, which has `hasWifiToggle = yes` and a fake WiFi toggle),
the `Desktop` class inherited `hasWifiToggle = no` from the base SDL `Device`.

This caused the following symptoms in the packaged build:

| Symptom | Root cause |
|---------|------------|
| No "Wi-Fi connection" entry in Settings | `manager.lua:1091` guards the menu on `hasWifiToggle()` |
| `isWifiOn()` / `isConnected()` / `isOnline()` always return `true` | `manager.lua:183-190`, `643` — early return when `!hasWifiToggle` |
| Network-dependent features silently fail when offline | The always-report-connected logic bypasses all real connectivity checks |
| Network info dialog shows no gateway | `generic/device.lua:828` reads `/proc/net/route` — Linux-only |

In the emulator, `Emulator:initNetworkManager` provides a fake toggle backed by the
`emulator_fake_wifi_connected` setting, making WiFi appear functional.

## Solution

Four files were modified:

### 1. `frontend/device/sdl/device.lua`

**Desktop class** (`hasWifiToggle`, `hasSeamlessWifiToggle`):

```lua
local Desktop = Device:extend{
    model = SDL.getPlatform(),
    isDesktop = yes,
    canRestart = notOSX,
    hasExitOptions = notOSX,
    hasWifiToggle = yes,
    hasSeamlessWifiToggle = yes,
}
```

- `hasWifiToggle = yes` — enables the "Wi-Fi connection" menu entry and enables the
  `beforeWifiAction` / `afterWifiAction` framework.
- `hasSeamlessWifiToggle = yes` — indicates that `networksetup` returns near-instantly,
  so no "Turning on Wi-Fi…" spinner is needed.

**`Desktop:initNetworkManager`** — overrides the base SDL `Device:initNetworkManager`
for the `Desktop` class. Key design:

| Aspect | Implementation |
|--------|----------------|
| WiFi interface detection | Runs `networksetup -listallhardwareports` once at init; falls back to the first `enX` interface from `getifaddrs()`, then to `"en0"` |
| `isWifiOn()` (macOS) | Reads `networksetup -getairportpower <iface>` |
| `isWifiOn()` (other desktop) | Checks `getifaddrs()` for any non-loopback UP interface with an IP |
| `isConnected()` (all desktop) | Uses `hasDefaultRoute()` — the socket `setpeername` API works on macOS and Linux |
| `turnOnWifi()` (macOS) | Calls `networksetup -setairportpower <iface> on`; schedules `complete_callback` after 1s for radio settling |
| `turnOffWifi()` (macOS) | Calls `networksetup -setairportpower <iface> off`; invokes `complete_callback` immediately |
| `getNetworkInterfaceName()` (macOS) | Returns the cached interface name |

The method also sets `wifi_enable_action` to `"turn_on"` on first launch so that
`beforeWifiAction` automatically attempts to turn on WiFi without prompting.

**Base `Device:initNetworkManager`** (unchanged for AppImage/Flatpak, which still have
`hasWifiToggle = no`). The unused ping-via-gateway path (lines 448-454) is left in
place for the base SDL class.

**`Emulator:initNetworkManager`** — completely unchanged.

### 2. `frontend/device/generic/device.lua`

**`getDefaultRoute()`** — added a macOS branch that parses `route -n get default`:

```lua
function Device:getDefaultRoute(interface)
    if jit.os == "OSX" then
        local handle = io.popen("route -n get default 2>/dev/null")
        if not handle then return end
        local gateway
        for line in handle:lines() do
            gateway = line:match("gateway%s*:%s*(%S+)")
            if gateway then break end
        end
        handle:close()
        return gateway
    end
    -- existing Linux /proc/net/route implementation follows
```

This enables the "Network info" dialog to show the gateway. The Linux path
(`/proc/net/route`) is unchanged.

### 3. `base/ffi/netinfo.lua`

**macOS `_process_ifaddr`** — enhanced with wireless detection and SSID retrieval:

- All interfaces named `en*` are heuristically marked as `wireless = true`
- SSID is attempted via the Apple `airport` private binary
  (`/System/Library/PrivateFrameworks/Apple80211.framework/.../airport -I`)
- SSID retrieval is best-effort; it silently returns nil if the binary is missing or
  if the `airport` command is unavailable (as on newer macOS versions where
  location permission may be required)

This only affects the "Network info" dialog's SSID display.

### 4. (This file) `docs/macos-wifi-fix.md`

## Changed files

| File | Lines changed | Type |
|------|---------------|------|
| `frontend/device/sdl/device.lua` | 140-141, 458-560 | Bug fix |
| `frontend/device/generic/device.lua` | 828-838 | Enhancement |
| `base/ffi/netinfo.lua` | 190-216 | Enhancement |
| `docs/macos-wifi-fix.md` | new file | Documentation |

## Verification

| Test | Expected result |
|------|----------------|
| Build & launch macOS `.app` | App launches with no errors; WiFi toggle visible in Settings → Network |
| Toggle WiFi on via menu | `networksetup -setairportpower <iface> on` runs; menu checkbox shows checked |
| Toggle WiFi off via menu | `networksetup -setairportpower <iface> off` runs; menu checkbox shows unchecked |
| WiFi on and connected | Sync, Wikipedia lookup, news downloader work |
| WiFi off | Network-dependent features show "Do you want to turn on Wi-Fi?" prompt (or auto-connect if `wifi_enable_action = turn_on`) |
| Network info dialog (WiFi on) | Shows interface name, MAC, IP, gateway, (maybe SSID) |
| Network info dialog (WiFi off) | Shows limited info (no IP/gateway) |
| Linux desktop with `KO_MULTIUSER=1` | Falls back to `hasActiveInterface()` via `getifaddrs`; no regression |
| Linux AppImage | Unchanged — still uses `hasWifiToggle = no` (always-connected path) |
| Emulator (`./luajit reader.lua`) | Unchanged — still uses `Emulator:initNetworkManager` with fake toggle |
| Kobo / Kindle / PocketBook | Unchanged — each has its own `initNetworkManager` override |

## Caveats

- **WiFi scanning** — `getNetworkList()` remains the default NOP stub on Desktop.
  wpa_supplicant is not available on macOS. The user is expected to use the macOS
  menu bar for network selection.
- **SSID detection** — Relies on the private `airport` binary, whose path may change
  between macOS versions. A future improvement could use CoreWLAN via FFI.
- **Linux Desktop** — Only `isConnected()` via `hasDefaultRoute()` is implemented.
  There is no `turnOnWifi` / `turnOffWifi` for Linux Desktop, as network management
  is handled by the system. The `hasWifiToggle = yes` flag makes the menu visible
  and allows the `beforeWifiAction` framework to gate on connectivity.
