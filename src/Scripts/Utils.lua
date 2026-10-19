---Prints a table or another printable entity up to a certain depth
---@param t any
---@param maxDepth number|nil
---@param indent number|nil
function mod.PrintTable(t, maxDepth, indent)
	if type(t) ~= "table" then
		rom.log.info(tostring(t))
		return
	end

	indent = indent or 0
	maxDepth = maxDepth or 20
	if indent > maxDepth then
		rom.log.info(string.rep("  ", indent) .. "...")
		return
	end

	local formatting = string.rep("  ", indent)
	for k, v in pairs(t) do
		local keyStr = tostring(k)
		if type(v) == "table" then
			rom.log.info(formatting .. keyStr .. ":")
			mod.PrintTable(v, maxDepth, indent + 1)
		else
			rom.log.info(formatting .. keyStr .. ": " .. tostring(v))
		end
	end
end
