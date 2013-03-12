DocSettings = {}

function DocSettings:getHistoryPath(fullpath)
	local i = #fullpath - 1
	-- search for last slash
	while i > 0 do
		if fullpath:sub(i,i) == "/" then
			break
		end
		i = i - 1
	end
	-- construct path to configuration file in history dir
	local filename = fullpath:sub(i+1, -1)
	local basename = fullpath:sub(1, i)
	return "./history/["..basename:gsub("/","#").."] "..filename..".lua"
end

function DocSettings:getPathFromHistory(hist_name)
	-- 1. select everything included in brackets
	local s = string.match(hist_name,"%b[]")
	-- 2. crop the bracket-sign from both sides
	-- 3. and finally replace decorative signs '#' to dir-char '/'
	return string.gsub(string.sub(s,2,-3),"#","/")
end

function DocSettings:getNameFromHistory(hist_name)
	-- at first, search for path length
	local s = string.len(string.match(hist_name,"%b[]"))
	-- and return the rest of string without 4 last characters (".lua")
	return string.sub(hist_name, s+2, -5)
end

function DocSettings:open(docfile)
	local conf_path = nil
	if docfile == ".reader" then
		-- we handle reader setting as special case
		conf_path = "settings.reader.lua"
	else
		conf_path = self:getHistoryPath(docfile)
	end
	-- construct settings obj
	local new = { file = conf_path, data = {} }
	local ok, stored = pcall(dofile, new.file)
	if not ok then
		-- try legacy conf path, for backward compatibility. this also
		-- takes care of reader legacy setting
		ok, stored = pcall(dofile, docfile..".kpdfview.lua")
	end
	if ok then
		new.data = stored
	end
	return setmetatable(new, { __index = DocSettings})
end

function DocSettings:readSetting(key)
	return self.data[key]
end

function DocSettings:saveSetting(key, value)
	self.data[key] = value
end

function DocSettings:delSetting(key)
	self.data[key] = nil
end

function dump(data)
	local out = {}
	DocSettings:_serialize(data, out, 0)
	return table.concat(out)
end

function DEBUG(...)
	local line = ""
	for i,v in ipairs({...}) do
		if type(v) == "table" then
			line = line .. " " .. dump(v)
		else
			line = line .. " " .. tostring(v)
		end
	end
	print("#"..line)
end

-- simple serialization function, won't do uservalues, functions, loops
function DocSettings:_serialize(what, outt, indent)
	if type(what) == "table" then
		local didrun = false
		table.insert(outt, "{")
		for k, v in pairs(what) do
			if didrun then
				table.insert(outt, ",")
			end
			table.insert(outt, "\n")
			table.insert(outt, string.rep("\t", indent+1))
			table.insert(outt, "[")
			self:_serialize(k, outt, indent+1)
			table.insert(outt, "] = ")
			self:_serialize(v, outt, indent+1)
			didrun = true
		end
		if didrun then
			table.insert(outt, "\n")
			table.insert(outt, string.rep("\t", indent))
		end
		table.insert(outt, "}")
	elseif type(what) == "string" then
		table.insert(outt, string.format("%q", what))
	elseif type(what) == "number" or type(what) == "boolean" then
		table.insert(outt, tostring(what))
	end
end

function DocSettings:flush()
	-- write a serialized version of the data table
	if not self.file then
		return
	end
	local f_out = io.open(self.file, "w")
	if f_out ~= nil then
		local out = {"-- we can read Lua syntax here!\nreturn "}
		self:_serialize(self.data, out, 0)
		table.insert(out, "\n")
		f_out:write(table.concat(out))
		f_out:close()
	end
end

function DocSettings:close()
	self:flush()
end
