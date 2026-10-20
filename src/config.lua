local config = {
	enabled = true,
	sortMode = "Count (most first)",
	fontSize = 20,
	offsetY = -40,
	showTypeNames = false,
}

local configDesc = {
	enabled = "Show selected IDs",
	sortMode = "Sort order",
	fontSize = "Label font size",
	offsetY = "Label vertical offset",
	showTypeNames = "Include type names",
}

configDescriptions = configDesc

return config, configDesc
