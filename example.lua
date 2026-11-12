--[[
	rainworld ui : example

	Builds the menu from the Figma design (top bar, main window, watermark,
	keybind list, esp preview, lua list, theme window) and shows every element.
	Nothing here touches the game: the callbacks only print or drive the preview.
]]

local library = loadstring(
	game:HttpGet("https://raw.githubusercontent.com/lavababsbs-lab/Lhi/refs/heads/hoplite/samos-66ff67d0/library.lua")
)()
local flags = library.flags

-- The top bar comes first so every window after it gets a toggle there.
library:dock({ name = "rainworld.club" })

local window = library:window({ name = "rainworld" })
library:watermark({ name = "rainworld.club | $$$" })
library:keybind_list({ dock = false })
local preview = library:esp_preview({ name = "esp preview" })

--// lua window: scripts stored in rainworld/lua
local scripts_folder = library.directory .. "/lua"
library.files.folder(scripts_folder)
if #library.files.list(scripts_folder) == 0 then
	library.files.write(scripts_folder .. "/rainworld.lua", 'print("hello from rainworld.lua")\n')
	library.files.write(scripts_folder .. "/inactive.lua", 'print("hello from inactive.lua")\n')
end

-- Alphabetical, with the main script kept on top as in the design.
local function script_files()
	local names = library.files.list(scripts_folder)
	local main = table.find(names, "rainworld.lua")
	if main then
		table.insert(names, 1, table.remove(names, main))
	end
	return names
end

local scripts
scripts = library:list({
	name = "lua",
	items = script_files(),
	actions = {
		{
			name = "run",
			callback = function(file)
				local source = library.files.read(scripts_folder .. "/" .. file)
				local chunk = source and loadstring and loadstring(source, file)
				if not chunk then
					library:notification({ text = "could not load " .. file })
					return
				end
				local ok, message = pcall(chunk)
				library:notification({ text = if ok then "ran " .. file else file .. ": " .. tostring(message) })
			end,
		},
		{
			name = "del",
			callback = function(file)
				library.files.delete(scripts_folder .. "/" .. file)
				scripts.set_items(script_files())
			end,
		},
	},
})
scripts.select("rainworld.lua", true)

library:theme_window()

--// aimbot tab: the controls drawn in the design
local aimbot = window:tab({ name = "aimbot" })

local aim_assist = aimbot:section({ name = "aim assist", side = "left" })
local enabled = aim_assist:toggle({ name = "enabled", flag = "aim_enabled", default = true })
enabled:colorpicker({ flag = "aim_color", color = Color3.fromRGB(153, 129, 188) })
enabled:colorpicker({ flag = "aim_color_2", color = Color3.fromRGB(200, 162, 255), alpha = 0.8 })
-- hidden = no readout on the row until a key is bound; right-click the toggle to bind.
enabled:keybind({ name = "aim assist", flag = "aim_bind", hidden = true })
aim_assist:slider({ name = "speed", flag = "aim_speed", min = 0, max = 100, default = 10, suffix = "%" })
aim_assist:dropdown({
	name = "smoothing",
	flag = "aim_smoothing",
	items = { "linear", "exponential", "sine", "none" },
	default = "linear",
})
aim_assist:button({
	name = "button",
	callback = function()
		library:notification({ text = "button pressed" })
	end,
})

local triggerbot = aimbot:section({ name = "triggerbot", side = "right" })
triggerbot:toggle({ name = "toggle", flag = "trigger_enabled", default = true })

--// rage tab: the remaining element types
local rage = window:tab({ name = "rage" })

local elements = rage:section({ name = "elements", side = "left" })
-- list = false keeps a bind out of the keybind list.
elements:toggle({ name = "with keybind", flag = "demo_toggle" }):keybind({
	name = "demo bind",
	flag = "demo_bind",
	key = Enum.KeyCode.E,
	mode = "hold",
	list = false,
	callback = function(active)
		print("demo bind", active)
	end,
})
elements:slider({ name = "decimals", flag = "demo_decimal", min = 0, max = 1, interval = 0.05, default = 0.35 })
elements:slider({ name = "range", flag = "demo_range", min = 0, max = 100, interval = 0.5, default = { 25, 75 } })
elements:dropdown({
	name = "multi dropdown",
	flag = "demo_multi",
	items = { "head", "torso", "arms", "legs" },
	multi = true,
	default = { "head", "torso" },
})
elements:textbox({ name = "textbox", flag = "demo_text", placeholder = "type here" })
elements:colorpicker({
	name = "colour with alpha",
	flag = "demo_color",
	color = Color3.fromRGB(200, 162, 255),
	alpha = 0.5,
})
elements:keybind({ name = "standalone keybind", flag = "demo_key", key = Enum.KeyCode.LeftShift, list = false })

local more = rage:section({ name = "more", side = "right" })
more:label({
	name = "labels wrap onto as many lines as they need, so longer notes can sit between the controls of a section.",
})
more:button_row({
	{
		name = "notify",
		callback = function()
			library:notification({ text = "hello world! " .. math.random(100000, 999999) })
		end,
	},
	{
		name = "print flags",
		callback = function()
			print(library:get_config())
		end,
	},
})
more:button_row({
	{ name = "1" },
	{ name = "2" },
	{ name = "3" },
})

--// esp tab: drives the overlay of the preview window
local esp = window:tab({ name = "esp" })
local overlay = esp:section({ name = "preview", side = "left" })
for _, element in ipairs({ "box", "name", "healthbar", "distance", "flags" }) do
	local color = if element == "healthbar" then Color3.fromRGB(110, 255, 120) else Color3.fromRGB(255, 255, 255)
	local toggle = overlay:toggle({
		name = element,
		flag = "preview_" .. element,
		callback = function(value)
			preview.set(element, value)
		end,
	})
	toggle:colorpicker({
		flag = "preview_" .. element .. "_color",
		color = color,
		callback = function(value)
			preview.set(element, nil, value)
		end,
	})
end
overlay:slider({
	name = "health",
	flag = "preview_health",
	min = 0,
	max = 100,
	default = 100,
	suffix = "%",
	callback = function(value)
		preview.set_health(value / 100)
	end,
})
preview.set_flags({ "flag one", "flag two" })

local model = esp:section({ name = "model", side = "right" })
model:slider({
	name = "rotation",
	min = 0,
	max = 360,
	default = 0,
	suffix = " deg",
	callback = function(value)
		preview.set_rotation(value)
	end,
})
model:button({
	name = "refresh character",
	callback = function()
		preview.refresh()
	end,
})
model:label({
	name = "preview.set_model(model) swaps in a custom model; preview.set_model(nil) returns to your character.",
})

--// visuals tab: three columns
local visuals = window:tab({ name = "visuals", columns = 3 })
for index = 1, 3 do
	local column = visuals:section({ name = "column " .. index, side = index })
	column:toggle({ name = "toggle", flag = "visuals_toggle_" .. index })
	column:slider({ name = "amount", flag = "visuals_amount_" .. index, default = index * 25 })
end

--// misc tab: configs and interface settings live in the main window
local misc = window:tab({ name = "misc" })
window:settings({ tab = misc })

-- Applies the config chosen with "set autoload", if there is one.
library:load_autoload()

print("rainworld ui loaded. menu key:", library.menu_key.Name, "| aim_speed flag:", flags.aim_speed)
