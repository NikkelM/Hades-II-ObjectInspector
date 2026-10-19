local cachePath = rom.path.combine(rom.paths.plugins_data(), _PLUGIN.guid, "ObjectTypes.sjson")
if rom.path.exists(cachePath) then
	mod.CachedObjectTypes = assert(sjson.decode_file(cachePath), "Object Inspector cannot decode " .. cachePath)
	for name in pairs(mod.CachedObjectTypes) do
		mod.RegisterObjectType(name)
	end
end

local staticObjectTypes = {}
local observedObjectTypes = {}

local function collectObjectTypes(data, source, static)
	local cacheChanged = false
	for _, key in ipairs({ "Obstacles", "Units" }) do
		for _, entry in ipairs(data[key] or {}) do
			mod.RegisterObjectType(entry.Name, key, source)
			if static then
				staticObjectTypes[entry.Name] = true
			elseif not staticObjectTypes[entry.Name] and not observedObjectTypes[entry.Name] then
				observedObjectTypes[entry.Name] = true
				local cached = mod.CachedObjectTypes[entry.Name]
				if not cached or cached.Category ~= key or cached.Source ~= source then
					mod.CachedObjectTypes[entry.Name] = { Category = key, Source = source }
					cacheChanged = true
				end
			end
		end
	end
	-- The game can reset Lua without rereading engine definitions, so retain patched-only types on disk
	if cacheChanged then
		sjson.encode_file(cachePath, mod.CachedObjectTypes)
	end
end

local function loadObjectTypeDirectory(directory)
	for _, path in ipairs(rom.path.get_files(directory)) do
		if path:lower():match("%.sjson$") then
			local source = rom.path.stem(path)
			local file, message = io.open(path, "r")
			assert(file, "Object Inspector cannot read " .. path .. ": " .. tostring(message))
			local text = file:read("*a")
			file:close()
			collectObjectTypes(sjson.decode(text), source, true)
		end
	end
end

for _, category in ipairs({ "Obstacles", "Units" }) do
	local directory = rom.path.combine(rom.paths.Content(), "Game", category)
	loadObjectTypeDirectory(directory)
	-- Observe patched vanilla and overlay files through their logical Content paths
	rom.data.on_sjson_read_as_string(function(path, content)
		collectObjectTypes(sjson.decode(content), rom.path.stem(path))
	end, directory .. "\\")
end

-- Include additive SJSON definitions shipped by other mods
for _, pluginDirectory in ipairs(rom.path.get_directories(rom.paths.plugins_data())) do
	local directory = rom.path.combine(pluginDirectory, "Hell2Modding-SJSON")
	if rom.path.exists(directory) then
		for _, category in ipairs({ "Obstacles", "Units" }) do
			local path = rom.path.combine(directory, category)
			if rom.path.exists(path) then
				loadObjectTypeDirectory(path)
			end
		end
	end
end
