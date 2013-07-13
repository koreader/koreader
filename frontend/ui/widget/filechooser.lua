require "ui/widget/menu"

FileChooser = Menu:new{
	height = Screen:getHeight(),
	width = Screen:getWidth(),
	path = lfs.currentdir(),
	parent = nil,
	show_hidden = false,
	filter = function(filename) return true end,
}

function FileChooser:init()
	self:changeToPath(self.path)
end

function FileChooser:compressPath(item_path)
	-- compress paths like "test/pdf/../epub" into "test/epub"
	local path = item_path
	while path:match("/[^/]+[/][\\.][\\.]") do
		path = path:gsub("/[^/]+[/][\\.][\\.]", "")
	end
	return path
end

function FileChooser:changeToPath(path)
	path = self:compressPath(path)
	local dirs = {}
	local files = {}
	self.path = path
	for f in lfs.dir(self.path) do
		if self.show_hidden or not string.match(f, "^%.[^.]") then
			local filename = self.path.."/"..f
			local filemode = lfs.attributes(filename, "mode")
			if filemode == "directory" and f ~= "." and f~=".." then
				if self.dir_filter(filename) then
					table.insert(dirs, f)
				end
			elseif filemode == "file" then
				if self.file_filter(filename) then
					table.insert(files, f)
				end
			end
		end
	end
	table.sort(dirs)
	if self.path ~= "/" then table.insert(dirs, 1, "..") end
	table.sort(files)

	self.item_table = {}
	for _, dir in ipairs(dirs) do
		table.insert(self.item_table, { text = dir.."/", path = self.path.."/"..dir })
	end
	for _, file in ipairs(files) do
		table.insert(self.item_table, { text = file, path = self.path.."/"..file })
	end

	Menu.init(self) -- call parent's init()
end

function FileChooser:onMenuSelect(item)
	if lfs.attributes(item.path, "mode") == "directory" then
		UIManager:close(self)
		self:changeToPath(item.path)
		UIManager:show(self)
	else
		self:onFileSelect(item.path)
	end
	return true
end

function FileChooser:onFileSelect(file)
	UIManager:close(self)
	return true
end
