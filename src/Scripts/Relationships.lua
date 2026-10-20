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

---@param groups ObjectInspectorGroup[]
---@param includeMissing boolean
---@param filter string
function mod.GetObjectHierarchy(groups, includeMissing, filter)
	local map = getMapRelationships()
	if not map then
		return { Roots = {}, Nodes = {}, Message = "No relationship data for " .. mod.CurrentMapName }
	end
	local nodes = {}
	local function addNode(id, name, group)
		if nodes[id] then
			return
		end
		local category = group and group.Category or mod.GetObjectTypeInfo(name)
		local object = map.Objects[id]
		if category == "Obstacles"
			and (not group or not object or not object.Name or object.Name == name)
			and (parentsById[id] or (object and (#(object.AttachedIDs or {}) > 0 or object.AttachToID))) then
			nodes[id] = { Id = id, Name = name, Group = group, Children = {} }
		end
	end
	local matchingIds = {}
	for _, group in ipairs(groups) do
		for _, id in ipairs(group.Ids) do
			matchingIds[id] = true
		end
	end
	for _, group in ipairs(mod.ObjectGroups) do
		for _, id in ipairs(group.Ids) do
			addNode(id, group.Name, group)
		end
	end
	if includeMissing then
		for id, object in pairs(map.Objects) do
			addNode(id, object.Name or "(unknown)")
		end
	end
	for childId, parentIds in pairs(parentsById) do
		local child = nodes[childId]
		if child then
			for _, parentId in ipairs(parentIds) do
				local parent = nodes[parentId]
				if parent and parentId ~= childId then
					child.Parent = parent
					break
				end
			end
		end
	end
	-- Choose one parent per row and break cycles so every object remains reachable once
	local checked = {}
	local ids = {}
	for id in pairs(nodes) do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local node = nodes[id]
		local path = {}
		local current = node
		while current and not checked[current.Id] do
			path[current.Id] = true
			if current.Parent and path[current.Parent.Id] then
				current.Parent = nil
				break
			end
			current = current.Parent
		end
		for id in pairs(path) do
			checked[id] = true
		end
	end
	local roots = {}
	for _, node in pairs(nodes) do
		if node.Parent then
			table.insert(node.Parent.Children, node)
		else
			table.insert(roots, node)
		end
	end
	filter = filter:lower()
	for _, node in pairs(nodes) do
		local matches = filter == "" or matchingIds[node.Id]
		if not node.Group then
			matches = filter == "" or node.Name:lower():find(filter, 1, true)
				or tostring(node.Id):find(filter, 1, true) or map.Source:lower():find(filter, 1, true)
		end
		node.Matches = not not matches
		node.SelectionIds = {}
		node.SelectedCount = 0
		if matches then
			local current = node
			while current and not current.Visible do
				current.Visible = true
				current = current.Parent
			end
		end
	end
	for _, id in ipairs(ids) do
		local node = nodes[id]
		if node.Group and node.Matches then
			local selected = mod.IsObjectSelected(node.Name, id)
			local current = node
			while current do
				table.insert(current.SelectionIds, id)
				if selected then
					current.SelectedCount = current.SelectedCount + 1
				end
				current = current.Parent
			end
		end
	end
	local mode = config.sortMode
	local distanceSort = mod.IsObjectDistanceSort(mode)
	local function compare(left, right)
		if distanceSort and mod.ObjectDistances[left.Id] ~= mod.ObjectDistances[right.Id] then
			local a, b = mod.ObjectDistances[left.Id], mod.ObjectDistances[right.Id]
			if a == nil then
				return false
			elseif b == nil then
				return true
			elseif mode == "Distance (closest first)" then
				return a < b
			end
			return a > b
		elseif mode == "ID (newest first)" then
			return left.Id > right.Id
		elseif mode == "Count (most first)" and #left.Children ~= #right.Children then
			return #left.Children > #right.Children
		elseif mode == "Count (fewest first)" and #left.Children ~= #right.Children then
			return #left.Children < #right.Children
		elseif left.Name:lower() ~= right.Name:lower() then
			if mode == "Name (Z-A)" then
				return left.Name:lower() > right.Name:lower()
			end
			return left.Name:lower() < right.Name:lower()
		end
		return left.Id < right.Id
	end
	table.sort(roots, compare)
	for _, node in pairs(nodes) do
		table.sort(node.Children, compare)
	end
	return {
		Roots = roots,
		Nodes = nodes,
	}
end

function mod.GetHierarchyGroups(hierarchy)
	local groups = {}
	local byType = {}
	for _, root in ipairs(hierarchy.Roots) do
		if root.Visible then
			local category, source = mod.GetObjectTypeInfo(root.Name)
			local liveGroup = root.Group
			if not liveGroup and #root.SelectionIds > 0 then
				liveGroup = hierarchy.Nodes[root.SelectionIds[1]].Group
				if category == "Other" then
					category, source = liveGroup.Category, liveGroup.Source
				end
			end
			local key = category .. ":" .. source .. ":" .. root.Name
			local group = byType[key]
			if not group then
				group = {
					Name = root.Name, SearchName = root.Name:lower(), Category = category, Source = source,
					Color = liveGroup and liveGroup.Color or { 0.6, 0.6, 0.6, 1 },
					Ids = {}, Roots = {}, SelectedCount = 0, LogGroups = {},
				}
				byType[key] = group
				table.insert(groups, group)
			end
			table.insert(group.Roots, root)
			group.SelectedCount = group.SelectedCount + root.SelectedCount
			for _, id in ipairs(root.SelectionIds) do
				table.insert(group.Ids, id)
			end
		end
	end
	for _, group in ipairs(groups) do
		table.sort(group.Ids)
		local logGroups = {}
		for _, id in ipairs(group.Ids) do
			local distance = mod.ObjectDistances[id]
			if distance and (not group.NearestDistance or distance < group.NearestDistance) then
				group.NearestDistance = distance
			end
			local name = hierarchy.Nodes[id].Name
			if not logGroups[name] then
				logGroups[name] = { Name = name, Ids = {} }
				table.insert(group.LogGroups, logGroups[name])
			end
			table.insert(logGroups[name].Ids, id)
		end
	end
	mod.SortObjectGroups(groups)
	return groups
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
