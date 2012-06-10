require "ui/dialog" -- for Menu

FileChooser = Menu:new{
	path = ".",
	parent = nil,
	show_hidden = false,
	filter = function(filename) return true end,
}

function FileChooser:init()
	self:changeToPath(self.path)
end

function FileChooser:changeToPath(path)
	local dirs = {}
	local files = {}
	self.path = path
	for f in lfs.dir(self.path) do
		if self.show_hidden or not string.match(f, "^%.[^.]") then
			local filename = self.path.."/"..f
			local filemode = lfs.attributes(filename, "mode")
			if filemode == "directory" and f ~= "." and f~=".." then
				table.insert(dirs, f)
			elseif filemode == "file" then
				if self.filter(filename) then
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
