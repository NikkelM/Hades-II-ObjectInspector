local catalog
local indexedMap
local parentsById

local function getMapRelationships()
	if not catalog then
		catalog = import "Data/MapRelationships.lua"
	end
	local map = catalog.Maps[mod.CurrentMapName]
	if map and indexedMap ~= map then
		parentsById = {}
		for parentId, object in pairs(map.Objects) do
			for _, childId in ipairs(object.AttachedIDs or {}) do
				parentsById[childId] = parentsById[childId] or {}
				table.insert(parentsById[childId], parentId)
			end
		end
		for _, ids in pairs(parentsById) do
			table.sort(ids)
		end
		indexedMap = map
	end
	return map
end

local function describeObject(map, id)
	local object = map.Objects[id]
	local liveName = game.GetName({ Id = id })
	local result = {
		Id = id,
		Name = object and object.Name or "(not recorded)",
	}
	if liveName == "" then
		result.Status = "Not currently present"
	elseif object and object.Name == liveName then
		local location = game.GetLocation({ Id = id })
		result.Status = "Present with matching type"
		result.X = location.X
		result.Y = location.Y
	else
		result.Status = object and "Present with a different type" or "Present without an exported record"
		result.LiveName = liveName
	end
	if not object then
		result.ExportedRecord = "Missing"
	end
	return result
end

local function logRelatedObjects(map, label, ids)
	rom.log.info(label .. " (" .. #ids .. ")")
	local objects = {}
	for _, id in ipairs(ids) do
		table.insert(objects, describeObject(map, id))
	end
	mod.PrintTable(objects)
end

---@param id integer
---@param name string
function mod.LogObjectRelationships(id, name)
	if game.GetName({ Id = id }) ~= name then
		rom.log.warning("Object Inspector | Object " .. id .. " changed or disappeared - refresh the list")
		return
	end
	local map = getMapRelationships()
	if not map then
		rom.log.warning("Object Inspector | No authored relationship export for room " .. mod.CurrentMapName)
		return
	end
	rom.log.info("Object Inspector | Authored map relationships | " .. mod.CurrentMapName .. " | " .. name .. " " .. id)
	rom.log.info("Static map data - runtime spawning and attachment changes are not reflected")
	local object = map.Objects[id]
	if not object then
		rom.log.info("No relationship record exported for this ID; it may be unrelated, runtime-spawned, or from a changed map")
		return
	end
	if object.Name and object.Name ~= name then
		rom.log.warning("Object Inspector | Exported type " .. object.Name .. " does not match " .. name .. " - regenerate the map data")
		return
	end
	mod.PrintTable({ Object = describeObject(map, id), Source = map.Source, MapSha256 = map.Sha256 })
	logRelatedObjects(map, "Parents (authored child lists)", parentsById[id] or {})
	logRelatedObjects(map, "Children (authored child list)", object.AttachedIDs or {})
	logRelatedObjects(map, "Attached to (movement)", object.AttachToID and { object.AttachToID } or {})
end
