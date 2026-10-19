local function collectObjectTypes(data)
	for _, key in ipairs({ "Obstacles", "Units" }) do
		for _, entry in ipairs(data[key] or {}) do
			mod.RegisterObjectType(entry.Name)
		end
	end
end

local function loadObjectTypeDirectory(directory)
	for _, path in ipairs(rom.path.get_files(directory)) do
		if path:lower():match("%.sjson$") then
			local file, message = io.open(path, "r")
			assert(file, "Object Inspector cannot read " .. path .. ": " .. tostring(message))
			local text = file:read("*a")
			file:close()
			collectObjectTypes(sjson.decode(text))
			sjson.hook(path, collectObjectTypes)
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
