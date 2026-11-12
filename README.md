# rainworld ui

A single-file Luau interface library for Roblox, built to match the "rainworld" Figma design pixel for pixel: window, tabs, sections, toggles, sliders, dropdowns, buttons, colour pickers with alpha, keybinds, a top bar, watermark, keybind list, notifications, an ESP preview window backed by a `ViewportFrame`, a script list window and a theme window.

- `library.lua` is the library.
- `example.lua` rebuilds the design and shows every element.

## Loading

```lua
local library = loadstring(game:HttpGet("https://raw.githubusercontent.com/lavababsbs-lab/Lhi/refs/heads/hoplite/samos-66ff67d0/library.lua"))()
```

The URL points at the branch this was written on; change it if you move the file to another branch.

The library also runs from a `LocalScript` or `ModuleScript`. Custom fonts and files on disk need `writefile`, `readfile`, `isfile` and `getcustomasset`; without them it falls back to built-in fonts and keeps configs and themes in memory for the session.

Running the library a second time unloads the first copy.

## Quick start

```lua
library:dock({ name = "rainworld.club" }) -- top bar; create it first so windows get a toggle
local window = library:window({ name = "rainworld" })
library:watermark({ name = "rainworld.club | $$$" })
library:keybind_list({ dock = false })

local tab = window:tab({ name = "aimbot" })
local section = tab:section({ name = "aim assist", side = "left" })

local enabled = section:toggle({ name = "enabled", flag = "aim_enabled", default = true })
enabled:colorpicker({ flag = "aim_color", color = Color3.fromRGB(153, 129, 188) })
enabled:keybind({ name = "aim assist", flag = "aim_bind" })

section:slider({ name = "speed", flag = "aim_speed", min = 0, max = 100, default = 10, suffix = "%" })
section:dropdown({ name = "smoothing", flag = "aim_smoothing", items = { "linear", "sine" }, default = "linear" })
section:button({ name = "button", callback = function() library:notification({ text = "pressed" }) end })

window:settings() -- configs and interface options in their own tab
library:load_autoload()

print(library.flags.aim_speed) --> 10
```

Every constructor takes one options table. Elements with a `flag` write their value to `library.flags[flag]`, are saved in configs, and are reachable as `library.options[flag]`. Methods on returned objects work with `.` or `:`.

The menu key is `RightShift` by default (`library.menu_key`, rebindable in the settings tab).

## Layout

| Call | Options |
| --- | --- |
| `library:window(o)` | `name`, `size` (387x554), `position`, `min_size`, `resizable`, `animate_title` (`"none"`, `"shimmer"`, `"wave"`), `dock`, `dock_name` |
| `window:tab(o)` | `name`, `columns` (2) |
| `tab:section(o)` | `name`, `side` (`"left"`, `"right"` or a column number), `fill`, `size` (0-1 of the page height), `draggable` |
| `window:settings(o)` | `name` for a new tab, or `tab` to add the sections to an existing one |

The window is dragged by any empty area and resized from its bottom-right corner. Sections are dragged by their title into another slot or column (`library.draggable_sections = false` turns that off). The last section of a column stretches to the bottom of the page unless it has `fill = false`.

`window:set_size(Vector2)`, `window:set_title(text)`, `window:set_title_animation(mode)`, `window:set_visible(bool)`, `tab.open_tab()`.

## Elements

| Call | Options | `flags[flag]` | Methods |
| --- | --- | --- | --- |
| `section:toggle(o)` | `name`, `flag`, `default`, `callback(bool)` | `boolean` | `set`, `get`, `colorpicker`, `keybind`, `set_visible` |
| `section:slider(o)` | `name`, `flag`, `min`, `max`, `interval`, `default`, `suffix`, `callback(number)` | `number` | `set`, `get`, `set_visible` |
| `section:slider(o)` with `default = { low, high }` | same | `{ low, high }` | same |
| `section:dropdown(o)` | `name`, `flag`, `items`, `default`, `multi`, `callback(value)` | item, or a list with `multi` | `set`, `get`, `refresh_options(items)`, `set_visible` |
| `section:button(o)` | `name`, `callback()` | | `set(name)`, `set_visible` |
| `section:button_row({ { name, callback }, ... })` | | | |
| `section:textbox(o)` | `name`, `flag`, `default`, `placeholder`, `live`, `callback(text)` | `string` | `set`, `get`, `set_visible` |
| `section:label(o)` | `name`, `wrap` | | `set(text)`, `set_visible` |
| `section:colorpicker(o)` | `name`, `flag`, `color`, `alpha`, `callback(Color3, alpha)` | `{ color, alpha, transparency }` | `set(color, alpha)`, `get` |
| `section:keybind(o)` | `name`, `flag`, `key`, `mode`, `callback(active)`, `list`, `hidden` | `{ key, mode, active }` | `set`, `set_mode`, `get`, `listen` |

- **Colour picker**: hue bar, saturation/value square, alpha bar and a hex box that accepts `#RRGGBB` or `#RRGGBBAA`. `toggle:colorpicker(o)` puts the swatch on the toggle's row; several can share a row.
- **Keybind**: left click the `[key]` readout to rebind (escape clears it, clicking again cancels), right click for the mode: `toggle`, `hold` or `always`. Keys and mouse buttons both work. `hidden = true` keeps the readout off the row until a key is bound; right click the toggle to bind it. `list = false` keeps it out of the keybind list.
- **Slider**: drag anywhere on the track, or use the `-` / `+` ends to step by `interval`.

## Floating pieces

| Call | Notes |
| --- | --- |
| `library:dock(o)` | Top bar. Every window gets a toggle (accent = shown, white = hidden); `dock:add({ name, default, callback, toggle })` adds your own. |
| `library:watermark(o)` | `name` is the brand; `text` is a string or a function (it receives the fps) returning the stats text (default: memory, fps, ping), refreshed every `rate` seconds. |
| `library:keybind_list(o)` | Lists every keybind as `name - [key]`; active ones use the accent. `active_only = true` lists only active binds. |
| `library:notification(o)` | `text`, `time`. Click to dismiss. |
| `library:esp_preview(o)` | See below. |
| `library:list(o)` | A list window with per-row action buttons: `name`, `items`, `actions = { { name, callback(item) } }`, `callback(item)`. Methods: `set_items`, `add`, `remove`, `select`, `get`. |
| `library:theme_window(o)` | A colour swatch for every theme key, plus save and reset. |

The windows, the watermark and the keybind list take `position`, `visible` and `dock = false` (no toggle in the top bar), and the windows can be resized from their bottom-right corner. The watermark and keybind list stay on screen when the menu is closed.

### ESP preview

```lua
local preview = library:esp_preview({ name = "esp preview" })
preview.set("box", true, Color3.new(1, 1, 1)) -- box, name, healthbar, distance, flags
preview.set_health(0.6)
preview.set_flags({ "flag one", "flag two" })
preview.set_model(some_model) -- show a custom model; set_model(nil) goes back to your character
```

The window holds a `ViewportFrame` with a `WorldModel` and its own camera. It shows a copy of your character (rebuilt on respawn) or any model you hand it, fits the camera to the model's bounding box, and lets you turn the model by dragging. The overlay elements are positioned from that bounding box and are hidden until you enable them. `preview.viewport`, `preview.world` and `preview.camera` are exposed for anything custom.

## Configs

```lua
library:save_config("legit")   library:read_config("legit")   library:delete_config("legit")
library:list_configs()         library:set_autoload("legit")   library:load_autoload()
library:get_config()           library:load_config(json)
```

Configs are JSON files in `rainworld/configs`. `window:settings()` adds the interface for all of this.

## Themes

Every colour comes from `library.theme` and updates live:

```lua
library:set_accent(Color3.fromRGB(255, 120, 160)) -- re-tints the whole accent family
library:update_theme("window_background", Color3.fromRGB(10, 10, 14))
library:save_theme()   library:reset_theme()   library:load_theme(json_or_table)
```

`library:update_theme("accent", color)` does the same as `set_accent`, so scripts that only know that call still recolour the whole menu. A saved theme (`rainworld/theme.json`) is applied on the next load.

## Coming from similar libraries

The structure follows the snake_case convention of i77lhm's libraries: `library:window` → `window:tab` → `tab:section` → elements, one lowercase options table per call, values in `library.flags`, and setters that can be called with a dot (`toggle.set(true)`). A few extras exist only to make porting easier:

- Option aliases: `title` for a window name, `minimum` / `maximum` / `decimal` on sliders, `default` for a colour picker's colour or a keybind's key, `text` on buttons, `placeholdertext` / `holder` on textboxes, `display` or `keybind_name` for the name a keybind shows in the list.
- A colour picker or keybind created on a section without a `name` attaches to the toggle made just before it.
- `window.set_menu_visibility(bool)`, `window.toggle_list(bool)` and `window.toggle_watermark(bool)`.

Differences to watch for when porting a script: colour flags are `{ color, alpha, transparency }` and keybind flags `{ key, mode, active }`, all lowercase; there is no `tab:column`, a section picks its column with `side`; and configs are saved with `save_config(name)` (writing `get_config()` to a file yourself still works).

## Animations

```lua
library:set_animation({ enabled = true, style = "spring", speed = 1 }) -- "smooth", "spring", "elastic"
```

`smooth` eases without overshoot; `spring` and `elastic` overshoot on anything that moves or resizes. Colours always ease smoothly. With `enabled = false` everything is instant. The settings tab exposes all three options and the title animation, and remembers them in `rainworld/settings.json` along with the menu key and which windows you hid from the top bar.

## Unloading

`library:unload()` destroys the interface and disconnects everything the library created. `library:on_unload(callback)` runs your own cleanup first. `library:stats()` reports live bindings, tweens, per-frame jobs and connections if you want to check for leaks.

Per-frame work is limited to what is on screen: one shared `RenderStepped` connection serves the watermark counter, drags, an open popup, the title wave and a spinning preview, and disconnects when none of them is running.

## Matching the design

Sizes, offsets and colours are taken from the Figma file. Two things are worth knowing if you change them:

- **Text sizes.** Figma sizes text by the em square and Roblox by the font's full glyph box, so each Figma size is multiplied by that ratio (`library.text_sizes`). The results are fractional on purpose.
- **Fonts.** OpenSansPX and Tahoma Bold are downloaded once from [i77lhm/storage](https://github.com/i77lhm/storage) into `rainworld/fonts` (`library.font_sources`). They are not part of this repository.

Design decisions that go beyond the drawing: the slider fill is proportional to its value, the colour picker gained the alpha bar and hex box the design notes ask for, configs live in the settings tab rather than the top bar, and the theme editor is its own window.
