DocSettings = {}

function DocSettings:open(docfile)
	local new = {}
	new.docdb, errno, errstr = sqlite3.open(docfile..".kpdfview")
	if new.docdb ~= nil then
		new.docdb:exec("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT);")
		new.stmt_readsetting = new.docdb:prepare("SELECT value FROM settings WHERE key = ?;")
		new.stmt_savesetting = new.docdb:prepare("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?);")
	end
	return setmetatable(new, { __index = DocSettings})
end

function DocSettings:readsetting(key)
	if self.docdb ~= nil then
		self.stmt_readsetting:reset()
		self.stmt_readsetting:bind_values(key)
		local result = self.stmt_readsetting:step()
		if result == sqlite3.ROW then
			return self.stmt_readsetting:get_value(0)
		end
	end
end

function DocSettings:savesetting(key, value)
	if self.docdb ~= nil then
		self.stmt_savesetting:reset()
		self.stmt_savesetting:bind_values(key, value)
		self.stmt_savesetting:step()
	end
end

function DocSettings:close()
	if self.docdb ~= nil then
		self.docdb:close()
		self.docdb = nil
	end
end
