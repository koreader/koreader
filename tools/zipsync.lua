#!./luajit

require "setupkoenv"

local ffiUtil = require("ffi/util")
local util = require("util")
local zipsync = require("ffi/zipsync")


local function zipsync_sync(state_dir, zipsync_url, syncdir)
    local updater = zipsync.Updater:new(state_dir)
    updater:fetch_manifest(zipsync_url)
    local total_files = #updater.manifest.files
    local last_update = 0
    local delay = false --190000
    local update_frequency = 0.2
    local stats = updater:prepare_update(syncdir, function(count)
        local new_update = ffiUtil.getTimestamp()
        if new_update - last_update < update_frequency then
            return true
        end
        last_update = new_update
        io.stderr:write(string.format("\ranalyzing: %4u/%4u", count, total_files))
        if delay then
            ffiUtil.usleep(delay)
        end
        return true
    end)
    io.stderr:write(string.format("\r%99s\r", ""))
    assert(total_files == stats.total_files)
    if stats.missing_files == 0 then
        print('nothing to update!')
        return
    end
    print(string.format("missing : %u/%u files", stats.missing_files, total_files))
    print(string.format("reusing : %7s (%10u)", util.getFriendlySize(stats.reused_size), stats.reused_size))
    print(string.format("fetching: %7s (%10u)", util.getFriendlySize(stats.download_size), stats.download_size))
    io.stdout:flush()
    local pbar_indicators = {" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"}
    local pbar_size = 16
    local pbar_chunk = (stats.download_size + pbar_size - 1) / pbar_size
    local prev_path = ""
    local old_progress
    last_update = 0
    local ok, err = pcall(updater.download_update, updater, function(size, count, path)
        local new_update = ffiUtil.getTimestamp()
        if new_update - last_update < update_frequency then
            return true
        end
        last_update = new_update
        local padding = math.max(#prev_path, #path)
        local progress = math.floor(size / pbar_chunk)
        local pbar = pbar_indicators[#pbar_indicators]:rep(progress)..pbar_indicators[1 + math.floor(size % pbar_chunk * #pbar_indicators / pbar_chunk)]..(" "):rep(pbar_size - progress - 1)
        local new_progress = string.format("\rdownloading: %8s %4u/%4u %s %-"..padding.."s", util.getFriendlySize(size), count, stats.missing_files, pbar, path)
        if new_progress ~= old_progress then
            old_progress = new_progress
            io.stderr:write(new_progress)
        end
        prev_path = path
        if delay then
            ffiUtil.usleep(delay)
        end
        return true
    end)
    io.stderr:write(string.format("\r%99s\r", ""))
    if not ok then
        io.stderr:write(string.format("ERROR: %s", err))
        return 1
    end
end

local function main()
    local cmd = table.remove(arg, 1)
    local ret
    if cmd == "sync" then
        assert(2 <= #arg and #arg <= 3)
        ret = zipsync_sync(unpack(arg))
    elseif not cmd then
        error("missing command!")
    else
        error("invalid command: "..cmd)
    end
    os.exit(ret)
end

main()
