require "ui/dialog" -- for Menu

FileChooser = Menu:new{
	path = ".",
	show_hidden = false,
	filter = function(filename) return true end,
}

function FileChooser:init()
	self:changeToPath(self.path)
end

function FileChooser:changeToPath(path)
	local dirs = {}
	local files = {}
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
		table.insert(self.item_table, { text = dir.."/" })
	end
	for _, file in ipairs(files) do
		table.insert(self.item_table, { text = file })
	end

	Menu.init(self) -- call parent's init()
end
