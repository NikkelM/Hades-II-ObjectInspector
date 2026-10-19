local windowName = "Object Inspector"
local configDescriptions = mod.ConfigDescriptions
local wasVisible = false
local filter = ""
local sortMode = config.sortMode
mod.ObjectDistanceSort = sortMode == "Distance (closest first)" or sortMode == "Distance (farthest first)"
local lastRefresh = 0
local lastMapName
local expandedTypes = mod.ExpandedObjectTypes
local expandedCategories = {}
local expandedSources = {}
local rows = {}
local rowGroups
local rowsDirty = true
local rowSelectionVersion = -1
local clipper = rom.ImGuiListClipper.new()

local function drawTooltip(description)
	if rom.ImGui.IsItemHovered() then
		rom.ImGui.SetNextWindowSize(420, 0)
		rom.ImGui.BeginTooltip()
		rom.ImGui.TextWrapped(description)
		rom.ImGui.EndTooltip()
	end
end

-- #region Object list
local function resetExpandedGroups()
	expandedCategories = {}
	expandedSources = {}
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

local function appendObjectRows(group)
	table.insert(rows, { Group = group })
	if expandedTypes[group.Name] then
		local ids = group.Ids
		if mod.ObjectDistanceSort then
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
		end
	end
end

local function rebuildRows(groups)
	rows = {}
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
			if expandedCategories[name] == true then
				local sourceNames = {}
				for source in pairs(category.Sources) do
					table.insert(sourceNames, source)
				end
				table.sort(sourceNames)
				for _, sourceName in ipairs(sourceNames) do
					local source = category.Sources[sourceName]
					table.insert(rows, {
						Category = name, Source = sourceName,
						Groups = source.Groups, ObjectCount = source.ObjectCount, SelectedCount = source.SelectedCount,
						Label = sourceName .. " (" .. #source.Groups .. " types, " .. source.ObjectCount
							.. " objects, " .. source.SelectedCount .. " selected)",
					})
					if expandedSources[name .. ":" .. sourceName] == true then
						for _, group in ipairs(source.Groups) do
							appendObjectRows(group)
						end
					end
				end
			end
		end
	end
	rowGroups = groups
	rowSelectionVersion = mod.ObjectSelectionVersion
	rowsDirty = false
end

local function drawObjectRow(row)
	if not row.Group then
		local key = row.Category .. (row.Source and (":" .. row.Source) or "")
		local states = row.Source and expandedSources or expandedCategories
		local expanded = states[key] == true
		rom.ImGui.PushID(key)
		if row.Source then
			rom.ImGui.Indent()
		end
		local selected, changed = rom.ImGui.Checkbox("##group", row.SelectedCount == row.ObjectCount)
		drawTooltip("Select or deselect all types in this group matching the current filter")
		if changed then
			mod.SelectObjectTypes(row.Groups, selected)
		end
		rom.ImGui.SameLine()
		rom.ImGui.SetNextItemOpen(expanded)
		local value = rom.ImGui.TreeNodeEx(row.Label .. "###category",
			rom.ImGuiTreeNodeFlags.NoTreePushOnOpen + rom.ImGuiTreeNodeFlags.FramePadding)
		if value ~= expanded then
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
	rom.ImGui.PushID(group.Name)
	if id then
		rom.ImGui.Indent()
		local selected, changed = rom.ImGui.Checkbox(group.IdText[id], mod.IsObjectSelected(group.Name, id))
		if changed then
			mod.SelectObjectId(id, selected)
		end
		rom.ImGui.SameLine()
		local distance = mod.ObjectDistances[id]
		local text = distance and string.format("%.0f units to player", distance) or "Distance unavailable - refresh"
		local cursorX = rom.ImGui.GetCursorPosX()
		local availableWidth = rom.ImGui.GetContentRegionAvail()
		local textWidth = rom.ImGui.CalcTextSize(text)
		rom.ImGui.SetCursorPosX(math.max(cursorX, cursorX + availableWidth - textWidth))
		rom.ImGui.Text(text)
		rom.ImGui.Unindent()
	else
		local color = group.Color
		rom.ImGui.TextColored(color[1], color[2], color[3], color[4], "o")
		rom.ImGui.SameLine()
		local selected, changed = rom.ImGui.Checkbox("##type", group.SelectedCount == #group.Ids)
		if changed then
			mod.SelectObjectTypes({ group }, selected)
		end
		rom.ImGui.SameLine()
		if rom.ImGui.SmallButton("Log") then
			mod.LogObjects({ group }, false)
		end
		rom.ImGui.SameLine()
		rom.ImGui.SetNextItemOpen(expandedTypes[group.Name] == true)
		local expanded = rom.ImGui.TreeNodeEx(
			group.Name .. " (" .. #group.Ids .. ", " .. group.SelectedCount .. " selected)###objects",
			rom.ImGuiTreeNodeFlags.NoTreePushOnOpen)
		if expanded ~= (expandedTypes[group.Name] == true) then
			expandedTypes[group.Name] = expanded or nil
			rowsDirty = true
			if expanded then
				mod.RefreshObjectDistances(group)
			end
		end
	end
	rom.ImGui.PopID()
	rom.ImGui.Unindent()
	rom.ImGui.Unindent()
end

local function drawObjectList(groups)
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
	drawTooltip(configDescriptions.enabled)
	if changed then
		config.enabled = enabled
		mod.SyncObjectLabels()
	end

	local value
	value, changed = rom.ImGui.Checkbox("Set player invulnerable", mod.PlayerInvulnerable)
	drawTooltip("Session-only debug setting: use normal player invulnerability and log blocked hits; pure damage can bypass it")
	if changed then
		mod.SetPlayerInvulnerability(value)
	end
	if rom.ImGui.CollapsingHeader("Label settings") then
		local rebuild = false
		value, changed = rom.ImGui.SliderInt("Font size", config.fontSize, 10, 48)
		drawTooltip(configDescriptions.fontSize)
		if changed then
			config.fontSize = value
			rebuild = true
		end
		value, changed = rom.ImGui.SliderInt("Vertical offset", config.offsetY, -200, 100)
		drawTooltip(configDescriptions.offsetY)
		if changed then
			config.offsetY = value
			rebuild = true
		end
		value, changed = rom.ImGui.Checkbox("Include type names", config.showTypeNames)
		drawTooltip(configDescriptions.showTypeNames)
		if changed then
			config.showTypeNames = value
			rebuild = true
		end
		value, changed = rom.ImGui.Checkbox("Type name and ID on separate lines", config.typeNameOnSeparateLine)
		drawTooltip(configDescriptions.typeNameOnSeparateLine)
		if changed then
			config.typeNameOnSeparateLine = value
			rebuild = true
		end
		if rebuild then
			mod.SyncObjectLabels(true)
		end
	end

	rom.ImGui.Text("Room " .. mod.CurrentMapName .. " has " .. mod.ObjectCount .. " objects with " .. #mod.ObjectGroups .. " types")
	local labelStatus = mod.ObjectLabelCount .. "/" .. mod.ObjectLabelLimit .. " labels are shown, limited by the engine"
	if mod.ObjectLabelOmittedCount > 0 then
		labelStatus = labelStatus .. " (" .. mod.ObjectLabelOmittedCount .. " additional objects selected)"
	end
	rom.ImGui.Text(labelStatus)
	drawTooltip("The world label cap leaves room in the game's shared text-box pool; lowest selected IDs are shown first, and selection and console logging remain unlimited")
	if mod.ObjectRefreshRequested then
		rom.ImGui.Text("Map objects changed - refresh to update the list")
	end

	rom.ImGui.Text("Sort")
	rom.ImGui.SameLine()
	if rom.ImGui.BeginCombo("##sort", sortMode) then
		for _, option in ipairs({ "Count (most first)", "Count (fewest first)", "Name (A-Z)", "Name (Z-A)", "ID (newest first)", "Distance (closest first)", "Distance (farthest first)" }) do
			if rom.ImGui.Selectable(option, sortMode == option) then
				sortMode = option
				config.sortMode = option
				local distanceSort = option == "Distance (closest first)" or option == "Distance (farthest first)"
				local needsSnapshot = distanceSort and not mod.ObjectDistanceSort
				mod.ObjectDistanceSort = distanceSort
				if needsSnapshot then
					mod.RefreshObjectDistances()
				end
			end
		end
		rom.ImGui.EndCombo()
	end

	if rom.ImGui.Button("Refresh list") then
		mod.RefreshObjects(true)
	end
	rom.ImGui.SameLine()
	local showFiltered = rom.ImGui.Button("Show filtered types")
	rom.ImGui.SameLine()
	local logFiltered = rom.ImGui.Button("Log filtered")
	rom.ImGui.SameLine()
	local logSelected = rom.ImGui.Button("Log selected")
	rom.ImGui.SameLine()
	local deselectAll = rom.ImGui.Button("Deselect all")

	rom.ImGui.Text("Filter by type, ID, category or source file:")
	filter = rom.ImGui.InputText("##filter", filter, 256)
	local groups = mod.GetObjectGroups(filter, sortMode)
	if showFiltered then
		mod.SelectObjectTypes(groups, true)
	end
	if logFiltered then
		mod.LogObjects(groups, false)
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
		rom.ImGui.Text("Open the inspector from the Windows menu")
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
				mod.RefreshObjectDistances()
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
