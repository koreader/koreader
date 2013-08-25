require "ui/widget/menu"

FileChooser = Menu:extend{
	height = Screen:getHeight(),
	width = Screen:getWidth(),
	no_title = true,
	path = lfs.currentdir(),
	parent = nil,
	show_hidden = false,
	filter = function(filename) return true end,
}

function FileChooser:init()
	self.item_table = self:genItemTableFromPath(self.path)
	Menu.init(self) -- call parent's init()
end

function FileChooser:genItemTableFromPath(path)
	local dirs = {}
	local files = {}

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
	if path ~= "/" then table.insert(dirs, 1, "..") end
	table.sort(files)

	local item_table = {}
	for _, dir in ipairs(dirs) do
		table.insert(item_table, { text = dir.."/", path = self.path.."/"..dir })
	end
	for _, file in ipairs(files) do
		table.insert(item_table, { text = file, path = self.path.."/"..file })
	end

	return item_table
end

function FileChooser:changeToPath(path)
	path = util.realpath(path)
	self.path = path
	self:swithItemTable(nil, self:genItemTableFromPath(path))
end

function FileChooser:toggleHiddenFiles()
	self.show_hidden = not self.show_hidden
	self:swithItemTable(nil, self:genItemTableFromPath(self.path))
end

function FileChooser:onMenuSelect(item)
	if lfs.attributes(item.path, "mode") == "directory" then
		self:changeToPath(item.path)
	else
		self:onFileSelect(item.path)
	end
	return true
end

function FileChooser:onFileSelect(file)
	UIManager:close(self)
	return true
end
