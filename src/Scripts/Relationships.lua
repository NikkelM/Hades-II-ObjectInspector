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

function mod.DescribeRelatedObject(map, id)
	local object = map.Objects[id]
	local liveName = game.GetName({ Id = id })
	local result = {
		Id = id,
		Name = object and object.Name or "(unknown)",
	}
	if liveName == "" then
		result.Status = "Not present"
	elseif object and object.Name == liveName then
		local location = game.GetLocation({ Id = id })
		result.Status = "Present"
		result.X = location.X
		result.Y = location.Y
	else
		result.Status = object and "Type mismatch" or "Present"
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
		table.insert(objects, mod.DescribeRelatedObject(map, id))
	end
	mod.PrintTable(objects)
end

---@param id integer
---@param name string
function mod.GetObjectRelationships(id, name)
	local map = getMapRelationships()
	if not map then
		return { Message = "No relationship data for " .. mod.CurrentMapName }
	end
	local object = map.Objects[id]
	if object and object.Name and object.Name ~= name then
		return { Message = "Map type mismatch: " .. object.Name .. " / " .. name }
	end
	return {
		Map = map,
		Object = object,
		Parents = parentsById[id] or {},
		Children = object and object.AttachedIDs or {},
		AttachedTo = object and object.AttachToID and { object.AttachToID } or {},
		Message = not object and "No map record for " .. id or nil,
	}
end

---@param id integer
---@param name string
function mod.LogObjectRelationships(id, name)
	if game.GetName({ Id = id }) ~= name then
		rom.log.warning("Object Inspector | Object " .. id .. " no longer matches the list")
		return
	end
	local relationships = mod.GetObjectRelationships(id, name)
	local map = relationships.Map
	if not map then
		rom.log.warning("Object Inspector | " .. relationships.Message)
		return
	end
	rom.log.info("Object Inspector | Relationships | " .. mod.CurrentMapName .. " | " .. name .. " " .. id)
	if relationships.Message then
		rom.log.info(relationships.Message)
	end
	mod.PrintTable({ Object = mod.DescribeRelatedObject(map, id), Source = map.Source })
	logRelatedObjects(map, "Parents", relationships.Parents)
	logRelatedObjects(map, "Children", relationships.Children)
	logRelatedObjects(map, "Attached to", relationships.AttachedTo)
end
