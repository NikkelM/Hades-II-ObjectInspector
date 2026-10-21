mod.PlayerInvulnerable = false

---@param enabled boolean
function mod.SetPlayerInvulnerability(enabled)
	mod.PlayerInvulnerable = enabled
	local hero = game.CurrentRun and game.CurrentRun.Hero
	if hero and hero.ObjectId then
		if enabled then
			game.SetPlayerInvulnerable(_PLUGIN.guid)
		else
			game.SetPlayerVulnerable(_PLUGIN.guid)
		end
	end
end

game.OnAnyLoad({ function()
	if mod.PlayerInvulnerable then
		mod.SetPlayerInvulnerability(true)
	end
end })

game.OnHit({ function(triggerArgs)
	if mod.PlayerInvulnerable	and triggerArgs.Victim == game.CurrentRun.Hero and game.CurrentRun.Hero.InvulnerableFlags[_PLUGIN.guid] and not triggerArgs.PureDamage and triggerArgs.DamageAmount ~= nil and triggerArgs.DamageAmount > 0 then
		rom.log.warning("Object Inspector | Damage skipped: \"Set player invulnerable\" is enabled in ImGui")
	end
end })
