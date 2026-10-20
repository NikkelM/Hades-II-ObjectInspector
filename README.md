# Object Inspector

Does nothing if you are just playing the game.

The Object Inspector is a Hades II developer mod that can find and show all obstacles and units on any map, and display their ObjectIds in the world.

## Usage

Press `Insert` (or whatever keybind you configured) to open the imgui overlay, then choose `Windows` > `NikkelM-Object_Inspector` > `Object Inspector`.
Sort types alphabetically or by item count, ascending or descending.

Use the per-type or individual-ID checkboxes to select objects for world-space ID labels.
Each type has a separate colour assigned for easier identification in-game.

You can also enable type-name labels and adjust the font size and vertical offset.

Use `Log filtered`, `Log selected`, or each type's `Log` button to write the corresponding details to the console.
Use `Refresh list` to update discovered objects, including spawned enemies.
The list will always refresh when you reopen the imgui menu.

Selected types are retained across map loads, while individual-ID choices reset at each map transition as the game may re-assign them.
Selections aren't persisted between game restarts.

## AI Usage Disclaimer

This mod contains code created by Generative AI:
- The majority of the mod's core logic was written by Generative AI, all code was manually reviewed and rewritten following the initial setup.
- The following AI model(s) were used to generate content included in this mod: GPT-6.1 Sol
