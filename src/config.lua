local config = {
	enabled = true,
	autoRefreshOnOpen = true,
	fontSize = 20,
	offsetY = -40,
	showTypeNames = false,
}

local configDesc = {
	enabled = "Enable object ID labels without changing type or individual selections",
	autoRefreshOnOpen = "Discover active objects whenever the inspector window is opened",
	fontSize = "Font size of world-space object ID labels",
	offsetY = "Vertical offset of labels relative to their objects",
	showTypeNames = "Include the object type alongside its ID",
}

configDescriptions = configDesc

return config, configDesc
