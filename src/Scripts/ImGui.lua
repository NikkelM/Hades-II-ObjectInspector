local windowName = "Object Inspector"
local wasVisible = false
local filter = ""
local showHierarchy = false
local includeMissing = false
local lastRefresh = 0
local lastMapName
local expandedTypes = mod.ExpandedObjectTypes
local expandedCategories = {}
local expandedSources = {}
local expandedRelationships = {}
local relationshipMapName
local expandedHierarchy = {}
local hierarchyExpansionInitialized = false
local rows = {}
local rowGroups
local rowsDirty = true
local rowSelectionVersion = -1
local clipper = rom.ImGuiListClipper.new()

-- #region Object list
local function resetExpandedGroups()
	expandedCategories = {}
	expandedSources = {}
	expandedRelationships = {}
	expandedHierarchy = {}
	hierarchyExpansionInitialized = false
	for name in pairs(expandedTypes) do
		expandedTypes[name] = nil
	end
	for _, group in ipairs(mod.ObjectGroups) do
		if group.SelectedCount > 0 then
			expandedCategories[group.Category] = true
			expandedSources[group.Category .. ":" .. group.Source] = true
			expandedTypes[group.Name] = true
		end
	end
	rowsDirty = true
end

local function getHierarchyGroups(groups)
	local hierarchy = mod.GetObjectHierarchy(groups, includeMissing, filter)
	if hierarchy.Message then
		table.insert(rows, { HierarchyLabel = hierarchy.Message })
	end
	if not hierarchyExpansionInitialized then
		for _, node in pairs(hierarchy.Nodes) do
			if node.Group and mod.IsObjectSelected(node.Name, node.Id) then
				local parent = node.Parent
				while parent and not expandedHierarchy[parent.Id] do
					expandedHierarchy[parent.Id] = true
					parent = parent.Parent
				end
			end
		end
	end
	local hierarchyGroups = mod.GetHierarchyGroups(hierarchy)
	if not hierarchyExpansionInitialized then
		for _, group in ipairs(hierarchyGroups) do
			if group.SelectedCount > 0 then
				expandedCategories[group.Category] = true
				expandedSources[group.Category .. ":" .. group.Source] = true
				expandedTypes[group.Name] = true
			end
		end
		hierarchyExpansionInitialized = true
	end
	return hierarchyGroups
end

local function appendHierarchyRows(group)
	table.insert(rows, { Group = group })
	if not expandedTypes[group.Name] and filter == "" then
		return
	end
	local stack = {}
	for index = #group.Roots, 1, -1 do
		table.insert(stack, { Node = group.Roots[index], Depth = 4 })
	end
	while #stack > 0 do
		local row = table.remove(stack)
		local node = row.Node
		if node.Visible then
			table.insert(rows, { HierarchyNode = node, Depth = row.Depth })
			if filter ~= "" or expandedHierarchy[node.Id] then
				for index = #node.Children, 1, -1 do
					table.insert(stack, { Node = node.Children[index], Depth = row.Depth + 1 })
				end
			end
		end
	end
end

local function appendRelationshipRows(group, id)
	local relationships = mod.GetObjectRelationships(id, group.Name)
	if relationships.Message then
		table.insert(rows, { Group = group, RelationshipLabel = relationships.Message })
	end
	if not relationships.Map then
		return
	end
	for _, section in ipairs({
		{ Label = "Parents", Ids = relationships.Parents },
		{ Label = "Children", Ids = relationships.Children },
		{ Label = "Attached to", Ids = relationships.AttachedTo },
	}) do
		table.insert(rows, {
			Group = group, RelationshipLabel = section.Label .. " (" .. #section.Ids .. ")",
		})
		for _, relatedId in ipairs(section.Ids) do
			table.insert(rows, { Group = group, RelationshipId = relatedId, RelationshipMap = relationships.Map })
		end
	end
end

local function appendObjectRows(group)
	table.insert(rows, { Group = group })
	if expandedTypes[group.Name] then
		local sortMode = config.sortMode
		local ids = group.Ids
		if mod.IsObjectDistanceSort(sortMode) then
			ids = {}
			for _, id in ipairs(group.Ids) do
				table.insert(ids, id)
			end
			table.sort(ids, function(a, b)
				local left, right = mod.ObjectDistances[a], mod.ObjectDistances[b]
				if left ~= right then
					if left == nil then
						return false
					elseif right == nil then
						return true
					elseif sortMode == "Distance (closest first)" then
						return left < right
					end
					return left > right
				end
				return a < b
			end)
		end
		for index = 1, #ids do
			local idIndex = sortMode == "ID (newest first)" and (#ids - index + 1) or index
			local id = ids[idIndex]
			table.insert(rows, { Group = group, Id = id })
			if expandedRelationships[id] then
				appendRelationshipRows(group, id)
			end
		end
	end
end

local function rebuildRows(groups)
	rows = {}
	local inputGroups = groups
	if showHierarchy then
		groups = getHierarchyGroups(groups)
	end
	local categories = {}
	for _, group in ipairs(groups) do
		local category = categories[group.Category]
		if not category then
			category = { Sources = {}, Groups = {}, ObjectCount = 0, SelectedCount = 0 }
			categories[group.Category] = category
		end
		table.insert(category.Groups, group)
		category.ObjectCount = category.ObjectCount + #group.Ids
		category.SelectedCount = category.SelectedCount + group.SelectedCount
		local source = category.Sources[group.Source]
		if not source then
			source = { Groups = {}, ObjectCount = 0, SelectedCount = 0 }
			category.Sources[group.Source] = source
		end
		table.insert(source.Groups, group)
		source.ObjectCount = source.ObjectCount + #group.Ids
		source.SelectedCount = source.SelectedCount + group.SelectedCount
		if group.NearestDistance and (not source.NearestDistance or group.NearestDistance < source.NearestDistance) then
			source.NearestDistance = group.NearestDistance
		end
	end
	for _, name in ipairs({ "Obstacles", "Units", "Other" }) do
		local category = categories[name]
		if category then
			table.insert(rows, {
				Category = name,
				Groups = category.Groups, ObjectCount = category.ObjectCount, SelectedCount = category.SelectedCount,
				Label = name .. " (" .. #category.Groups .. " types, " .. category.ObjectCount
					.. " objects, " .. category.SelectedCount .. " selected)",
			})
			if expandedCategories[name] == true or (showHierarchy and filter ~= "") then
				local sourceNames = {}
				for source in pairs(category.Sources) do
					table.insert(sourceNames, source)
				end
				table.sort(sourceNames, function(a, b)
					if config.sortMode == "Distance (closest first)" then
						local left, right = category.Sources[a].NearestDistance, category.Sources[b].NearestDistance
						if left ~= right then
							if left == nil then
								return false
							elseif right == nil then
								return true
							end
							return left < right
						end
					end
					return a < b
				end)
				for _, sourceName in ipairs(sourceNames) do
					local source = category.Sources[sourceName]
					table.insert(rows, {
						Category = name, Source = sourceName,
						Groups = source.Groups, ObjectCount = source.ObjectCount, SelectedCount = source.SelectedCount,
						Label = sourceName .. " (" .. #source.Groups .. " types, " .. source.ObjectCount
							.. " objects, " .. source.SelectedCount .. " selected)",
					})
					if expandedSources[name .. ":" .. sourceName] == true or (showHierarchy and filter ~= "") then
						for _, group in ipairs(source.Groups) do
							if group.Roots then
								appendHierarchyRows(group)
							else
								appendObjectRows(group)
							end
						end
					end
				end
			end
		end
	end
	rowGroups = inputGroups
	rowSelectionVersion = mod.ObjectSelectionVersion
	rowsDirty = false
end

local function selectGroups(groups, selected)
	if showHierarchy then
		local ids = {}
		for _, group in ipairs(groups) do
			for _, id in ipairs(group.Ids) do
				table.insert(ids, id)
			end
		end
		mod.SelectObjectIds(ids, selected)
	else
		mod.SelectObjectTypes(groups, selected)
	end
end

local function drawObjectDistance(id)
	local distance = mod.ObjectDistances[id]
	local text = distance and string.format("%.0f units to player", distance) or "Distance unavailable"
	local cursorX = rom.ImGui.GetCursorPosX()
	local availableWidth = rom.ImGui.GetContentRegionAvail()
	local textWidth = rom.ImGui.CalcTextSize(text)
	rom.ImGui.SetCursorPosX(math.max(cursorX, cursorX + availableWidth - textWidth))
	rom.ImGui.Text(text)
end

local function drawHierarchyRow(row)
	if row.HierarchyLabel then
		rom.ImGui.AlignTextToFramePadding()
		rom.ImGui.Text(row.HierarchyLabel)
		return
	end
	local node = row.HierarchyNode
	for _ = 1, row.Depth do
		rom.ImGui.Indent()
	end
	rom.ImGui.PushID(node.Id)
	if node.Group then
		local selected, changed = rom.ImGui.Checkbox("##selected",
			#node.SelectionIds > 0 and node.SelectedCount == #node.SelectionIds)
		if changed then
			mod.SelectObjectIds(node.SelectionIds, selected)
		end
		rom.ImGui.SameLine()
		if rom.ImGui.SmallButton("Log") then
			mod.LogObjectRelationships(node.Id, node.Name)
		end
		rom.ImGui.SameLine()
	end
	if #node.Children > 0 then
		local expanded = filter ~= "" or expandedHierarchy[node.Id] == true
		rom.ImGui.SetNextItemOpen(expanded)
		local value = rom.ImGui.TreeNodeEx("##children",
			rom.ImGuiTreeNodeFlags.NoTreePushOnOpen + rom.ImGuiTreeNodeFlags.FramePadding)
		if value ~= expanded and filter == "" then
			expandedHierarchy[node.Id] = value or nil
			rowsDirty = true
		end
		rom.ImGui.SameLine()
	end
	local label = node.Id .. " " .. node.Name
	rom.ImGui.AlignTextToFramePadding()
	if node.Group then
		rom.ImGui.Text(label)
		rom.ImGui.SameLine()
		drawObjectDistance(node.Id)
	else
		rom.ImGui.Text(label .. " (missing)")
	end
	rom.ImGui.PopID()
	for _ = 1, row.Depth do
		rom.ImGui.Unindent()
	end
end

local function drawObjectRow(row)
	if row.HierarchyNode or row.HierarchyLabel then
		drawHierarchyRow(row)
		return
	end
	if not row.Group then
		local key = row.Category .. (row.Source and (":" .. row.Source) or "")
		local states = row.Source and expandedSources or expandedCategories
		local expanded = states[key] == true or (showHierarchy and filter ~= "")
		rom.ImGui.PushID(key)
		if row.Source then
			rom.ImGui.Indent()
		end
		local selected, changed = rom.ImGui.Checkbox("##group", row.ObjectCount > 0 and row.SelectedCount == row.ObjectCount)
		if changed then
			selectGroups(row.Groups, selected)
		end
		rom.ImGui.SameLine()
		rom.ImGui.SetNextItemOpen(expanded)
		local value = rom.ImGui.TreeNodeEx(row.Label .. "###category",
			rom.ImGuiTreeNodeFlags.NoTreePushOnOpen + rom.ImGuiTreeNodeFlags.FramePadding)
		if value ~= expanded and not (showHierarchy and filter ~= "") then
			states[key] = value
			rowsDirty = true
		end
		if row.Source then
			rom.ImGui.Unindent()
		end
		rom.ImGui.PopID()
		return
	end

	local group, id = row.Group, row.Id
	rom.ImGui.Indent()
	rom.ImGui.Indent()
	rom.ImGui.PushID(group.Category .. ":" .. group.Source .. ":" .. group.Name)
	if row.RelationshipLabel or row.RelationshipId then
		rom.ImGui.Indent()
		rom.ImGui.Indent()
		rom.ImGui.Indent()
		rom.ImGui.AlignTextToFramePadding()
		if row.RelationshipId then
			local object = mod.DescribeRelatedObject(row.RelationshipMap, row.RelationshipId)
			local text = object.Id .. " " .. object.Name .. " - " .. object.Status
			if object.LiveName then
				text = text .. " (" .. object.LiveName .. ")"
			end
			if object.ExportedRecord then
				text = text .. " - no map record"
			end
			rom.ImGui.Text(text)
		else
			rom.ImGui.Text(row.RelationshipLabel)
		end
		rom.ImGui.Unindent()
		rom.ImGui.Unindent()
		rom.ImGui.Unindent()
	elseif id then
		rom.ImGui.Indent()
		rom.ImGui.Indent()
		rom.ImGui.PushID(id)
		local selected, changed = rom.ImGui.Checkbox("##selected", mod.IsObjectSelected(group.Name, id))
		if changed then
			mod.SelectObjectId(id, selected)
		end
		rom.ImGui.SameLine()
		if rom.ImGui.SmallButton("Log") then
			mod.LogObjectRelationships(id, group.Name)
		end
		rom.ImGui.SameLine()
		local expanded = expandedRelationships[id] == true
		rom.ImGui.SetNextItemOpen(expanded)
		local value = rom.ImGui.TreeNodeEx("##relationships",
			rom.ImGuiTreeNodeFlags.NoTreePushOnOpen + rom.ImGuiTreeNodeFlags.FramePadding)
		if value ~= expanded then
			expandedRelationships[id] = value or nil
			rowsDirty = true
		end
		rom.ImGui.SameLine()
		rom.ImGui.AlignTextToFramePadding()
		rom.ImGui.Text(group.IdText[id])
		rom.ImGui.PopID()
		rom.ImGui.SameLine()
		drawObjectDistance(id)
		rom.ImGui.Unindent()
		rom.ImGui.Unindent()
	else
		local color = group.Color
		rom.ImGui.TextColored(color[1], color[2], color[3], color[4], "o")
		rom.ImGui.SameLine()
		local selected, changed = rom.ImGui.Checkbox("##type", #group.Ids > 0 and group.SelectedCount == #group.Ids)
		if changed then
			selectGroups({ group }, selected)
		end
		rom.ImGui.SameLine()
		if rom.ImGui.SmallButton("Log") then
			mod.LogObjects(group.LogGroups or { group }, false)
		end
		rom.ImGui.SameLine()
		local typeExpanded = expandedTypes[group.Name] == true or (group.Roots ~= nil and filter ~= "")
		rom.ImGui.SetNextItemOpen(typeExpanded)
		local expanded = rom.ImGui.TreeNodeEx(
			group.Name .. " (" .. #group.Ids .. ", " .. group.SelectedCount .. " selected)###objects",
			rom.ImGuiTreeNodeFlags.NoTreePushOnOpen)
		if expanded ~= typeExpanded and not (group.Roots and filter ~= "") then
			expandedTypes[group.Name] = expanded or nil
			rowsDirty = true
			if expanded then
				if group.Roots then
					mod.RefreshObjectDistances(nil, true)
				else
					mod.RefreshObjectDistances(group)
				end
			end
		end
	end
	rom.ImGui.PopID()
	rom.ImGui.Unindent()
	rom.ImGui.Unindent()
end

local function drawObjectList(groups)
	if relationshipMapName ~= mod.CurrentMapName then
		relationshipMapName = mod.CurrentMapName
		expandedRelationships = {}
		expandedHierarchy = {}
		hierarchyExpansionInitialized = false
		rowsDirty = true
	end
	if rowsDirty or rowGroups ~= groups or rowSelectionVersion ~= mod.ObjectSelectionVersion then
		rebuildRows(groups)
	end
	if rom.ImGui.BeginChild("Object types", 0, 0, true) then
		clipper:Begin(#rows, rom.ImGui.GetFrameHeightWithSpacing())
		while clipper:Step() do
			for index = clipper.DisplayStart + 1, clipper.DisplayEnd do
				drawObjectRow(rows[index])
			end
		end
	end
	rom.ImGui.EndChild()
end
-- #endregion

-- #region Controls
local function drawContents()
	local enabled, changed = rom.ImGui.Checkbox("Show selected IDs", config.enabled)
	if changed then
		config.enabled = enabled
		mod.SyncObjectLabels()
	end

	local value
	value, changed = rom.ImGui.Checkbox("Set player invulnerable", mod.PlayerInvulnerable)
	if changed then
		mod.SetPlayerInvulnerability(value)
	end
	if rom.ImGui.CollapsingHeader("Label settings") then
		local rebuild = false
		value, changed = rom.ImGui.SliderInt("Font size", config.fontSize, 10, 48)
		if changed then
			config.fontSize = value
			rebuild = true
		end
		value, changed = rom.ImGui.SliderInt("Vertical offset", config.offsetY, -200, 100)
		if changed then
			config.offsetY = value
			rebuild = true
		end
		value, changed = rom.ImGui.Checkbox("Include type names", config.showTypeNames)
		if changed then
			config.showTypeNames = value
			rebuild = true
		end
		if rebuild then
			mod.SyncObjectLabels(true)
		end
	end

	rom.ImGui.Text(mod.CurrentMapName .. " | " .. mod.ObjectCount .. " objects | " .. #mod.ObjectGroups .. " types")
	local labelStatus = mod.ObjectLabelCount .. "/" .. mod.ObjectLabelLimit .. " labels"
	if mod.ObjectLabelOmittedCount > 0 then
		labelStatus = labelStatus .. " (" .. mod.ObjectLabelOmittedCount .. " more selected)"
	end
	rom.ImGui.Text(labelStatus)
	if mod.ObjectRefreshRequested then
		rom.ImGui.Text("List out of date")
	end

	value, changed = rom.ImGui.Checkbox("Show Hierarchy only", showHierarchy)
	if changed then
		showHierarchy = value
		hierarchyExpansionInitialized = false
		mod.RefreshObjects()
		mod.RefreshObjectDistances(nil, showHierarchy)
		rowsDirty = true
	end
	if showHierarchy then
		rom.ImGui.SameLine()
		value, changed = rom.ImGui.Checkbox("Include missing", includeMissing)
		if changed then
			includeMissing = value
			hierarchyExpansionInitialized = false
			rowsDirty = true
		end
		rom.ImGui.TextColored(1, 0.75, 0.2, 1,
			"Only obstacles with parent, child or attached-to relationships are shown.")
	end

	rom.ImGui.Text("Sort")
	rom.ImGui.SameLine()
	local sortMode = config.sortMode
	if rom.ImGui.BeginCombo("##sort", sortMode) then
		for _, option in ipairs(mod.ObjectSortModes) do
			if rom.ImGui.Selectable(option, sortMode == option) then
				mod.SetObjectSortMode(option)
			end
		end
		rom.ImGui.EndCombo()
	end

	if rom.ImGui.Button("Refresh list") then
		mod.RefreshObjects()
		mod.RefreshObjectDistances(nil, showHierarchy)
	end
	rom.ImGui.SameLine()
	local showFiltered = rom.ImGui.Button("Show filtered types")
	rom.ImGui.SameLine()
	local logFiltered = rom.ImGui.Button("Log filtered")
	rom.ImGui.SameLine()
	local logSelected = rom.ImGui.Button("Log selected")
	rom.ImGui.SameLine()
	local deselectAll = rom.ImGui.Button("Deselect all")

	rom.ImGui.Text("Filter: type, ID, category or source file")
	filter = rom.ImGui.InputText("##filter", filter, 256)
	local groups = mod.GetObjectGroups(filter)
	local actionGroups = groups
	if showHierarchy and (showFiltered or logFiltered) then
		actionGroups = {}
		local hierarchy = mod.GetObjectHierarchy(groups, includeMissing, filter)
		for _, group in ipairs(mod.GetHierarchyGroups(hierarchy)) do
			for _, logGroup in ipairs(group.LogGroups) do
				table.insert(actionGroups, logGroup)
			end
		end
	end
	if showFiltered then
		selectGroups(actionGroups, true)
	end
	if logFiltered then
		mod.LogObjects(actionGroups, false)
	end
	if logSelected then
		mod.LogObjects(mod.ObjectGroups, true)
	end
	if deselectAll then
		mod.HideAllObjects()
	end
	drawObjectList(groups)
end
-- #endregion

-- #region Registration
rom.gui.add_to_menu_bar(function()
	if rom.ImGui.BeginMenu(windowName) then
		rom.ImGui.Text("Open from the Windows menu")
		if rom.ImGui.Button("Deselect all") then
			mod.HideAllObjects()
		end
		rom.ImGui.EndMenu()
	end
end)

rom.gui.add_always_draw_imgui(function()
	local visible = false
	if rom.gui.is_open() then
		rom.ImGui.SetNextWindowSize(720, 850, rom.ImGuiCond.FirstUseEver)
		-- Managed Begin handles End itself when collapsed and skips Begin when closed
		visible = rom.ImGui.Begin(windowName)
		if visible then
			local opening = not wasVisible
			if opening or lastMapName ~= mod.CurrentMapName then
				mod.RefreshObjects()
				if opening then
					resetExpandedGroups()
				end
				mod.RefreshObjectDistances(nil, showHierarchy)
			end
			drawContents()
			rom.ImGui.End()
		end
	end
	wasVisible = visible
	lastMapName = mod.CurrentMapName

	local now = rom.ImGui.GetTime()
	if now - lastRefresh >= 1 then
		if mod.ObjectRefreshRequested and mod.HasObjectSelection() then
			mod.RefreshObjects()
		elseif mod.HasObjectSelection() then
			mod.SyncObjectLabels()
		end
		lastRefresh = now
	end
end)
-- #endregion
