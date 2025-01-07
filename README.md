# HudHelper
 A compact feature-filled HUD rendering tool.

## Features

- Painstakingly manually positioning to support all different HUD layouts in Repentance and Repentance+, with some assistance from REPENTOGON, but not needed for the library
- Can render for any corner of the HUD, hearts, actives, pocket items, and extra HUD elements, the last of which can automatically reposition to make room for multiple extra HUD elements
- Accounts for J&E, existing vanilla HUD elements, all co-op players, and even strawmen if you render health
- EID support to automatically reposition it with any of your extra HUD elements
- Works in tandem with multiple mods using the HudHelper tool so there's no overlap

## Installation
Setting up the library is simple. If you look at the main code of this repository, you'll see a main.lua that should work as intended. Just to put it within steps though:
1. First, [download the latest release, found here.](https://github.com/BenevolusGoat/hud-helper/wiki/) (Doesn't exist yet!)
2. Place the file anywhere in your mod. I recommend putting it in a neatly organized place, such as in a folder named "utility" that's within a greater "scripts" folder.
3. In your `main.lua` file, `include` the file. HudHelper is a global, so you can access it at any time with "HudHelper".
4. Within the hud_helper.lua file, change out the "HudHelperExample" variable with a global for your mod. If you don't have a global, it's merely used as a name identifier, and you can go to line 41 to change the string to "YourModNameHere's HudHelper".
5. If you plan on having your mod NOT exclusive to REPENTOGON, you can take the empty shader within this repository's content/shaders.xml and change its name to use the name of the mod in some form, then change out "HudHelperEmptyShader" with that new name. This is what allows HudHelper to render above the HUD

## To find out how to use, please open the wiki
https://github.com/BenevolusGoat/hud-helper/wiki
