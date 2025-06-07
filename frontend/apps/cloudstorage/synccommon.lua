local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local DocSettings = require("docsettings")
local ffiutil = require("ffi/util")
local _ = require("gettext")

local SyncCommon = {}

-- Progress callback throttling state
local last_progress_time = 0
local last_progress_count = 0
local PROGRESS_THROTTLE_TIME = 1.0 -- seconds
local PROGRESS_THROTTLE_COUNT = 50 -- files

-- Helper function to split a string by separator
local function split_path(str, sep)
    if sep == nil then
        sep = "/"
    end
    local t = {}
    if str == nil then return t end
    for s in string.gmatch(str, "([^" .. sep .. "]+)") do
        table.insert(t, s)
    end
    return t
end

-- Throttled progress callback helper
function SyncCommon.call_progress_callback(callback, kind, current, total, rel_path)
    if not callback then return end
    
    local now = os.time()
    local should_emit = false
    
    -- Emit if enough time has passed or enough files processed
    if now - last_progress_time >= PROGRESS_THROTTLE_TIME or 
       current - last_progress_count >= PROGRESS_THROTTLE_COUNT or
       current == 1 or current == total then
        should_emit = true
        last_progress_time = now
        last_progress_count = current
    end
    
    if should_emit then
        callback(kind, current, total, rel_path)
    end
end

-- Get local files recursively for synchronization
function SyncCommon.get_local_files_recursive(base_path, current_rel_path)
    local files = {}
    local current_path = base_path
    if current_rel_path and current_rel_path ~= "" then
        current_path = base_path .. "/" .. current_rel_path
    end

    local ok, iter, dir_obj = pcall(lfs.dir, current_path)
    if not ok then
        logger.err("SyncCommon:get_local_files_recursive: Cannot access directory", current_path)
        return files
    end

    for item in iter, dir_obj do
        if item ~= "." and item ~= ".." then
            local item_path = current_path .. "/" .. item
            local rel_path = current_rel_path and current_rel_path ~= "" and (current_rel_path .. "/" .. item) or item
            local attr = lfs.attributes(item_path)
            
            if attr then
                if attr.mode == "file" and item ~= ".DS_Store" then
                    files[rel_path] = {
                        size = attr.size,
                        path = item_path,
                        type = "file"
                    }
                elseif attr.mode == "directory" and not item:match("%.sdr$") and not item:match("^%.") then
                    local sub_files = SyncCommon.get_local_files_recursive(base_path, rel_path)
                    for k, v in pairs(sub_files) do
                        files[k] = v
                    end
                end
            else
                logger.err("SyncCommon:get_local_files_recursive: Cannot get attributes for", item_path)
            end
        end
    end
    return files
end

-- Create local directories as needed
function SyncCommon.create_local_directories(base_path, file_paths)
    local errors = {}
    for rel_path, _ in pairs(file_paths) do
        local path_parts = split_path(rel_path, "/")
        if #path_parts > 1 then
            local current_dir = base_path
            for i = 1, #path_parts - 1 do
                current_dir = current_dir .. "/" .. path_parts[i]
                local attr = lfs.attributes(current_dir)
                if not attr then
                    local ok, err = lfs.mkdir(current_dir)
                    if not ok then
                        table.insert(errors, "Failed to create directory " .. current_dir .. ": " .. (err or "unknown error"))
                    end
                end
            end
        end
    end
    return errors
end

-- Delete empty local folders
function SyncCommon.delete_empty_folders(base_path)
    local deleted_count = 0
    local errors = {}
    
    local function delete_empty_recursive(path)
        local ok, iter, dir_obj = pcall(lfs.dir, path)
        if not ok then 
            return 
        end
        
        local has_items = false
        for item in iter, dir_obj do
            if item ~= "." and item ~= ".." then
                local item_path = path .. "/" .. item
                local attr = lfs.attributes(item_path)
                if attr and attr.mode == "directory" then
                    delete_empty_recursive(item_path)
                    -- Check again if directory is now empty
                    attr = lfs.attributes(item_path)
                    if attr then 
                        has_items = true 
                    end
                else
                    has_items = true
                end
            end
        end
        
        if not has_items and path ~= base_path then
            local ok, err = lfs.rmdir(path)
            if ok then
                deleted_count = deleted_count + 1
            else
                table.insert(errors, "Failed to remove empty directory " .. path .. ": " .. (err or "unknown error"))
            end
        end
    end
    
    delete_empty_recursive(base_path)
    return deleted_count, errors
end

-- Delete local files and their sidecar directories
function SyncCommon.delete_local_file(file_path)
    local ok, err = lfs.remove(file_path)
    if ok then
        local sdr_path = DocSettings:getSidecarDir(file_path)
        local sdr_attr = lfs.attributes(sdr_path)
        if sdr_attr and sdr_attr.mode == "directory" then
            ffiutil.purgeDir(sdr_path)
        end
        return true
    else
        logger.err("SyncCommon:delete_local_file: Failed to delete", file_path, "error:", err)
        return false, err
    end
end

-- Initialize results table
function SyncCommon.init_results()
    return {
        downloaded = 0,
        failed = 0,
        skipped = 0,
        deleted_files = 0,
        deleted_folders = 0,
        errors = {}
    }
end

-- Add error to results
function SyncCommon.add_error(results, error_msg)
    table.insert(results.errors, error_msg)
end

return SyncCommon
