# Object Inspector

Does nothing if you are just playing the game.

The Object Inspector is a Hades II developer mod that can find and show all obstacles and units on any map, and display their ObjectIds in the world.

## Usage

Press `Insert` (or whatever keybind you configured) to open the imgui overlay, then choose `Windows` > `NikkelM-Object_Inspector` > `Object Inspector`.
Sort alphabetically or by item count, ascending or descending, by ID (newest first), or by distance (closest or farthest first).

Use the per-type or individual-ID checkboxes to select objects for world-space ID labels.
Each type has a separate colour assigned for easier identification in-game.

You can also enable type-name labels and adjust the font size and vertical offset.

Expand an object in the viewer to see its parent, child and attached-to details from the map definition.
Enable `Show Hierarchy only` to nest children under parents within the category/source/type groups.

Use `Log filtered`, `Log selected`, or each type's `Log` button to write the corresponding details to the console.
Use each individual ID's `Log` button to write its relationships to the console.
Use `Refresh list` to update discovered objects, including spawned enemies.
The list will always refresh when you reopen the imgui menu.

Selected types are retained across map loads, while individual-ID choices reset at each map transition as the game may re-assign them.
Selections aren't persisted between game restarts.

## AI Usage Disclaimer

This mod contains code created by Generative AI:
- The majority of the mod's core logic was written by Generative AI.
- The following AI model(s) were used to generate content included in this mod: GPT-6.1 Sol
