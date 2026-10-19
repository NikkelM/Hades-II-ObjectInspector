local config = {
	enabled = true,
	sortMode = "Count (most first)",
	fontSize = 20,
	offsetY = -40,
	showTypeNames = false,
}

local configDesc = {
	enabled = "Enable object ID labels without changing type or individual selections",
	sortMode = "Sort order of object types and their IDs in the inspector",
	fontSize = "Font size of world-space object ID labels",
	offsetY = "Vertical offset of labels relative to their objects",
	showTypeNames = "Include the object type alongside its ID",
}

configDescriptions = configDesc

return config, configDesc
