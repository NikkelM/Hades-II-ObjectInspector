game.OnPreThingCreation({ function()
	mod.ResetObjectInspectorMap()
end })

game.OnAnyLoad({ function(args)
	mod.CurrentMapName = args.name
	mod.ObjectRefreshRequested = true
end })

game.OnSpawn({ function(args)
	mod.RegisterObjectType(args.name)
	mod.ObjectRefreshRequested = true
end })
