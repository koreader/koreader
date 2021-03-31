local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DocumentRegistry = require("document/documentregistry")
local DropBoxApi = require("apps/cloudstorage/dropboxapi")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")
local util = require("util")
local Screen = require("device").screen
local T = require("ffi/util").template
local _ = require("gettext")
local lfs = require("libs/libkoreader-lfs")

local DropBox = {}

function DropBox:showFilesAndFolders(url, password)
    return DropBoxApi:showFilesAndFoldersV2(url, password)
end

function DropBox:getRemoteFilesMap(url,password,treePath)
    local tree = {}
    local UI = require("ui/trapper")
    local files = DropBox:showFilesAndFolders(url,password)
    for i,file in ipairs(files) do
        if file.type == "folder" then
            UI:info(_("Retrieving folder ".. treePath.."/"..file.text .."…"))
            local subtree = DropBox:getRemoteFilesMap(file.url,password,treePath.."/"..file.text)
            for k,subf in pairs(subtree) do
                tree[k]=subf
            end
        else
            tree[treePath.."/"..file.text] = file
        end
	end
    return tree
end

function DropBox:synchronize(item)
    local function tableSlice(t, l,r)
        if not r then r = #t end
        local nt = {}
        for i=l,r do
            table.insert(nt,t[i])
        end
        return nt
    end
    local function stringSplit(s, sep)
	--implem: https://stackoverflow.com/questions/1426954/split-string-in-lua
        if sep == nil then
                sep = "%s"
        end
        local t={}
        for str in string.gmatch(s, "([^"..sep.."]+)") do
                table.insert(t, str)
        end
        return t
end
    
    -- local utility functions
    local function _getLocalFilesMap(path,treePath)
        local DocSettings = require("docsettings")
        local tree = {}
        local ok, iter, dir_obj = pcall(lfs.dir, path)
        local sdrMap = {}
        if ok then
            for f in iter, dir_obj do
                local filename = path .."/" .. f
                local attributes = lfs.attributes(filename)
                if attributes.mode == "file" and f ~= ".DS_Store" then
                    tree[treePath.."/"..f]={size=attributes.size, has_sdr=false}
                elseif attributes.mode == "directory" and f:find("%.sdr$") ~= nil then
                    sdrMap[treePath.."/"..f]=true
                elseif attributes.mode == "directory" and f:find("^%.") == nil then
                    local subtree = _getLocalFilesMap(filename,treePath.."/"..f)
                    for k,subf in pairs(subtree) do
                        tree[k]=subf
                    end
                end
            end
        end
        for k,v in pairs(tree) do
            local sdr_path = DocSettings:getSidecarDir(k)
            if sdrMap[sdr_path] ~= nil then
                v.has_sdr = true
            end
        end
        return tree
    end
    
    
    local function _filesMapToTree(filesMap)
        local foldTree = {}
        for k,v in pairs(filesMap) do
            local r = tableSlice(stringSplit(k,"/"),1)
            local fileName = r[#r]
            local folderList = tableSlice(r,0,#r-1)
            local cur = foldTree
            for _,k in ipairs(folderList)do
                if not cur[k] then
                    cur[k]={}
                end
                cur = cur[k]
            end
            cur[fileName] = true
        end
        return foldTree
    end
    
    local function _prepTree(path, remoteFilesMap)
        --create the folders to accept the future files
        -- build a "foldTree", recursive object { with the list of }
        local foldTree = _filesMapToTree(remoteFilesMap)
        -- fprint(foldTree)
        local function createFolderIfNotExists(tree, path)
            for k,v in pairs(tree) do
                if type(v) == "table" then
                    -- check folder exists
                    local subpath = path .. "/" .. k
                    local exists = lfs.attributes(subpath)
                    if not exists then
                        lfs.mkdir(subpath)
                    end
                    createFolderIfNotExists(v,subpath)
                end
            end
        end
        createFolderIfNotExists(foldTree,path)
    end
    
    local function _moveOldFiles(path, localFilesMap, remoteFilesMap)
        local DocSettings = require("docsettings")
        local ffiutil = require("ffi/util")
        --find files already existing in the localTree, and move them to the correct place
        local FileManager = require("apps/filemanager/filemanager")
        local m = {}
        local filesToRemove = {}
        local filesToMove = {}
        for k, _ in pairs(remoteFilesMap) do
            local arr = stringSplit(k,"/")
            local filename = arr[#arr]
            local obj = {path=k,matched=false}
            if m[filename] ~= nil then 
                table.insert(m[filename],obj)
            else
                m[filename] = {obj}
            end
        end
        
        for k, _ in pairs(localFilesMap) do
            local arr = stringSplit(k,"/")
            local filename = arr[#arr]
            if m[filename] then
                for _,v in ipairs(m[filename]) do
                    if k == v.path then
                        v.matched=true
                        break;
                    end
                end
            end
        end
    
        local modifiedLocalFilesMap = {}
    
        for k, d in pairs(localFilesMap) do
            local arr = stringSplit(k,"/")
            local filename = arr[#arr]
            local found=false
            if m[filename] then
                for _,v in ipairs(m[filename]) do
                    if k == v.path then
                        found=true
                        break;
                    end
                end
                if found == false then
                    -- try to find if it's an old DB
                    for _,v in ipairs(m[filename]) do
                        if v.matched == false then
                            found = true
                            modifiedLocalFilesMap[k]=true
                            table.insert(filesToMove, {src=path..k,dst=path..v.path, has_sdr=d.has_sdr}) 
                            break;
                        end
                    end
                end
            end
            if found == false then
                modifiedLocalFilesMap[k]=true
                table.insert(filesToRemove, {src=path..k,has_sdr=d.has_sdr}) 
            end
        end
        for i, v in ipairs(filesToMove) do
            FileManager:moveFile(v.src,v.dst)
            if v.has_sdr then
                FileManager:moveFile( DocSettings:getSidecarDir(v.src), DocSettings:getSidecarDir(v.dst))
            end
        end
        
        --remove all the empty folders
        local foldTree = _filesMapToTree(modifiedLocalFilesMap)
        local function folderHasFile(folderPath)
            local ok, iter, dir_obj = pcall(lfs.dir, folderPath)
            if not ok then return false end
            local found = false
            for f in iter, dir_obj do
                local filename = folderPath .."/" .. f
                local attributes = lfs.attributes(filename)
                if attributes.mode == "file" and f ~= ".DS_Store" then
                    found = true
                    break;
                elseif attributes.mode == "directory" and f ~= "." and f ~= ".."then
                    found = true
                    break;
                end
            end
            return found
        end
        local function recursiveRemoveEmptyFolder(tree,path)
            for k,v in pairs(tree) do
                if type(v) == "table" then
                    -- check folder exists
                    local subpath = path .. "/" .. k
                    recursiveRemoveEmptyFolder(v,subpath)
                    if folderHasFile(subpath) == false then
                        --can remove this folder
                        ffiutil.purgeDir(subpath)
                    end
                end
            end
        end
        recursiveRemoveEmptyFolder(foldTree,path)
        --from the removed files, check each folder and check if empty, if empty, remove it
    end
    
    local function _getRemoteFilesToDownload(path,remoteFilesMap)
        local remoteFilesToDL = {}
        local foldTree = _filesMapToTree(remoteFilesMap)
        for k,file in pairs(remoteFilesMap) do
            local exists = lfs.attributes(path.."/"..k)
            if not exists then 
                file.local_url = k
                table.insert(remoteFilesToDL, file)
            end
        end
        return remoteFilesToDL
    end
    
    local function _downloadRemoteFiles(path,remoteFilesDownload,item,UI)
        local response, go_on
        local proccessed_files = 0
        local success_files = 0
        local unsuccess_files = 0
        for _, file in ipairs(remoteFilesDownload) do
                proccessed_files = proccessed_files + 1
                print(file.local_url)
                local text = string.format("Downloading file (%d/%d):\n%s", proccessed_files, #remoteFilesDownload, file.text)
                go_on = UI:info(text)
                if not go_on then
                    break
                end
                response = DropBox:downloadFileNoUI(file.url, item.password, path .. "/" .. file.local_url)
                if response then
                    success_files = success_files + 1
                else
                    unsuccess_files = unsuccess_files + 1
                end
        end
        UI:clear()
        return success_files, unsuccess_files
    end

    local path = item.sync_dest_folder
    local UI = require("ui/trapper")
    UI:info(_("Retrieving files…"))
    local local_files_map = _getLocalFilesMap(path,"")
    local remote_files_map = DropBox:getRemoteFilesMap(item.sync_source_folder, item.password,"")
    _moveOldFiles(path, local_files_map, remote_files_map)
    _prepTree(path,remote_files_map)
    local remote_files_to_download = _getRemoteFilesToDownload(path, remote_files_map)
    local success_files, unsuccess_files = _downloadRemoteFiles(path,remote_files_to_download, item,UI)

    UI:clear()
    return success_files, unsuccess_files
end

function DropBox:run(url, password, choose_folder_mode)
    return DropBoxApi:listFolder(url, password, choose_folder_mode)
end

function DropBox:showFiles(url, password)
    return DropBoxApi:showFiles(url, password)
end

function DropBox:downloadFile(item, password, path, callback_close)
    local code_response = DropBoxApi:downloadFile(item.url, password, path)
    if code_response == 200 then
        local __, filename = util.splitFilePathName(path)
        if G_reader_settings:isTrue("show_unsupported") and not DocumentRegistry:hasProvider(filename) then
            UIManager:show(InfoMessage:new{
                text = T(_("File saved to:\n%1"), BD.filename(path)),
            })
        else
            UIManager:show(ConfirmBox:new{
                text = T(_("File saved to:\n%1\nWould you like to read the downloaded book now?"),
                    BD.filepath(path)),
                ok_callback = function()
                    local Event = require("ui/event")
                    UIManager:broadcastEvent(Event:new("SetupShowReader"))

                    if callback_close then
                        callback_close()
                    end

                    ReaderUI:showReader(path)
                end
            })
        end
    else
        UIManager:show(InfoMessage:new{
            text = T(_("Could not save file to:\n%1"), BD.filepath(path)),
            timeout = 3,
        })
    end
end

function DropBox:downloadFileNoUI(url, password, path)
    local code_response = DropBoxApi:downloadFile(url, password, path)
    if code_response == 200 then
        return true
    else
        return false
    end
end

function DropBox:config(item, callback)
    local text_info = "How to generate Access Token:\n"..
        "1. Open the following URL in your Browser, and log in using your account: https://www.dropbox.com/developers/apps.\n"..
        "2. Click on >>Create App<<, then select >>Dropbox API app<<.\n"..
        "3. Now go on with the configuration, choosing the app permissions and access restrictions to your DropBox folder.\n"..
        "4. Enter the >>App Name<< that you prefer (e.g. KOReader).\n"..
        "5. Now, click on the >>Create App<< button.\n" ..
        "6. When your new App is successfully created, please click on the Generate button.\n"..
        "7. Under the 'Generated access token' section, then enter code in Dropbox token field."
    local hint_top = _("Your Dropbox name")
    local text_top = ""
    local hint_bottom = _("Dropbox token\n\n\n\n")
    local text_bottom = ""
    local title
    local text_button_right = _("Add")
    if item then
        title = _("Edit Dropbox account")
        text_button_right = _("Apply")
        text_top = item.text
        text_bottom = item.password
    else
        title = _("Add Dropbox account")
    end
    self.settings_dialog = MultiInputDialog:new {
        title = title,
        fields = {
            {
                text = text_top,
                hint = hint_top ,
            },
            {
                text = text_bottom,
                hint = hint_bottom,
                scroll = false,
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)
                    end
                },
                {
                    text = _("Info"),
                    callback = function()
                        UIManager:show(InfoMessage:new{ text = text_info })
                    end
                },
                {
                    text = text_button_right,
                    callback = function()
                        local fields = MultiInputDialog:getFields()
                        if fields[1] ~= "" and fields[2] ~= "" then
                            if item then
                                --edit
                                callback(item, fields)
                            else
                                -- add new
                                callback(fields)
                            end
                            self.settings_dialog:onClose()
                            UIManager:close(self.settings_dialog)
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("Please fill in all fields.")
                            })
                        end
                    end
                },
            },
        },
        width = math.floor(Screen:getWidth() * 0.95),
        height = math.floor(Screen:getHeight() * 0.2),
        input_type = "text",
    }
    UIManager:show(self.settings_dialog)
    self.settings_dialog:onShowKeyboard()
end

function DropBox:info(token)
    local info = DropBoxApi:fetchInfo(token)
    local info_text
    if info and info.name then
        info_text = T(_"Type: %1\nName: %2\nEmail: %3\nCountry: %4",
            "Dropbox",info.name.display_name, info.email, info.country)
    else
        info_text = _("No information available")
    end
    UIManager:show(InfoMessage:new{text = info_text})
end

return DropBox
