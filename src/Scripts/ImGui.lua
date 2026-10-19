local windowName = "Object Inspector"
local configDescriptions = mod.ConfigDescriptions
local wasVisible = false
local filter = ""
local sortMode = "Count (most first)"
local lastRefresh = 0
local lastMapName
local expandedTypes = mod.ExpandedObjectTypes
local rows = {}
local rowGroups
local rowsDirty = true
local clipper = rom.ImGuiListClipper.new()
local renderedRows = 0
local drawMilliseconds = 0

-- #region Object list
local function rebuildRows(groups)
	rows = {}
	for _, group in ipairs(groups) do
		table.insert(rows, { Group = group })
		if expandedTypes[group.Name] then
			for index = 1, #group.Ids do
				local idIndex = sortMode == "ID (newest first)" and (#group.Ids - index + 1) or index
				local id = group.Ids[idIndex]
				table.insert(rows, { Group = group, Id = id })
			end
		end
	end
	rowGroups = groups
	rowsDirty = false
end

local function drawObjectRow(row)
	local group, id = row.Group, row.Id
	rom.ImGui.PushID(group.Name)
	if id then
		rom.ImGui.Indent()
		local selected, changed = rom.ImGui.Checkbox(group.IdText[id], mod.IsObjectSelected(group.Name, id))
		if changed then
			mod.SelectObjectId(id, selected)
		end
		rom.ImGui.SameLine()
		rom.ImGui.Text(mod.ObjectDistances[id] or "Distance unavailable - refresh")
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
end

local function drawObjectList(groups)
	if rowsDirty or rowGroups ~= groups then
		rebuildRows(groups)
	end
	renderedRows = 0
	if rom.ImGui.BeginChild("Object types", 0, 0, true) then
		clipper:Begin(#rows, rom.ImGui.GetFrameHeightWithSpacing())
		while clipper:Step() do
			for index = clipper.DisplayStart + 1, clipper.DisplayEnd do
				drawObjectRow(rows[index])
				renderedRows = renderedRows + 1
			end
		end
	end
	rom.ImGui.EndChild()
end
-- #endregion

local function drawTooltip(description)
	if rom.ImGui.IsItemHovered() then
		rom.ImGui.SetNextWindowSize(420, 0)
		rom.ImGui.BeginTooltip()
		rom.ImGui.TextWrapped(description)
		rom.ImGui.EndTooltip()
	end
end

-- #region Controls
local function drawContents()
	local enabled, changed = rom.ImGui.Checkbox("Show selected IDs", config.enabled)
	drawTooltip(configDescriptions.enabled)
	if changed then
		config.enabled = enabled
		mod.SyncObjectLabels()
	end

	local value
	value, changed = rom.ImGui.Checkbox("Refresh when opened", config.autoRefreshOnOpen)
	drawTooltip(configDescriptions.autoRefreshOnOpen)
	if changed then
		config.autoRefreshOnOpen = value
	end
	if rom.ImGui.Button("Refresh now") then
		mod.RefreshObjects(true)
	end
	rom.ImGui.SameLine()
	if rom.ImGui.Button("Deselect all") then
		mod.HideAllObjects()
	end
	rom.ImGui.Text(mod.CurrentMapName .. " | " .. mod.ObjectCount .. " objects | " .. #mod.ObjectGroups .. " types")
	rom.ImGui.Text("Distances to player ID " .. tostring(mod.DistancePlayerId or "(unavailable)") .. " are snapshots")
	if mod.ObjectRefreshRequested then
		rom.ImGui.Text("Map objects changed - refresh to update the list")
	end

	filter = rom.ImGui.InputText("Filter type or ID", filter, 256)
	if rom.ImGui.BeginCombo("Sort", sortMode) then
		for _, option in ipairs({ "Count (most first)", "Count (fewest first)", "Name (A-Z)", "Name (Z-A)", "ID (newest first)" }) do
			if rom.ImGui.Selectable(option, sortMode == option) then
				sortMode = option
			end
		end
		rom.ImGui.EndCombo()
	end

	if rom.ImGui.CollapsingHeader("Performance") then
		local timings = mod.ObjectInspectorTimings
		rom.ImGui.Text(string.format("Draw: %.2f ms | %d / %d rows submitted", drawMilliseconds, renderedRows, #rows))
		rom.ImGui.Text(string.format("Last discovery: %.2f ms | filter/sort: %.2f ms", timings.Refresh, timings.Filter))
		rom.ImGui.Text(string.format("Last distance snapshot: %.2f ms | label sync: %.2f ms", timings.Distances, timings.Labels))
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
		if rebuild then
			mod.SyncObjectLabels(true)
		end
	end

	local groups = mod.GetObjectGroups(filter, sortMode)
	if rom.ImGui.Button("Show filtered types") then
		mod.SelectObjectTypes(groups, true)
	end
	rom.ImGui.SameLine()
	if rom.ImGui.Button("Log filtered") then
		mod.LogObjects(groups, false)
	end
	rom.ImGui.SameLine()
	if rom.ImGui.Button("Log selected") then
		mod.LogObjects(mod.ObjectGroups, true)
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
		rom.ImGui.SetNextWindowSize(720, 600, rom.ImGuiCond.FirstUseEver)
		-- Managed Begin handles End itself when collapsed and skips Begin when closed
		visible = rom.ImGui.Begin(windowName)
		if visible then
			if config.autoRefreshOnOpen and (not wasVisible or lastMapName ~= mod.CurrentMapName) then
				mod.RefreshObjects(true)
			elseif not wasVisible then
				mod.RefreshObjectDistances()
			end
			local startTime = os.clock()
			drawContents()
			drawMilliseconds = (os.clock() - startTime) * 1000
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
