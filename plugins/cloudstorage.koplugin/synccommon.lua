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

-- Get local files recursively
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

-- Create directory recursively
function SyncCommon.mkdir_recursive(path)
    local ok, err = lfs.mkdir(path)
    if ok or err == "File exists" then
        return true
    end

    -- Try to create parent directory first
    local parent = path:match("^(.+)/[^/]+$")
    if parent then
        local parent_ok = SyncCommon.mkdir_recursive(parent)
        if parent_ok then
            return lfs.mkdir(path)
        end
    end

    return false, err
end

-- Delete local file
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

return SyncCommon
