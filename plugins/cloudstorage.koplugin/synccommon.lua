local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")

local SyncCommon = {}

-- Initialize sync results structure
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
    logger.err("SyncCommon error:", error_msg)
end

-- Call progress callback safely
function SyncCommon.call_progress_callback(callback, kind, current, total, rel_path)
    if callback then
        local ok, err = pcall(callback, kind, current, total, rel_path)
        if not ok then
            logger.err("SyncCommon: Progress callback failed:", err)
        end
    end
end

-- Get local files recursively with streaming approach to save memory
function SyncCommon.get_local_files_recursive(base_path, current_rel_path)
    local files = {}
    local current_path = base_path .. (current_rel_path ~= "" and "/" .. current_rel_path or "")

    local ok, iter, dir_obj = pcall(lfs.dir, current_path)
    if not ok then
        logger.warn("SyncCommon: Cannot read directory:", current_path)
        return files
    end

    for file in iter, dir_obj do
        if file ~= "." and file ~= ".." then
            local file_path = current_path .. "/" .. file
            local rel_path = current_rel_path ~= "" and (current_rel_path .. "/" .. file) or file
            local attributes = lfs.attributes(file_path)

            if attributes then
                if attributes.mode == "file" then
                    files[rel_path] = {
                        path = file_path,
                        size = attributes.size,
                        mtime = attributes.modification,
                        type = "file"
                    }
                elseif attributes.mode == "directory" then
                    local sub_files = SyncCommon.get_local_files_recursive(base_path, rel_path)
                    for k, v in pairs(sub_files) do
                        files[k] = v
                    end
                end
            end
        end
    end

    return files
end

-- Create local directories based on remote file structure
function SyncCommon.create_local_directories(base_path, remote_files)
    local errors = {}
    local dirs_to_create = {}

    -- Collect all directory paths
    for rel_path, file_info in pairs(remote_files) do
        if file_info.type == "file" then
            local dir_path = rel_path:match("^(.+)/[^/]+$")
            if dir_path then
                dirs_to_create[dir_path] = true
            end
        end
    end

    -- Create directories
    for dir_rel_path, _ in pairs(dirs_to_create) do
        local full_dir_path = base_path .. "/" .. dir_rel_path
        local ok, err = SyncCommon.mkdir_recursive(full_dir_path)
        if not ok then
            table.insert(errors, _("Failed to create directory: ") .. dir_rel_path .. " (" .. (err or "unknown error") .. ")")
        end
    end

    return errors
end

-- Create directory recursively with proper error handling
function SyncCommon.mkdir_recursive(path)
    local ok, err = lfs.mkdir(path)
    if ok or (err and err:match("File exists")) then
        return true
    end

    -- Try to create parent directory first
    local parent = path:match("^(.+)/[^/]+$")
    if parent then
        local parent_ok, parent_err = SyncCommon.mkdir_recursive(parent)
        if parent_ok then
            return lfs.mkdir(path)
        else
            return false, parent_err
        end
    end

    return false, err
end

-- Delete local file with proper error handling
function SyncCommon.delete_local_file(file_path)
    local ok, err = os.remove(file_path)
    if ok then
        logger.dbg("SyncCommon: Deleted file:", file_path)
        return true
    else
        logger.err("SyncCommon: Failed to delete file:", file_path, "error:", err)
        return false, err
    end
end

-- Common recursive file scanner for all providers
function SyncCommon.get_remote_files_recursive(provider, list_function, base_params, sync_folder_path, on_progress)
    local files = {}
    local processed_folders = {} -- Prevent infinite loops

    local function getFilesRecursive(current_path, current_rel_path)
        if processed_folders[current_path] then
            logger.warn("SyncCommon: Circular reference detected, skipping:", current_path)
            return
        end
        processed_folders[current_path] = true

        logger.dbg("SyncCommon: Scanning remote folder:", current_path, "rel_path:", current_rel_path)

        -- Use provider's list function
        local params = {}
        for i, param in ipairs(base_params) do
            params[i] = param
        end
        table.insert(params, current_path)
        table.insert(params, false) -- folder_mode = false for sync

        local file_list, err = list_function(unpack(params))
        if not file_list then
            logger.err("SyncCommon: Failed to list folder", current_path, "error:", err or "unknown")
            return
        end

        logger.dbg("SyncCommon: Found", #file_list, "items in", current_path)

        for i, item in ipairs(file_list) do
            -- Yield periodically to keep UI responsive
            if i % 20 == 0 and require("ui/uimanager").UIManager then
                require("ui/uimanager").UIManager:nextTick(function() end)
            end

            if item.type == "file" then
                local rel_path = current_rel_path and current_rel_path ~= "" and (current_rel_path .. "/" .. item.text) or item.text
                files[rel_path] = {
                    url = item.url,
                    size = item.filesize or item.size or item.mandatory,
                    text = item.text,
                    type = "file",
                    mtime = item.mtime or item.modification,
                    relative_path = item.relative_path or rel_path
                }
            elseif item.type == "folder" then
                local folder_name = item.text:gsub("/$", "") -- Remove trailing slash
                local sub_rel_path = current_rel_path and current_rel_path ~= "" and (current_rel_path .. "/" .. folder_name) or folder_name
                local sub_path = current_path .. "/" .. folder_name
                getFilesRecursive(sub_path, sub_rel_path)
            end
        end
    end

    local start_path = sync_folder_path and sync_folder_path ~= "" and sync_folder_path or ""
    getFilesRecursive(start_path, "")

    return files
end

-- Check if file should be downloaded based on size and modification time
function SyncCommon.should_download_file(local_file, remote_file)
    if not local_file then
        return true -- File doesn't exist locally
    end

    -- Compare sizes
    if remote_file.size and local_file.size ~= remote_file.size then
        return true
    end

    -- Compare modification times if available
    if remote_file.mtime and local_file.mtime and remote_file.mtime > local_file.mtime then
        return true
    end

    return false
end

-- Safe file operations with proper cleanup
function SyncCommon.safe_file_operation(operation, file_path, mode)
    local file_handle = nil
    local ok, result = pcall(function()
        file_handle = io.open(file_path, mode or "r")
        if not file_handle then
            error("Failed to open file: " .. file_path)
        end
        return operation(file_handle)
    end)

    -- Ensure file is always closed
    if file_handle then
        pcall(file_handle.close, file_handle)
    end

    if not ok then
        return false, result
    end
    return true, result
end

-- Yield control during long operations to keep UI responsive
function SyncCommon.yield_if_needed(counter, yield_interval)
    yield_interval = yield_interval or 10
    if counter % yield_interval == 0 and require("ui/uimanager").UIManager then
        require("ui/uimanager").UIManager:nextTick(function() end)
    end
end

return SyncCommon
