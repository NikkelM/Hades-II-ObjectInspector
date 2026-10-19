---@alias ObjectInspectorGroup { Name: string, SearchName: string, SearchText: string, Category: string, Source: string, Ids: integer[], IdText: table<integer, string>, Color: number[], SelectedCount: integer, NearestDistance: number|nil }

-- #region State
local objectTypes = {}
local typeColors = {}
local colorCount = 0
local labels = {}
local labelIds = {}
local selectionOverrides = {}
local selectedObjectIds = {}
local groupsById = {}
local cachedGroups = {}
local cachedFilter
local cachedSortMode
local cachedVersion = -1

mod.ObjectGroups = {}
mod.SelectedObjectTypes = {}
mod.CurrentMapName = "(current map)"
mod.ObjectCount = 0
-- Leave room in the engine's shared 512-entry text-box pool
mod.ObjectLabelLimit = 256
mod.ObjectLabelCount = 0
mod.ObjectLabelOmittedCount = 0
mod.ObjectRefreshRequested = true
mod.ObjectDataVersion = 0
mod.ObjectSelectionVersion = 0
mod.ObjectDistances = {}
mod.ObjectDistanceSort = false
mod.ExpandedObjectTypes = {}
mod.DistancePlayerId = nil
-- #endregion

-- #region Discovery
---@param name string
---@param category string|nil
---@param source string|nil
function mod.RegisterObjectType(name, category, source)
	local objectType = objectTypes[name]
	if not objectType then
		objectType = {}
		objectTypes[name] = objectType
	end
	-- Keep the original definition source when another file overrides the type
	objectType.Category = objectType.Category or category
	objectType.Source = objectType.Source or source
end

local function getObjectTypeColor(name)
	if not typeColors[name] then
		colorCount = colorCount + 1
		local hue = (colorCount * 0.618033988749895) % 1 * 6
		local sector = math.floor(hue)
		local fraction = hue - sector
		local low, falling, rising = 0.3, 1 - 0.7 * fraction, 0.3 + 0.7 * fraction
		local palette = {
			{ 1, rising, low, 1 }, { falling, 1, low, 1 }, { low, 1, rising, 1 },
			{ low, falling, 1, 1 }, { rising, low, 1, 1 }, { 1, low, falling, 1 },
		}
		typeColors[name] = palette[sector + 1]
	end
	return typeColors[name]
end

---@param refreshDistances boolean|nil
function mod.RefreshObjects(refreshDistances)
	for name in pairs(game.ObstacleData) do
		mod.RegisterObjectType(name)
	end
	for name in pairs(game.EnemyData) do
		mod.RegisterObjectType(name)
	end
	local names = {}
	for name in pairs(objectTypes) do
		table.insert(names, name)
	end
	table.sort(names)

	local groupsByName, activeObjects = {}, {}
	-- Query engine type definitions rather than only Lua-initialized objects
	for _, id in ipairs(game.GetIdsByType({ Names = names })) do
		if not labelIds[id] then
			local name = game.GetName({ Id = id })
			if name ~= "" then
				activeObjects[id] = name
				if not groupsByName[name] then
					local objectType = objectTypes[name]
					local category = objectType.Category or "Other"
					local source = objectType.Source or "Uncategorized"
					groupsByName[name] = {
						Name = name, SearchName = name:lower(), Ids = {}, IdText = {},
						Category = category, Source = source,
						SearchText = (name .. " " .. category .. " " .. source):lower(),
						Color = getObjectTypeColor(name), SelectedCount = 0,
					}
				end
				table.insert(groupsByName[name].Ids, id)
				groupsByName[name].IdText[id] = tostring(id)
			end
		end
	end
	mod.ObjectGroups = {}
	mod.ObjectCount = 0
	groupsById = {}
	selectedObjectIds = {}
	for _, group in pairs(groupsByName) do
		table.sort(group.Ids)
		table.insert(mod.ObjectGroups, group)
		mod.ObjectCount = mod.ObjectCount + #group.Ids
		for _, id in ipairs(group.Ids) do
			groupsById[id] = group
			local distance = mod.ObjectDistances[id]
			if distance and (not group.NearestDistance or distance < group.NearestDistance) then
				group.NearestDistance = distance
			end
			if mod.IsObjectSelected(group.Name, id) then
				selectedObjectIds[id] = group
				group.SelectedCount = group.SelectedCount + 1
			end
		end
	end
	table.sort(mod.ObjectGroups, function(a, b)
		return a.Name < b.Name
	end)
	for id in pairs(selectionOverrides) do
		if not activeObjects[id] then
			selectionOverrides[id] = nil
		end
	end
	for id in pairs(mod.ObjectDistances) do
		if not activeObjects[id] then
			mod.ObjectDistances[id] = nil
		end
	end
	mod.ObjectDataVersion = mod.ObjectDataVersion + 1
	mod.ObjectRefreshRequested = false
	mod.SyncObjectLabels()
	if refreshDistances then
		mod.RefreshObjectDistances()
	end
end

---@param openedGroup ObjectInspectorGroup|nil
function mod.RefreshObjectDistances(openedGroup)
	local hero = game.CurrentRun and game.CurrentRun.Hero
	local playerId = hero and hero.ObjectId
	if not openedGroup or mod.DistancePlayerId ~= playerId then
		mod.ObjectDistances = {}
		for _, group in ipairs(mod.ObjectGroups) do
			group.NearestDistance = nil
		end
	end
	mod.DistancePlayerId = playerId
	if mod.DistancePlayerId then
		for _, group in ipairs(openedGroup and { openedGroup } or mod.ObjectGroups) do
			if openedGroup or mod.ObjectDistanceSort or mod.ExpandedObjectTypes[group.Name] then
				group.NearestDistance = nil
				for _, id in ipairs(group.Ids) do
					mod.ObjectDistances[id] = nil
					if game.GetName({ Id = id }) == group.Name then
						local distance = game.GetDistance({
							Id = id, DestinationId = mod.DistancePlayerId,
						})
						mod.ObjectDistances[id] = distance
						if not group.NearestDistance or distance < group.NearestDistance then
							group.NearestDistance = distance
						end
					end
				end
			end
		end
	end
	cachedVersion = -1
end

---@param filter string
---@param sortMode string
---@return ObjectInspectorGroup[]
function mod.GetObjectGroups(filter, sortMode)
	filter = filter:lower()
	if filter == cachedFilter and sortMode == cachedSortMode and cachedVersion == mod.ObjectDataVersion then
		return cachedGroups
	end
	local result = {}
	local distanceSort = sortMode == "Distance (closest first)" or sortMode == "Distance (farthest first)"
	local searchIds = filter:match("^%d+$") ~= nil
	for _, group in ipairs(mod.ObjectGroups) do
		local matches = group.SearchText:find(filter, 1, true) ~= nil
		if not matches and searchIds then
			for _, id in ipairs(group.Ids) do
				if group.IdText[id]:find(filter, 1, true) then
					matches = true
					break
				end
			end
		end
		if matches then
			table.insert(result, group)
		end
	end
	table.sort(result, function(a, b)
		if distanceSort and a.NearestDistance ~= b.NearestDistance then
			if a.NearestDistance == nil then
				return false
			elseif b.NearestDistance == nil then
				return true
			elseif sortMode == "Distance (closest first)" then
				return a.NearestDistance < b.NearestDistance
			end
			return a.NearestDistance > b.NearestDistance
		elseif sortMode == "ID (newest first)" and a.Ids[#a.Ids] ~= b.Ids[#b.Ids] then
			return a.Ids[#a.Ids] > b.Ids[#b.Ids]
		elseif sortMode == "Count (most first)" and #a.Ids ~= #b.Ids then
			return #a.Ids > #b.Ids
		elseif sortMode == "Count (fewest first)" and #a.Ids ~= #b.Ids then
			return #a.Ids < #b.Ids
		elseif sortMode == "Name (Z-A)" then
			local left, right = a.SearchName, b.SearchName
			return left > right or (left == right and a.Name > b.Name)
		end
		local left, right = a.SearchName, b.SearchName
		return left < right or (left == right and a.Name < b.Name)
	end)
	cachedGroups, cachedFilter, cachedSortMode = result, filter, sortMode
	cachedVersion = mod.ObjectDataVersion
	return cachedGroups
end
-- #endregion

-- #region Selection
---@param name string
---@param id integer
---@return boolean
function mod.IsObjectSelected(name, id)
	if selectionOverrides[id] ~= nil then
		return selectionOverrides[id]
	end
	return mod.SelectedObjectTypes[name] == true
end

---@param groups ObjectInspectorGroup[]
---@param selected boolean
function mod.SelectObjectTypes(groups, selected)
	for _, group in ipairs(groups) do
		mod.SelectedObjectTypes[group.Name] = selected or nil
		group.SelectedCount = selected and #group.Ids or 0
		for _, id in ipairs(group.Ids) do
			selectionOverrides[id] = nil
			selectedObjectIds[id] = selected and group or nil
		end
	end
	mod.ObjectSelectionVersion = mod.ObjectSelectionVersion + 1
	mod.SyncObjectLabels()
end

---@param id integer
---@param selected boolean
function mod.SelectObjectId(id, selected)
	local group = groupsById[id]
	local wasSelected = mod.IsObjectSelected(group.Name, id)
	selectionOverrides[id] = selected
	selectedObjectIds[id] = selected and group or nil
	if wasSelected ~= selected then
		group.SelectedCount = group.SelectedCount + (selected and 1 or -1)
	end
	mod.ObjectSelectionVersion = mod.ObjectSelectionVersion + 1
	mod.SyncObjectLabels()
end

function mod.HideAllObjects()
	mod.SelectedObjectTypes = {}
	selectionOverrides = {}
	selectedObjectIds = {}
	for _, group in ipairs(mod.ObjectGroups) do
		group.SelectedCount = 0
	end
	mod.ObjectSelectionVersion = mod.ObjectSelectionVersion + 1
	mod.ClearObjectLabels()
end

---@return boolean
function mod.HasObjectSelection()
	return next(mod.SelectedObjectTypes) ~= nil or next(selectedObjectIds) ~= nil
end
-- #endregion

-- #region Labels
local function destroyObjectLabel(id, label)
	-- Release the text slot immediately rather than waiting for obstacle disposal
	game.DestroyTextBox({ Id = label.AnchorId })
	game.Destroy({ Id = label.AnchorId })
	labelIds[label.AnchorId] = nil
	labels[id] = nil
end

function mod.ClearObjectLabels()
	for id, label in pairs(labels) do
		destroyObjectLabel(id, label)
	end
	labels = {}
	labelIds = {}
	mod.ObjectLabelCount = 0
	mod.ObjectLabelOmittedCount = 0
end

function mod.ResetObjectInspectorMap()
	-- The engine has already torn down the old map, so its IDs must not be destroyed again
	labels = {}
	labelIds = {}
	selectionOverrides = {}
	selectedObjectIds = {}
	groupsById = {}
	mod.ObjectGroups = {}
	mod.ObjectDistances = {}
	mod.DistancePlayerId = nil
	mod.ObjectDataVersion = mod.ObjectDataVersion + 1
	cachedGroups = {}
	cachedVersion = -1
	mod.ObjectCount = 0
	mod.ObjectLabelCount = 0
	mod.ObjectLabelOmittedCount = 0
	mod.CurrentMapName = "(loading map)"
	mod.ObjectRefreshRequested = true
end

---@param rebuild boolean|nil
function mod.SyncObjectLabels(rebuild)
	local previousOmittedCount = mod.ObjectLabelOmittedCount
	if rebuild or not config.enabled then
		mod.ClearObjectLabels()
	end
	if not config.enabled then
		return
	end

	local activeIds = {}
	for id, group in pairs(selectedObjectIds) do
		if game.GetName({ Id = id }) == group.Name then
			table.insert(activeIds, id)
		end
	end
	table.sort(activeIds)
	local labelCount = math.min(#activeIds, mod.ObjectLabelLimit)
	local wantedLabels = {}
	for index = 1, labelCount do
		wantedLabels[activeIds[index]] = true
	end
	for id, label in pairs(labels) do
		if not wantedLabels[id] then
			destroyObjectLabel(id, label)
		end
	end
	for index = 1, labelCount do
		local id = activeIds[index]
		local group = selectedObjectIds[id]
		if not labels[id] then
			local anchorId = game.SpawnObstacle({
				Name = "BlankObstacleNoTimeModifier", Group = "Combat_UI_Backing",
				DestinationId = id, TriggerOnSpawn = false,
			})
			assert(anchorId and anchorId > 0, "Object Inspector could not create a label anchor")
			labels[id] = { AnchorId = anchorId }
			labelIds[anchorId] = true
			game.Attach({ Id = anchorId, DestinationId = id, OffsetY = config.offsetY })
			game.CreateTextBox({
				Id = anchorId,
				Text = config.showTypeNames
					and (group.Name .. (config.typeNameOnSeparateLine and "\n" or " ") .. id) or tostring(id),
				Font = "P22UndergroundSCHeavy", FontSize = config.fontSize,
				Justification = "CENTER", Color = group.Color,
				OutlineThickness = 2, OutlineColor = { 0, 0, 0, 1 },
				ShadowColor = { 0, 0, 0, 1 }, ShadowAlpha = 1,
				ShadowOffset = { 0, 2 },
				DataProperties = { LocationZWithOwner = true },
			})
		end
	end
	mod.ObjectLabelCount = labelCount
	mod.ObjectLabelOmittedCount = #activeIds - labelCount
	if mod.ObjectLabelOmittedCount > 0 and previousOmittedCount == 0 then
		rom.log.warning("Object Inspector | World label limit " .. mod.ObjectLabelLimit
			.. " reached: " .. mod.ObjectLabelOmittedCount .. " additional selected IDs have no label"
			.. " (lowest IDs shown first); selection and logging are unaffected")
	end
end
-- #endregion

-- #region Console
---@param groups ObjectInspectorGroup[]
---@param selectedOnly boolean
function mod.LogObjects(groups, selectedOnly)
	rom.log.info("Object Inspector | " .. mod.CurrentMapName)
	local count = 0
	for _, group in ipairs(groups) do
		local ids = {}
		local groupCount = 0
		for _, id in ipairs(group.Ids) do
			if (not selectedOnly or mod.IsObjectSelected(group.Name, id))
				and game.GetName({ Id = id }) == group.Name then
				local location = game.GetLocation({ Id = id })
				ids[id] = { X = location.X, Y = location.Y }
				groupCount = groupCount + 1
			end
		end
		if groupCount > 0 then
			rom.log.info(group.Name .. " (" .. groupCount .. ")")
			mod.PrintTable(ids)
			count = count + groupCount
		end
	end
	rom.log.info("Object Inspector | " .. count .. " active object IDs logged")
end
-- #endregion
