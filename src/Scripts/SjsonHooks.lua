local function collectObjectTypes(data, source)
	for _, key in ipairs({ "Obstacles", "Units" }) do
		for _, entry in ipairs(data[key] or {}) do
			mod.RegisterObjectType(entry.Name, key, source)
		end
	end
end

local function loadObjectTypeDirectory(directory)
	for _, path in ipairs(rom.path.get_files(directory)) do
		if path:lower():match("%.sjson$") then
			local source = rom.path.stem(path)
			local function collect(data)
				collectObjectTypes(data, source)
			end
			local file, message = io.open(path, "r")
			assert(file, "Object Inspector cannot read " .. path .. ": " .. tostring(message))
			local text = file:read("*a")
			file:close()
			collect(sjson.decode(text))
			-- Observe the buffer after the SJSON dependency has run all registered mod hooks
			rom.data.on_sjson_read_as_string(function(_, content)
				collect(sjson.decode(content))
			end, path)
		end
	end
end

for _, category in ipairs({ "Obstacles", "Units" }) do
	loadObjectTypeDirectory(rom.path.combine(rom.paths.Content(), "Game", category))
end

-- Include additive SJSON definitions shipped by other mods
for _, directory in ipairs(rom.path.get_directories(rom.paths.plugins_data())) do
	if rom.path.filename(directory) == "Hell2Modding-SJSON" then
		for _, category in ipairs({ "Obstacles", "Units" }) do
			local path = rom.path.combine(directory, "Game", category)
			if rom.path.exists(path) then
				loadObjectTypeDirectory(path)
			end
		end
	end
end
