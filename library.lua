--[[
	rainworld ui

	A Luau interface library for Roblox. The visuals follow the "rainworld" Figma
	design pixel for pixel; every measurement and colour below comes from that file.

		local library = loadstring(game:HttpGet("https://raw.githubusercontent.com/lavababsbs-lab/Lhi/refs/heads/hoplite/samos-66ff67d0/library.lua"))()
		local window = library:window({ name = "rainworld" })

	See README.md for the full API and example.lua for a complete menu.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Stats = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer

local fromOffset = UDim2.fromOffset
local fromRGB = Color3.fromRGB

-- A second execution replaces the first one instead of stacking two interfaces.
local GLOBAL_KEY = "__rainworld_ui"
local environment = (type(getgenv) == "function" and getgenv()) or _G
do
	local previous = rawget(environment, GLOBAL_KEY)
	if type(previous) == "table" and type(previous.unload) == "function" then
		pcall(previous.unload, previous)
	end
end

-- Figma sizes text by the em square, Roblox by the font's full glyph box
-- (yMin..yMax). These are that box over the em for the two faces.
local MAIN_SCALE = 896 / 1024 -- OpenSansPX
local BOLD_SCALE = 2419 / 2048 -- Tahoma Bold

local library = {
	version = "1.0.0",
	directory = "rainworld",
	flags = {},
	options = {},
	open = true,
	unloaded = false,
	menu_key = Enum.KeyCode.RightShift,
	parent = nil, -- where the ScreenGui goes; defaults to CoreGui, then PlayerGui
	draggable_sections = true,

	animation = {
		enabled = true,
		style = "smooth", -- "smooth" | "spring" | "elastic"
		speed = 1,
	},

	theme = {
		accent = fromRGB(200, 162, 255), -- #C8A2FF
		accent_mid = fromRGB(165, 145, 195), -- #A591C3
		accent_dark = fromRGB(153, 129, 188), -- #9981BC
		accent_text = fromRGB(188, 160, 228), -- #BCA0E4
		highlight = fromRGB(200, 164, 249), -- #C8A4F9
		gradient_mid = fromRGB(203, 192, 208), -- #CBC0D0
		brand_mid = fromRGB(230, 230, 230), -- #E6E6E6
		text = fromRGB(255, 255, 255),
		text_soft = fromRGB(243, 243, 243), -- #F3F3F3
		text_selected = fromRGB(214, 200, 233), -- #D6C8E9
		text_dim = fromRGB(120, 120, 120),
		stroke = fromRGB(0, 0, 0),
		button_stroke = fromRGB(45, 45, 45), -- #2D2D2D
		window_outline = fromRGB(6, 6, 6), -- #060606
		window_inline = fromRGB(29, 29, 29), -- #1D1D1D
		window_background = fromRGB(15, 15, 15), -- #0F0F0F
		panel_outline = fromRGB(12, 12, 12), -- #0C0C0C
		panel_background = fromRGB(20, 20, 20), -- #141414
		section_inline = fromRGB(40, 40, 40), -- #282828
		section_background = fromRGB(25, 25, 25), -- #191919
		element_outline = fromRGB(0, 0, 0),
		element_background = fromRGB(34, 34, 34), -- #222222
		field_outline = fromRGB(11, 11, 11), -- #0B0B0B
		track_top = fromRGB(47, 47, 47), -- #2F2F2F
		track_bottom = fromRGB(40, 40, 40), -- #282828
		button_outline = fromRGB(44, 44, 44), -- #2C2C2C
		button_top = fromRGB(38, 38, 38), -- #262626
		button_bottom = fromRGB(31, 31, 31), -- #1F1F1F
		bar_background = fromRGB(17, 17, 17), -- #111111
		float_outline = fromRGB(0, 0, 0),
		float_inline = fromRGB(22, 22, 22), -- #161616
		popup_outline = fromRGB(2, 2, 2), -- #020202
		bar_outline = fromRGB(7, 7, 7), -- #070707
	},

	-- The Figma font size of each role, converted to a Roblox TextSize.
	text_sizes = {
		element = 12 * MAIN_SCALE, -- toggles, sliders, dropdowns, section titles
		button = 14 * MAIN_SCALE, -- buttons and list rows
		tab = 15 * MAIN_SCALE, -- tabs, watermark stats, keybind list
		dock = 16 * MAIN_SCALE, -- top bar items
		title = 18 * MAIN_SCALE, -- window title
		brand = 10 * BOLD_SCALE, -- top bar and watermark brand
		panel_title = 14 * BOLD_SCALE, -- floating window titles
	},

	font_sources = {
		main = {
			name = "OpenSansPX",
			file = "open-sans-px.ttf",
			url = "https://github.com/i77lhm/storage/raw/refs/heads/main/fonts/open-sans-px.ttf",
			fallback = Enum.Font.Code,
		},
		bold = {
			name = "TahomaBoldXP",
			file = "tahoma_bold.ttf",
			url = "https://github.com/i77lhm/storage/raw/refs/heads/main/fonts/tahoma_bold.ttf",
			fallback = Enum.Font.SourceSansBold,
		},
	},
	fonts = {},
}
library.__index = library

local flags = library.flags
local theme = library.theme
local animation = library.animation
local DEFAULT_THEME = table.clone(theme)

-- Everything that has to be torn down on unload lives here.
local state: { [string]: any } = {
	gui = nil,
	root = nil,
	modal = nil,
	layers = {},
	connections = {},
	bindings = {},
	tweens = {},
	floats = {},
	keybinds = {},
	windows = {},
	theme_listeners = {},
	unload_callbacks = {},
	capture = nil,
	drag = nil,
	dock = nil,
	keybind_list = nil,
	watermark = nil,
	top_z = 10,
}

-- Interface preferences that persist between sessions (settings.json).
local settings: { [string]: any } = {}
local save_settings -- defined with the rest of the settings code further down

--// files
-- Executor file functions when they exist, an in-memory table otherwise, so configs
-- and themes keep working for the session in environments without a filesystem.
local files: { [string]: any } = {}
library.files = files
do
	local memory = {}
	local persistent = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
	files.persistent = persistent

	function files.write(path, data)
		if persistent then
			return (pcall(writefile, path, data))
		end
		memory[path] = data
		return true
	end

	function files.read(path)
		if persistent then
			local ok, data = pcall(readfile, path)
			return if ok and type(data) == "string" then data else nil
		end
		return memory[path]
	end

	function files.exists(path)
		if persistent then
			local ok, result = pcall(isfile, path)
			return ok and result == true
		end
		return memory[path] ~= nil
	end

	function files.delete(path)
		if persistent then
			if type(delfile) == "function" then
				pcall(delfile, path)
			end
		else
			memory[path] = nil
		end
	end

	function files.folder(path)
		if not persistent or type(makefolder) ~= "function" then
			return
		end
		local exists = false
		if type(isfolder) == "function" then
			local ok, result = pcall(isfolder, path)
			exists = ok and result == true
		end
		if not exists then
			pcall(makefolder, path)
		end
	end

	-- File names (without the directory) directly inside `path`.
	function files.list(path)
		local names = {}
		if persistent then
			if type(listfiles) == "function" then
				local ok, list = pcall(listfiles, path)
				if ok and type(list) == "table" then
					for _, full in ipairs(list) do
						table.insert(names, string.match(full, "([^/\\]+)$") or full)
					end
				end
			end
		else
			local prefix = path .. "/"
			for full in pairs(memory) do
				if
					string.sub(full, 1, #prefix) == prefix
					and not string.find(string.sub(full, #prefix + 1), "/", 1, true)
				then
					table.insert(names, string.sub(full, #prefix + 1))
				end
			end
		end
		table.sort(names)
		return names
	end
end

--// utility
local function round(value, step)
	step = step or 1
	return math.floor(value / step + 0.5) * step
end

local function decimals_of(step)
	local fraction = string.match(tostring(step), "%.(%d+)")
	return if fraction then #fraction else 0
end

-- Lets a method be called as object.method(...) or object:method(...).
local function method(object, callback)
	return function(first, ...)
		if first == object then
			return callback(...)
		end
		return callback(first, ...)
	end
end

local function safe_call(callback, ...)
	if type(callback) ~= "function" then
		return
	end
	local ok, message = pcall(callback, ...)
	if not ok then
		warn("[rainworld] callback error: " .. tostring(message))
	end
end

local function track(connection)
	table.insert(state.connections, connection)
	return connection
end

local KEY_NAMES = {
	LeftShift = "ls",
	RightShift = "rs",
	LeftControl = "lc",
	RightControl = "rc",
	LeftAlt = "la",
	RightAlt = "ra",
	LeftSuper = "lwin",
	RightSuper = "rwin",
	CapsLock = "caps",
	Insert = "ins",
	Delete = "del",
	Backspace = "bs",
	Return = "ent",
	Escape = "esc",
	Space = "spc",
	PageUp = "pgup",
	PageDown = "pgdn",
	MouseButton1 = "mb1",
	MouseButton2 = "mb2",
	MouseButton3 = "mb3",
	Zero = "0",
	One = "1",
	Two = "2",
	Three = "3",
	Four = "4",
	Five = "5",
	Six = "6",
	Seven = "7",
	Eight = "8",
	Nine = "9",
	Minus = "-",
	Equals = "=",
	Comma = ",",
	Period = ".",
	Slash = "/",
	Semicolon = ";",
	Quote = "'",
	LeftBracket = "[",
	RightBracket = "]",
	BackSlash = "\\",
	Backquote = "`",
}
local KEYPAD_NAMES = { "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
for index, name in ipairs(KEYPAD_NAMES) do
	KEY_NAMES["Keypad" .. name] = "num" .. tostring(index - 1)
end

local function key_name(key)
	if typeof(key) ~= "EnumItem" then
		return "none"
	end
	return KEY_NAMES[key.Name] or string.lower(key.Name)
end

local function serialize_key(key)
	if typeof(key) ~= "EnumItem" then
		return "none"
	end
	return (if key.EnumType == Enum.KeyCode then "KeyCode." else "UserInputType.") .. key.Name
end

local function deserialize_key(text)
	if type(text) ~= "string" then
		return nil
	end
	local enum_name, item_name = string.match(text, "^(%a+)%.([%w_]+)$")
	if enum_name ~= "KeyCode" and enum_name ~= "UserInputType" then
		return nil
	end
	local ok, item = pcall(function()
		return Enum[enum_name][item_name]
	end)
	return if ok then item else nil
end

local function input_matches(input, key)
	if typeof(key) ~= "EnumItem" then
		return false
	end
	if key.EnumType == Enum.KeyCode then
		return input.KeyCode == key
	end
	return input.UserInputType == key
end

--// frame driver
-- One RenderStepped connection serves every per-frame job and disconnects itself
-- when the last job is removed.
local frame: { [string]: any } = { jobs = {}, queued = {}, count = 0, stepping = false, connection = nil }

local function step_frame(delta)
	frame.stepping = true
	for _, job in pairs(frame.jobs) do
		job(delta)
	end
	frame.stepping = false
	-- Jobs bound while stepping join afterwards; adding keys mid-traversal is not allowed.
	for id, job in pairs(frame.queued) do
		frame.jobs[id] = job
		frame.queued[id] = nil
	end
end

function frame.bind(id, callback)
	if library.unloaded then
		return
	end
	if frame.jobs[id] == nil and frame.queued[id] == nil then
		frame.count += 1
	end
	if frame.stepping and frame.jobs[id] == nil then
		frame.queued[id] = callback
	else
		frame.jobs[id] = callback
	end
	if frame.connection == nil then
		frame.connection = RunService.RenderStepped:Connect(step_frame)
	end
end

function frame.unbind(id)
	if frame.jobs[id] ~= nil or frame.queued[id] ~= nil then
		frame.jobs[id] = nil
		frame.queued[id] = nil
		frame.count -= 1
	end
	if frame.count <= 0 and frame.connection then
		frame.connection:Disconnect()
		frame.connection = nil
	end
end

--// animation
local EASING = {
	smooth = Enum.EasingStyle.Quint,
	spring = Enum.EasingStyle.Back,
	elastic = Enum.EasingStyle.Elastic,
}

-- Running tweens by instance and property. A direct write has to cancel the tween
-- on that property first, or the tween overwrites it again a frame later.
local function stop_tweens(instance, goals)
	local running = state.tweens[instance]
	if not running then
		return
	end
	for property in pairs(goals) do
		local handle = running[property]
		if handle then
			running[property] = nil
			handle:Cancel()
		end
	end
	if next(running) == nil then
		state.tweens[instance] = nil
	end
end

-- Plays a tween and keeps it registered until it ends, so a later write to the
-- same property, destroying the instance, or unloading can cancel it.
local function play(instance, info, goals)
	stop_tweens(instance, goals)
	local handle = TweenService:Create(instance, info, goals)
	local running = state.tweens[instance]
	if not running then
		running = {}
		state.tweens[instance] = running
	end
	for property in pairs(goals) do
		running[property] = handle
	end
	handle.Completed:Once(function()
		local current = state.tweens[instance]
		if not current then
			return
		end
		for property in pairs(goals) do
			if current[property] == handle then
				current[property] = nil
			end
		end
		if next(current) == nil then
			state.tweens[instance] = nil
		end
	end)
	handle:Play()
	return handle
end

-- `motion` marks geometry (size, position): only that follows the spring/elastic
-- style, colours always ease smoothly because overshooting them just flickers.
-- Returns the Tween, or nil when the goals were applied immediately.
local function tween(instance, goals, duration, motion)
	if not animation.enabled or library.unloaded or not duration or duration <= 0 then
		stop_tweens(instance, goals)
		for property, value in pairs(goals) do
			instance[property] = value
		end
		return nil
	end
	local style = Enum.EasingStyle.Quint
	local length = duration / math.max(animation.speed, 0.05)
	if motion then
		style = EASING[animation.style] or style
		if style == Enum.EasingStyle.Elastic then
			length *= 2.2
		elseif style == Enum.EasingStyle.Back then
			length *= 1.3
		end
	end
	return play(instance, TweenInfo.new(length, style, Enum.EasingDirection.Out), goals)
end

-- Runs `callback` once the tween finishes on its own (not when it is replaced),
-- or straight away when there was nothing to animate.
local function after(handle, callback)
	if not handle then
		callback()
		return
	end
	handle.Completed:Once(function(playback)
		if playback == Enum.PlaybackState.Completed then
			callback()
		end
	end)
end

--// theme
local function resolve(key)
	if type(key) == "function" then
		return key(theme)
	end
	return theme[key]
end

-- Binds a property to a theme key (or to a function of the theme) so later
-- theme changes reach the instance.
local function bind(instance, property, key, duration)
	local map = state.bindings[instance]
	if not map then
		map = {}
		state.bindings[instance] = map
	end
	map[property] = key
	if duration then
		tween(instance, { [property] = resolve(key) }, duration)
	else
		instance[property] = resolve(key)
	end
end

local function forget(instance)
	state.bindings[instance] = nil
	local running = state.tweens[instance]
	if running then
		state.tweens[instance] = nil
		for _, handle in pairs(running) do
			handle:Cancel()
		end
	end
end

-- Drops the theme bindings and running tweens of an instance and everything in it.
local function release(instance)
	forget(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		forget(descendant)
	end
end

local function destroy(instance)
	release(instance)
	instance:Destroy()
end

-- Applies { key = Color3 } in one pass over the bound instances.
local function apply_theme(changes)
	local changed = false
	for key, color in pairs(changes) do
		if theme[key] ~= nil and typeof(color) == "Color3" and theme[key] ~= color then
			theme[key] = color
			changed = true
		else
			changes[key] = nil
		end
	end
	if not changed then
		return
	end
	for instance, map in pairs(state.bindings) do
		local running = state.tweens[instance]
		for property, bound in pairs(map) do
			if type(bound) == "function" or changes[bound] ~= nil then
				if running and running[property] then
					running[property]:Cancel()
					running[property] = nil
				end
				instance[property] = resolve(bound)
			end
		end
	end
	for key, color in pairs(changes) do
		for _, listener in ipairs(state.theme_listeners) do
			listener(key, color)
		end
	end
end

-- Saturation/value of each accent tone relative to the main accent, taken from
-- the Figma palette, so one colour can re-tint the whole family.
local ACCENT_FAMILY = {
	accent_mid = { 0.703, 0.765 },
	accent_dark = { 0.861, 0.737 },
	accent_text = { 0.818, 0.894 },
	highlight = { 0.936, 0.976 },
	text_selected = { 0.388, 0.914 },
	gradient_mid = { 0.211, 0.816 },
}

function library:set_accent(color)
	local hue, saturation, value = color:ToHSV()
	local changes = { accent = color }
	for key, ratio in pairs(ACCENT_FAMILY) do
		changes[key] = Color3.fromHSV(hue, math.clamp(saturation * ratio[1], 0, 1), math.clamp(value * ratio[2], 0, 1))
	end
	apply_theme(changes)
end

-- Changes one theme colour. "accent" re-tints the whole accent family, which is
-- what scripts written for similar libraries expect; load_theme({ accent = c })
-- sets that single tone.
function library:update_theme(key, color)
	if key == "accent" then
		self:set_accent(color)
	else
		apply_theme({ [key] = color })
	end
end

--// instances
local CLASS_DEFAULTS = {
	Frame = { BorderSizePixel = 0 },
	TextLabel = { BorderSizePixel = 0, BackgroundTransparency = 1, Text = "" },
	TextButton = { BorderSizePixel = 0, BackgroundTransparency = 1, Text = "", AutoButtonColor = false },
	TextBox = { BorderSizePixel = 0, BackgroundTransparency = 1, Text = "", ClearTextOnFocus = false },
	ImageLabel = { BorderSizePixel = 0, BackgroundTransparency = 1 },
	ViewportFrame = { BorderSizePixel = 0, BackgroundTransparency = 1 },
	ScrollingFrame = {
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
	},
}

-- `Theme = { Property = "theme_key" }` binds properties; Parent is assigned last.
local function create(class, properties)
	local instance = Instance.new(class)
	local defaults = CLASS_DEFAULTS[class]
	if defaults then
		for property, value in pairs(defaults) do
			instance[property] = value
		end
	end
	local parent, bindings
	for property, value in pairs(properties) do
		if property == "Parent" then
			parent = value
		elseif property == "Theme" then
			bindings = value
		else
			instance[property] = value
		end
	end
	if bindings then
		for property, key in pairs(bindings) do
			bind(instance, property, key)
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

-- Text with the library fonts. options: font ("main" | "bold"), size (text_sizes
-- key), color (theme key), stroke (true or a theme key for the outline colour).
local function text(class, properties, options)
	options = options or {}
	properties.FontFace = library.fonts[options.font or "main"]
	properties.TextSize = library.text_sizes[options.size or "element"]
	if properties.TextXAlignment == nil then
		properties.TextXAlignment = Enum.TextXAlignment.Left
	end
	local bindings = properties.Theme or {}
	if bindings.TextColor3 == nil and properties.TextColor3 == nil then
		bindings.TextColor3 = options.color or "text"
	end
	if options.stroke then
		properties.TextStrokeTransparency = 0
		bindings.TextStrokeColor3 = if options.stroke == true then "stroke" else options.stroke
	end
	properties.Theme = bindings
	return create(class, properties)
end

-- Nested 1px (or thicker) borders as plain frames: layers = { { key, thickness }, ..., { key } }.
-- Returns the outermost frame and the innermost fill.
local function box(properties, layers)
	local outer, current
	for index, layer in ipairs(layers) do
		local frame_properties
		if index == 1 then
			frame_properties = properties
		else
			local inset = layers[index - 1][2] or 1
			frame_properties = {
				Parent = current,
				Position = fromOffset(inset, inset),
				Size = UDim2.new(1, -inset * 2, 1, -inset * 2),
			}
		end
		frame_properties.Theme = frame_properties.Theme or {}
		frame_properties.Theme.BackgroundColor3 = layer[1]
		current = create("Frame", frame_properties)
		outer = outer or current
	end
	return outer, current
end

local function gradient(parent, rotation, key)
	return create("UIGradient", { Parent = parent, Rotation = rotation, Theme = { Color = key } })
end

local GRADIENTS = {
	title = function(colors)
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, colors.accent),
			ColorSequenceKeypoint.new(0.53, colors.gradient_mid),
			ColorSequenceKeypoint.new(1, colors.accent_dark),
		})
	end,
	brand = function(colors)
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, colors.accent_dark),
			ColorSequenceKeypoint.new(0.5, colors.brand_mid),
			ColorSequenceKeypoint.new(1, colors.accent_mid),
		})
	end,
	button = function(colors)
		return ColorSequence.new(colors.button_top, colors.button_bottom)
	end,
}

-- Centres an AutomaticSize label in `container` (its parent) on a whole pixel,
-- so the result never depends on how the engine rounds a half pixel. The design
-- drops the half pixel; `up` rounds it the other way.
local function center(label, container, y, up)
	local function update()
		local free = (container.AbsoluteSize.X - label.AbsoluteSize.X) / 2
		label.Position = fromOffset(if up then math.ceil(free) else math.floor(free), y)
	end
	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	container:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	update()
end

-- Two stacked stripes, the look shared by slider tracks, fills and tab underlines.
local function stripes(properties, top_key, bottom_key, top_height)
	properties.BackgroundTransparency = 1
	local holder = create("Frame", properties)
	local top = create("Frame", {
		Parent = holder,
		Size = UDim2.new(1, 0, 0, top_height),
		Theme = { BackgroundColor3 = top_key },
	})
	local bottom = create("Frame", {
		Parent = holder,
		Position = fromOffset(0, top_height),
		Size = UDim2.new(1, 0, 1, -top_height),
		Theme = { BackgroundColor3 = bottom_key },
	})
	return holder, top, bottom
end

-- Pointer position in the same space AbsolutePosition uses. The root frame fills
-- the whole screen, so its reported position is exactly the offset between the two.
local function pointer()
	local location = UserInputService:GetMouseLocation()
	local root = state.root
	if root then
		return location + root.AbsolutePosition
	end
	return location
end

local function contains(instance, point)
	local position, size = instance.AbsolutePosition, instance.AbsoluteSize
	return point.X >= position.X
		and point.X < position.X + size.X
		and point.Y >= position.Y
		and point.Y < position.Y + size.Y
end

-- Position of `instance` inside the root layer, for placing popups next to it.
local function relative_position(instance)
	return instance.AbsolutePosition - state.root.AbsolutePosition
end

local function end_drag()
	local drag = state.drag
	if drag then
		state.drag = nil
		frame.unbind("drag")
		if drag.stop then
			drag.stop()
		end
	end
end

-- Follows the pointer until the button is released. The pointer is polled once
-- per frame, which caps the work no matter how fast the mouse reports.
local function begin_drag(move, stop)
	end_drag()
	local last = pointer()
	local mouse_only = UserInputService.MouseEnabled and not UserInputService.TouchEnabled
	state.drag = { stop = stop }
	move(last)
	frame.bind("drag", function()
		-- Releasing outside the game window never reports InputEnded.
		if mouse_only and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			end_drag()
			return
		end
		local point = pointer()
		if point ~= last then
			last = point
			move(point)
		end
	end)
end

--// fonts
-- Sizes used with the built-in fallback fonts when the real faces cannot load.
local FALLBACK_SIZES = {
	main = { element = 12, button = 13, tab = 14, dock = 15, title = 17 },
	bold = { brand = 13, panel_title = 17 },
}

-- Custom faces need the executor asset API. Returns the font and whether it is
-- the real face (false means the built-in fallback is in use).
local function load_font(source)
	local fallback = Font.fromEnum(source.fallback)
	local asset = getcustomasset or getsynasset
	if not files.persistent or type(asset) ~= "function" then
		return fallback, false
	end
	local folder = library.directory .. "/fonts"
	local font_path = folder .. "/" .. source.file
	local face_path = folder .. "/" .. source.name .. ".font"
	local ok, result = pcall(function()
		if not files.exists(font_path) then
			local data = (game :: any):HttpGet(source.url)
			if type(data) ~= "string" or #data < 1024 then
				error("font download failed")
			end
			files.write(font_path, data)
		end
		-- Rewritten every session: the asset id is only valid for the current one.
		files.write(
			face_path,
			HttpService:JSONEncode({
				name = source.name,
				faces = { { name = "Regular", weight = 400, style = "normal", assetId = asset(font_path) } },
			})
		)
		return Font.new(asset(face_path), Enum.FontWeight.Regular, Enum.FontStyle.Normal)
	end)
	if ok and typeof(result) == "Font" then
		return result, true
	end
	return fallback, false
end

--// floats
-- Every free-standing piece (window, watermark, keybind list, preview, lists) is a
-- float: draggable, focusable, and shown or hidden with the menu unless it is a HUD.
local Float = {}
Float.__index = Float

local function next_z()
	state.top_z += 1
	return state.top_z
end

-- options: name, position, size (nil = sized by its content), hud, visible, dock
local function new_float(options)
	-- A window the user hid through the top bar stays hidden next session. The
	-- main window opts out, so a menu can never be left with no way to show it.
	local remembered = nil
	if options.remember ~= false and settings.floats then
		remembered = settings.floats[options.name]
	end
	local self = setmetatable({
		name = options.name,
		hud = options.hud == true,
		enabled = if type(remembered) == "boolean" then remembered else options.visible ~= false,
		shown = false,
		size = options.size,
		position = options.position or Vector2.new(100, 100),
		dock = options.dock ~= false,
		listeners = {}, -- called with `enabled` when it changes
		shown_listeners = {}, -- called with `shown` (enabled and the menu is open, or a HUD)
	}, Float)
	self.holder = create("Frame", {
		Parent = state.layers.floats,
		Name = options.name,
		BackgroundTransparency = 1,
		ClipsDescendants = options.size ~= nil,
		Position = fromOffset(self.position.X, self.position.Y),
		Size = if options.size then fromOffset(options.size.X, options.size.Y) else fromOffset(0, 0),
		Visible = false,
		ZIndex = next_z(),
	})
	self.hit = self.holder
	table.insert(state.floats, self)
	return self
end

-- The body is what slides during the show animation; for content-sized floats it
-- is also the rectangle used for hit tests.
function Float:attach(body)
	self.body = body
	if not self.size then
		self.hit = body
	end
	self:refresh(true)
	if state.dock and self.dock then
		state.dock:add_float(self)
	end
end

function Float:refresh(instant)
	local show = self.enabled and (self.hud or library.open)
	if show == self.shown then
		return
	end
	self.shown = show
	local holder, body, size = self.holder, self.body, self.size
	local animate = not instant and animation.enabled
	if show then
		holder.Visible = true
		if size then
			if animate then
				holder.Size = fromOffset(size.X, 0)
			end
			tween(holder, { Size = fromOffset(size.X, size.Y) }, if animate then 0.22 else 0)
		end
		if body and animate then
			body.Position = fromOffset(0, -10)
			tween(body, { Position = fromOffset(0, 0) }, 0.22, true)
		end
	elseif size and animate then
		after(tween(holder, { Size = fromOffset(size.X, 0) }, 0.16), function()
			if not self.shown then
				holder.Visible = false
			end
		end)
	else
		holder.Visible = false
	end
	for _, listener in ipairs(self.shown_listeners) do
		listener(show)
	end
end

function Float:set_visible(visible)
	visible = visible == true
	if self.enabled == visible then
		return
	end
	self.enabled = visible
	self:refresh()
	for _, listener in ipairs(self.listeners) do
		listener(visible)
	end
end

-- Stores the current visibility so it survives a restart (user-driven changes only).
function Float:remember()
	settings.floats = settings.floats or {}
	settings.floats[self.name] = self.enabled
	save_settings()
end

function Float:set_position(position, smooth)
	local screen = state.root.AbsoluteSize
	local size = self.hit.AbsoluteSize
	local x, y = position.X, position.Y
	if screen.X > 80 and screen.Y > 80 then
		x = math.clamp(x, 30 - size.X, screen.X - 30)
		y = math.clamp(y, 0, screen.Y - 20)
	end
	self.position = Vector2.new(math.floor(x + 0.5), math.floor(y + 0.5))
	local goal = fromOffset(self.position.X, self.position.Y)
	if smooth then
		tween(self.holder, { Position = goal }, 0.07)
	else
		self.holder.Position = goal
	end
end

function Float:set_size(size)
	self.size = size
	if self.shown then
		tween(self.holder, { Size = fromOffset(size.X, size.Y) }, 0)
	end
end

function Float:focus()
	self.holder.ZIndex = next_z()
end

function Float:drag_handle(button)
	button.MouseButton1Down:Connect(function()
		local start = pointer()
		local origin = self.position
		self:focus()
		begin_drag(function(point)
			self:set_position(origin + (point - start), true)
		end)
	end)
end

function Float:destroy()
	local index = table.find(state.floats, self)
	if index then
		table.remove(state.floats, index)
	end
	destroy(self.holder)
end

local function focus_float_at(point)
	local best
	for _, float in ipairs(state.floats) do
		if float.shown and contains(float.hit, point) and (not best or float.holder.ZIndex > best.holder.ZIndex) then
			best = float
		end
	end
	if best then
		best:focus()
	end
end

--// popups
-- One popup is open at a time. A popup is { frame, anchor, close() }.
local popup = { current = nil }

function popup.close()
	local current = popup.current
	if current then
		popup.current = nil
		frame.unbind("popup")
		current.close()
	end
end

local function place_popup(popup_frame, anchor, size)
	local screen = state.root.AbsoluteSize
	local origin = relative_position(anchor)
	local x = origin.X
	local y = origin.Y + anchor.AbsoluteSize.Y + 2
	if y + size.Y > screen.Y and origin.Y - size.Y - 2 >= 0 then
		y = origin.Y - size.Y - 2
	end
	if screen.X > size.X then
		x = math.clamp(x, 0, screen.X - size.X)
	end
	popup_frame.Position = fromOffset(x, y)
end

-- Opens `popup_frame` under `anchor`, unrolling it to `size`.
function popup.open(popup_frame, anchor, size, on_close)
	popup.close()
	popup_frame.Visible = true
	popup_frame.Size = fromOffset(size.X, if animation.enabled then 0 else size.Y)
	place_popup(popup_frame, anchor, size)
	tween(popup_frame, { Size = fromOffset(size.X, size.Y) }, 0.16, true)
	local entry
	entry = {
		frame = popup_frame,
		anchor = anchor,
		close = function()
			after(tween(popup_frame, { Size = fromOffset(size.X, 0) }, 0.1), function()
				if popup.current == nil or popup.current.frame ~= popup_frame then
					popup_frame.Visible = false
				end
			end)
			if on_close then
				on_close()
			end
		end,
	}
	popup.current = entry
	-- Follows the anchor while its window is dragged.
	local last = anchor.AbsolutePosition
	frame.bind("popup", function()
		local now = anchor.AbsolutePosition
		if now ~= last then
			last = now
			place_popup(popup_frame, anchor, size)
		end
	end)
	return entry
end

function popup.outside_click(point)
	local current = popup.current
	if current and not contains(current.frame, point) and not contains(current.anchor, point) then
		popup.close()
	end
end

--// colour picker popup (shared by every colour swatch)
local picker: { [string]: any } =
	{ frame = nil, target = nil, hue = 0, saturation = 0, value = 1, alpha = 1, applying = false }

local HUE_SEQUENCE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, fromRGB(255, 0, 0)),
	ColorSequenceKeypoint.new(1 / 6, fromRGB(255, 255, 0)),
	ColorSequenceKeypoint.new(2 / 6, fromRGB(0, 255, 0)),
	ColorSequenceKeypoint.new(3 / 6, fromRGB(0, 255, 255)),
	ColorSequenceKeypoint.new(4 / 6, fromRGB(0, 0, 255)),
	ColorSequenceKeypoint.new(5 / 6, fromRGB(255, 0, 255)),
	ColorSequenceKeypoint.new(1, fromRGB(255, 0, 0)),
})

local function format_hex(color, alpha)
	return string.upper("#" .. color:ToHex() .. string.format("%02x", math.floor(alpha * 255 + 0.5)))
end

-- Accepts RRGGBB or RRGGBBAA with an optional leading '#'.
local function parse_hex(input)
	local digits = string.gsub(input, "[^%x]", "")
	if #digits ~= 6 and #digits ~= 8 then
		return nil
	end
	local ok, color = pcall(Color3.fromHex, string.sub(digits, 1, 6))
	if not ok then
		return nil
	end
	local alpha = if #digits == 8 then (tonumber(string.sub(digits, 7, 8), 16) or 255) / 255 else nil
	return color, alpha
end

function picker.render()
	local color = Color3.fromHSV(picker.hue, picker.saturation, picker.value)
	picker.square.BackgroundColor3 = Color3.fromHSV(picker.hue, 1, 1)
	picker.alpha_fill.BackgroundColor3 = color
	picker.hue_cursor.Position = fromOffset(4 + math.floor(picker.hue * 119 + 0.5), 3)
	picker.alpha_cursor.Position = fromOffset(4 + math.floor(picker.alpha * 119 + 0.5), 148)
	picker.square_cursor.Position = UDim2.new(picker.saturation, -2, 1 - picker.value, -2)
	if not picker.hex:IsFocused() then
		picker.hex.Text = format_hex(color, picker.alpha)
	end
end

-- Pushes the popup state into the element that owns it.
function picker.apply()
	local target = picker.target
	picker.render()
	if target then
		picker.applying = true
		target.set(Color3.fromHSV(picker.hue, picker.saturation, picker.value), picker.alpha)
		picker.applying = false
	end
end

-- Pulls the element state into the popup (when opened or set from code).
function picker.sync()
	local target = picker.target
	if not target or picker.applying then
		return
	end
	local hue, saturation, value = target.color:ToHSV()
	-- Greys and black carry no hue; keep the one the user last picked.
	if saturation > 0 and value > 0 then
		picker.hue = hue
	end
	picker.saturation, picker.value, picker.alpha = saturation, value, target.alpha
	picker.render()
end

function picker.build()
	local outer, inner = box({
		Parent = state.layers.popups,
		Name = "colorpicker",
		Visible = false,
		ClipsDescendants = true,
		Size = fromOffset(130, 188),
	}, { { "popup_outline", 1 }, { "window_background" } })
	picker.frame = outer
	-- Swallows clicks so they never reach the game through the popup.
	create("TextButton", { Parent = inner, Size = UDim2.new(1, 0, 0, 186) })

	local function bar(y, name)
		local border = create("Frame", {
			Parent = inner,
			Name = name,
			Position = fromOffset(3, y),
			Size = fromOffset(122, 17),
			Theme = { BackgroundColor3 = "bar_outline" },
		})
		local fill = create("Frame", {
			Parent = border,
			Position = fromOffset(1, 1),
			Size = fromOffset(120, 15),
			BackgroundColor3 = fromRGB(255, 255, 255),
		})
		local cursor = create("Frame", {
			Parent = inner,
			Position = fromOffset(4, y),
			Size = fromOffset(1, 17),
			ZIndex = 3,
			Theme = { BackgroundColor3 = "text" },
		})
		local button = create("TextButton", {
			Parent = inner,
			Position = fromOffset(4, y),
			Size = fromOffset(120, 17),
			ZIndex = 4,
		})
		return fill, cursor, button
	end

	local hue_fill, hue_cursor, hue_button = bar(3, "hue")
	create("UIGradient", { Parent = hue_fill, Color = HUE_SEQUENCE })
	picker.hue_cursor = hue_cursor

	local square_border = create("Frame", {
		Parent = inner,
		Name = "square",
		Position = fromOffset(3, 23),
		Size = fromOffset(122, 122),
		Theme = { BackgroundColor3 = "element_outline" },
	})
	local square = create("Frame", {
		Parent = square_border,
		Position = fromOffset(1, 1),
		Size = fromOffset(120, 120),
		ClipsDescendants = true,
	})
	picker.square = square
	local white =
		create("Frame", { Parent = square, Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = fromRGB(255, 255, 255) })
	create("UIGradient", {
		Parent = white,
		Transparency = NumberSequence.new(0, 1),
	})
	local black = create(
		"Frame",
		{ Parent = square, Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = fromRGB(0, 0, 0), ZIndex = 2 }
	)
	create("UIGradient", {
		Parent = black,
		Rotation = 90,
		Transparency = NumberSequence.new(1, 0),
	})
	local square_cursor = create("Frame", {
		Parent = square,
		Size = fromOffset(5, 5),
		ZIndex = 3,
		BackgroundColor3 = fromRGB(0, 0, 0),
	})
	create("Frame", {
		Parent = square_cursor,
		Position = fromOffset(1, 1),
		Size = fromOffset(3, 3),
		BackgroundColor3 = fromRGB(255, 255, 255),
	})
	picker.square_cursor = square_cursor
	local square_button = create("TextButton", {
		Parent = inner,
		Position = fromOffset(4, 24),
		Size = fromOffset(120, 120),
		ZIndex = 4,
	})

	local alpha_fill, alpha_cursor, alpha_button = bar(148, "alpha")
	-- Checkerboard from hard-stop gradients: 3 rows of 5px cells, each strip 8 cells.
	for row = 0, 2 do
		for strip = 0, 2 do
			local keypoints = {}
			for cell = 0, 7 do
				local shade = if (cell + row) % 2 == 0 then fromRGB(84, 84, 84) else fromRGB(52, 52, 52)
				table.insert(keypoints, ColorSequenceKeypoint.new(cell / 8, shade))
				table.insert(
					keypoints,
					ColorSequenceKeypoint.new(if cell == 7 then 1 else (cell + 1) / 8 - 0.001, shade)
				)
			end
			local strip_frame = create("Frame", {
				Parent = alpha_fill,
				Position = fromOffset(strip * 40, row * 5),
				Size = fromOffset(40, 5),
				BackgroundColor3 = fromRGB(255, 255, 255),
			})
			create("UIGradient", { Parent = strip_frame, Color = ColorSequence.new(keypoints) })
		end
	end
	alpha_fill.BackgroundTransparency = 1
	picker.alpha_fill = create("Frame", { Parent = alpha_fill, Size = UDim2.new(1, 0, 1, 0), ZIndex = 2 })
	create("UIGradient", { Parent = picker.alpha_fill, Transparency = NumberSequence.new(1, 0) })
	picker.alpha_cursor = alpha_cursor

	local _, field = box({
		Parent = inner,
		Name = "hex",
		Position = fromOffset(3, 168),
		Size = fromOffset(122, 15),
		ZIndex = 4,
	}, { { "field_outline", 1 }, { "element_background" } })
	picker.hex = text("TextBox", {
		Parent = field,
		Position = fromOffset(2, 1),
		Size = UDim2.new(1, -4, 0, 12),
		ClipsDescendants = true,
		PlaceholderText = "#RRGGBBAA",
	})
	picker.hex.FocusLost:Connect(function()
		local color, alpha = parse_hex(picker.hex.Text)
		if color and picker.target then
			picker.target.set(color, alpha or picker.alpha)
		end
		picker.render()
	end)

	-- The first and last pixel map to exactly 0 and 1.
	local function fraction(instance, point)
		local position, size = instance.AbsolutePosition, instance.AbsoluteSize
		return math.clamp((point.X - position.X) / math.max(size.X - 1, 1), 0, 1),
			math.clamp((point.Y - position.Y) / math.max(size.Y - 1, 1), 0, 1)
	end
	hue_button.MouseButton1Down:Connect(function()
		begin_drag(function(point)
			picker.hue = fraction(hue_button, point)
			picker.apply()
		end)
	end)
	alpha_button.MouseButton1Down:Connect(function()
		begin_drag(function(point)
			picker.alpha = round(fraction(alpha_button, point), 0.01)
			picker.apply()
		end)
	end)
	square_button.MouseButton1Down:Connect(function()
		begin_drag(function(point)
			local x, y = fraction(square_button, point)
			picker.saturation, picker.value = x, 1 - y
			picker.apply()
		end)
	end)
end

function picker.open(target, anchor)
	local same = popup.current ~= nil and popup.current.frame == picker.frame and picker.target == target
	-- Closing first matters: the previous popup's close handler clears picker.target.
	popup.close()
	if same then
		return
	end
	if not picker.frame then
		picker.build()
	end
	picker.target = target
	picker.sync()
	popup.open(picker.frame, anchor, Vector2.new(130, 188), function()
		picker.target = nil
	end)
end

--// list popup (dropdown options and keybind modes share it)
local list_popup: { [string]: any } = { frame = nil, rows = {}, config = nil }
local LIST_ROW = 15

function list_popup.build()
	local outer, inner = box({
		Parent = state.layers.popups,
		Name = "list",
		Visible = false,
		ClipsDescendants = true,
		Size = fromOffset(100, LIST_ROW + 2),
	}, { { "field_outline", 1 }, { "element_background" } })
	list_popup.frame = outer
	create("TextButton", { Parent = inner, Size = UDim2.new(1, 0, 1, 0) })
	list_popup.scroll = create("ScrollingFrame", {
		Parent = inner,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 2,
	})
end

function list_popup.row(index)
	local row = list_popup.rows[index]
	if row then
		return row
	end
	local button = create("TextButton", {
		Parent = list_popup.scroll,
		Position = fromOffset(0, (index - 1) * LIST_ROW),
		Size = UDim2.new(1, 0, 0, LIST_ROW),
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "highlight" },
	})
	local label = text("TextLabel", {
		Parent = button,
		Position = fromOffset(2, 1),
		Size = UDim2.new(1, -4, 0, 12),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	row = { button = button, label = label, item = nil }
	list_popup.rows[index] = row
	button.MouseEnter:Connect(function()
		tween(button, { BackgroundTransparency = 0.89 }, 0.1)
	end)
	button.MouseLeave:Connect(function()
		tween(button, { BackgroundTransparency = 1 }, 0.1)
	end)
	button.MouseButton1Click:Connect(function()
		local config = list_popup.config
		if not config or row.item == nil then
			return
		end
		config.pick(row.item)
		if config.multi then
			list_popup.refresh()
		else
			popup.close()
		end
	end)
	return row
end

function list_popup.refresh()
	local config = list_popup.config
	if not config then
		return
	end
	for index, item in ipairs(config.items) do
		local row = list_popup.row(index)
		row.item = item
		row.button.Visible = true
		row.label.Text = tostring(item)
		bind(row.label, "TextColor3", if config.selected(item) then "accent" else "text")
	end
	for index = #config.items + 1, #list_popup.rows do
		list_popup.rows[index].button.Visible = false
		list_popup.rows[index].item = nil
	end
end

-- config: { owner, items, selected(item) -> boolean, pick(item), multi, max_rows, min_width, closed() }
function list_popup.open(config, anchor)
	local same = popup.current ~= nil
		and popup.current.frame == list_popup.frame
		and list_popup.config ~= nil
		and list_popup.config.owner == config.owner
	popup.close()
	if same then
		return
	end
	if not list_popup.frame then
		list_popup.build()
	end
	list_popup.config = config
	list_popup.refresh()
	local visible_rows = math.clamp(#config.items, 1, config.max_rows or 8)
	local width = math.max(anchor.AbsoluteSize.X, config.min_width or 0)
	list_popup.scroll.CanvasSize = fromOffset(0, #config.items * LIST_ROW)
	list_popup.scroll.CanvasPosition = Vector2.new(0, 0)
	popup.open(list_popup.frame, anchor, Vector2.new(width, visible_rows * LIST_ROW + 2), function()
		list_popup.config = nil
		if config.closed then
			config.closed()
		end
	end)
end

--// sizing helpers
local function to_vector(value, fallback)
	if typeof(value) == "UDim2" then
		return Vector2.new(value.X.Offset, value.Y.Offset)
	elseif typeof(value) == "Vector2" then
		return value
	end
	return fallback
end

-- Keeps a requested size between `minimum` and the screen, on whole pixels.
local function clamp_size(size, minimum)
	local screen = state.root.AbsoluteSize
	local width, height = math.max(size.X, minimum.X), math.max(size.Y, minimum.Y)
	if screen.X > minimum.X and screen.Y > minimum.Y then
		width, height = math.min(width, screen.X), math.min(height, screen.Y)
	end
	return Vector2.new(math.floor(width + 0.5), math.floor(height + 0.5))
end

-- Bottom-right resize grip: invisible until hovered. `apply` receives the
-- requested size and is responsible for clamping and resizing the owner.
local function resize_grip(float, parent, current, apply)
	local grip = create("TextButton", {
		Parent = parent,
		Name = "resize",
		Position = UDim2.new(1, -12, 1, -12),
		Size = fromOffset(12, 12),
		ZIndex = 8,
	})
	local marks = {
		create("Frame", {
			Parent = grip,
			Position = fromOffset(4, 9),
			Size = fromOffset(6, 1),
			BackgroundTransparency = 1,
			Theme = { BackgroundColor3 = "accent_dark" },
		}),
		create("Frame", {
			Parent = grip,
			Position = fromOffset(9, 4),
			Size = fromOffset(1, 6),
			BackgroundTransparency = 1,
			Theme = { BackgroundColor3 = "accent_dark" },
		}),
	}
	local hovered, resizing = false, false
	local function update()
		for _, mark in ipairs(marks) do
			tween(mark, { BackgroundTransparency = if hovered or resizing then 0 else 1 }, 0.12)
		end
	end
	grip.MouseEnter:Connect(function()
		hovered = true
		update()
	end)
	grip.MouseLeave:Connect(function()
		hovered = false
		update()
	end)
	grip.MouseButton1Down:Connect(function()
		local start, origin = pointer(), current()
		resizing = true
		float:focus()
		popup.close()
		update()
		begin_drag(function(point)
			apply(origin + (point - start))
		end, function()
			resizing = false
			update()
		end)
	end)
	return grip
end

--// window
local Window = {}
Window.__index = Window
local Tab = {}
Tab.__index = Tab
local Section = {}
Section.__index = Section

local TITLE_MODES = { "none", "shimmer", "wave" }

local RICH_ESCAPES = { ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;", ['"'] = "&quot;", ["'"] = "&apos;" }

local function hidden(characters, first, last)
	if first > last then
		return ""
	end
	return '<font transparency="1">' .. table.concat(characters, "", first, last) .. "</font>"
end

-- options: name, size, position, min_size, resizable, animate_title, dock, dock_name
function library:window(options)
	self:init()
	options = options or {}
	local name = options.name or options.title or "rainworld"
	local size = to_vector(options.size, Vector2.new(387, 554))
	local float = new_float({
		name = "menu",
		position = to_vector(options.position, Vector2.new(261, 112)),
		size = size,
		dock = options.dock,
		remember = false,
	})
	float.label = options.dock_name or "menu"
	local window = setmetatable({
		float = float,
		name = name,
		size = size,
		min_size = to_vector(options.min_size, Vector2.new(240, 200)),
		tabs = {},
		active = nil,
		title_mode = "none",
	}, Window)

	local body, content = box({
		Parent = float.holder,
		Name = "window",
		Size = fromOffset(size.X, size.Y),
	}, { { "window_outline", 2 }, { "window_inline", 1 }, { "window_background" } })
	window.body = body
	window.content = content

	-- Sits under everything: keeps clicks away from the game and drags the window.
	local sink = create("TextButton", { Parent = content, Name = "drag", Size = UDim2.new(1, 0, 1, 0) })
	float:drag_handle(sink)

	local title = text("TextLabel", {
		Parent = content,
		Name = "title",
		Size = fromOffset(0, 17),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = name,
		TextColor3 = fromRGB(255, 255, 255),
		ZIndex = 2,
	}, { size = "title", stroke = true })
	center(title, content, 7)
	window.title = title
	window.title_gradient = gradient(title, 0, GRADIENTS.title)

	window.tab_bar = create("Frame", {
		Parent = content,
		Name = "tabs",
		BackgroundTransparency = 1,
		Position = fromOffset(3, 26),
		Size = UDim2.new(1, -6, 0, 28),
		ZIndex = 2,
	})

	local _, pages = box({
		Parent = content,
		Name = "pages",
		Position = fromOffset(2, 62),
		Size = UDim2.new(1, -4, 1, -64),
		ZIndex = 2,
	}, { { "panel_outline", 1 }, { "panel_background" } })
	pages.ClipsDescendants = true
	window.pages = pages

	if options.resizable ~= false then
		resize_grip(float, body, function()
			return window.size
		end, function(requested)
			window:set_size(requested)
		end)
	end

	table.insert(state.windows, window)
	table.insert(float.shown_listeners, function()
		window:set_title_animation(window.title_mode)
	end)
	-- The wave bakes the outline colour into its rich text.
	table.insert(state.theme_listeners, function(key)
		if key == "stroke" and window.letters then
			window:set_title_animation(window.title_mode)
		end
	end)
	float:attach(body)

	local mode = options.animate_title
	if settings.title ~= nil then
		mode = settings.title
	end
	window:set_title_animation(mode)

	-- Dot-callable helpers kept for scripts written against similar libraries.
	window.set_menu_visibility = method(window, function(visible)
		library:set_open(visible)
	end)
	window.toggle_list = method(window, function(visible)
		if state.keybind_list then
			state.keybind_list.set_visible(visible)
		end
	end)
	window.toggle_watermark = method(window, function(visible)
		if state.watermark then
			state.watermark.set_visible(visible)
		end
	end)
	return window
end

function Window:set_visible(visible)
	self.float:set_visible(visible)
end

function Window:set_title(name)
	self.name = tostring(name)
	self.title.Text = self.name
	self:set_title_animation(self.title_mode)
end

-- mode: "none", "shimmer" (a highlight sweeping the gradient; engine-driven, no
-- Lua per frame) or "wave" (letters bobbing). Only runs while the window shows.
function Window:set_title_animation(mode)
	if mode == true then
		mode = "shimmer"
	elseif not table.find(TITLE_MODES, mode) then
		mode = "none"
	end
	self.title_mode = mode

	stop_tweens(self.title_gradient, { Offset = true })
	frame.unbind(self)
	if self.letters then
		destroy(self.letters)
		self.letters = nil
	end
	self.title_gradient.Offset = Vector2.new(0, 0)
	self.title.TextTransparency = 0
	self.title.TextStrokeTransparency = 0
	if library.unloaded or not self.float.shown or not animation.enabled then
		return
	end

	if mode == "shimmer" then
		self.title_gradient.Offset = Vector2.new(-0.35, 0)
		play(
			self.title_gradient,
			TweenInfo.new(2.4 / animation.speed, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Offset = Vector2.new(0.35, 0) }
		)
	elseif mode == "wave" then
		-- Each letter gets a copy of the whole title in which only that letter is
		-- drawn, so the letters keep their exact spacing while moving on their own.
		local characters = {}
		for character in string.gmatch(self.name, utf8.charpattern) do
			table.insert(characters, RICH_ESCAPES[character] or character)
		end
		local holder = create("Frame", {
			Parent = self.title,
			Name = "letters",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
		})
		local stroke = '<stroke color="#' .. theme.stroke:ToHex() .. '" thickness="1">'
		local labels, offsets = {}, {}
		for index, character in ipairs(characters) do
			if not string.match(character, "^%s$") then
				local label = text("TextLabel", {
					Parent = holder,
					RichText = true,
					Size = UDim2.new(1, 0, 1, 0),
					Text = hidden(characters, 1, index - 1) .. stroke .. character .. "</stroke>" .. hidden(
						characters,
						index + 1,
						#characters
					),
					TextColor3 = fromRGB(255, 255, 255),
				}, { size = "title" })
				gradient(label, 0, GRADIENTS.title)
				table.insert(labels, label)
			end
		end
		self.letters = holder
		self.title.TextTransparency = 1
		self.title.TextStrokeTransparency = 1
		local clock = 0
		frame.bind(self, function(delta)
			clock += delta * animation.speed
			for index, label in ipairs(labels) do
				local y = math.floor(math.sin(clock * 5 - index * 0.7) * 2 + 0.5)
				if offsets[index] ~= y then
					offsets[index] = y
					label.Position = fromOffset(0, y)
				end
			end
		end)
	end
end

function Window:set_size(size)
	size = clamp_size(size, self.min_size)
	if size == self.size then
		return
	end
	self.size = size
	self.body.Size = fromOffset(size.X, size.Y)
	self.float:set_size(size)
	self:layout_tabs()
	for _, tab in ipairs(self.tabs) do
		tab:layout()
	end
end

-- Equal cells across the bar. Underlines keep a 2px inset except on the first
-- tab's left edge, which sits flush with the page border exactly as designed.
function Window:layout_tabs()
	local count = #self.tabs
	local width = self.size.X - 12
	for index, tab in ipairs(self.tabs) do
		local left = math.floor((index - 1) * width / count)
		local right = math.floor(index * width / count)
		local inset = if index == 1 then 0 else 2
		tab.button.Position = fromOffset(left, 0)
		tab.button.Size = fromOffset(right - left, 28)
		tab.slot.Position = fromOffset(inset, 5)
		tab.slot.Size = fromOffset(right - left - inset - 2, 14)
		tab.line.Position = fromOffset(inset, 24)
		tab.line.Size = fromOffset(right - left - inset - 2, 4)
	end
end

function Window:select(tab, instant)
	if self.active == tab then
		return
	end
	popup.close()
	local previous = self.active
	self.active = tab
	if previous then
		previous.page.Visible = false
		tween(previous.active_line, { Size = UDim2.new(0, 0, 1, 0) }, if instant then 0 else 0.16)
	end
	tab.page.Visible = true
	tween(tab.active_line, { Size = UDim2.new(1, 0, 1, 0) }, if instant then 0 else 0.22, true)
	if not instant and animation.enabled then
		tab.page.Position = fromOffset(0, 8)
		tween(tab.page, { Position = fromOffset(0, 0) }, 0.22, true)
	end
	tab:layout()
end

-- options: name, columns (default 2)
function Window:tab(options)
	options = options or {}
	local tab = setmetatable({
		window = self,
		name = options.name or "tab",
		columns = {},
		dirty = false,
	}, Tab)

	local button = create("TextButton", { Parent = self.tab_bar, Name = tab.name, ClipsDescendants = true })
	tab.button = button
	-- The label is centred over the underline rather than the cell, as designed.
	tab.slot = create("Frame", { Parent = button, Name = "label", BackgroundTransparency = 1 })
	local label = text("TextLabel", {
		Parent = tab.slot,
		Size = fromOffset(0, 14),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = tab.name,
	}, { size = "tab", stroke = true })
	center(label, tab.slot, 0)
	tab.line = stripes({ Parent = button, Name = "line" }, "track_top", "track_bottom", 2)
	tab.active_line = stripes({
		Parent = tab.line,
		Name = "active",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0, 0, 1, 0),
		ClipsDescendants = true,
		ZIndex = 2,
	}, "accent_mid", "accent_dark", 2)

	tab.page = create("Frame", {
		Parent = self.pages,
		Name = tab.name,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
	})
	for index = 1, math.max(1, math.floor(options.columns or 2)) do
		tab.columns[index] = {
			sections = {},
			frame = create("ScrollingFrame", { Parent = tab.page, Name = "column" .. index }),
		}
	end

	table.insert(self.tabs, tab)
	self:layout_tabs()
	button.MouseButton1Click:Connect(function()
		self:select(tab)
	end)
	tab.open_tab = method(tab, function()
		self:select(tab)
	end)
	if not self.active then
		self:select(tab, true)
	end
	tab:layout()
	return tab
end

-- Column geometry from the design: 5px page padding, 7px between columns.
local PAGE_PADDING, COLUMN_GAP, SECTION_GAP = 5, 7, 10

function Tab:layout()
	local size = self.window.size
	local count = #self.columns
	local usable = size.X - 12 - PAGE_PADDING * 2 - COLUMN_GAP * (count - 1)
	for index, column in ipairs(self.columns) do
		local left = math.floor((index - 1) * usable / count)
		local right = math.floor(index * usable / count)
		column.frame.Position = fromOffset(PAGE_PADDING + left + COLUMN_GAP * (index - 1), 0)
		column.frame.Size = UDim2.new(0, math.max(right - left, 1), 1, 0)
	end
	self:arrange()
end

-- Stacks the sections of each column. The last one stretches to the bottom of
-- the page (as in the design) unless it was created with fill = false.
function Tab:arrange()
	self.dirty = false
	local available = self.window.size.Y - 72
	for _, column in ipairs(self.columns) do
		local y = PAGE_PADDING
		local count = #column.sections
		for index, section in ipairs(column.sections) do
			local height = section:content_height()
			if section.height then
				height = math.max(height, math.floor((available - PAGE_PADDING * 2) * section.height))
			elseif index == count and section.fill ~= false then
				height = math.max(height, available - PAGE_PADDING - y)
			end
			section.frame.Position = fromOffset(0, y)
			section.frame.Size = UDim2.new(1, 0, 0, height)
			y += height + SECTION_GAP
		end
		column.frame.CanvasSize = fromOffset(0, if count > 0 then y - SECTION_GAP + PAGE_PADDING else 0)
	end
end

function Tab:invalidate()
	if self.dirty then
		return
	end
	self.dirty = true
	task.defer(function()
		if self.dirty and not library.unloaded then
			self:arrange()
		end
	end)
end

-- Drag a section by its title to move it to another slot or column.
local function drag_section(section)
	local tab = section.tab
	local start = pointer()
	local lifted = false
	local grab, placeholder, target, slot

	-- Nearest column, then the slot given by the midpoints of its sections.
	local function locate(point)
		local nearest, distance = tab.columns[1], math.huge
		for _, column in ipairs(tab.columns) do
			local center = column.frame.AbsolutePosition.X + column.frame.AbsoluteSize.X / 2
			if math.abs(point.X - center) < distance then
				nearest, distance = column, math.abs(point.X - center)
			end
		end
		local index = 1
		for _, other in ipairs(nearest.sections) do
			if other ~= placeholder and point.Y > other.frame.AbsolutePosition.Y + other.frame.AbsoluteSize.Y / 2 then
				index += 1
			end
		end
		return nearest, index
	end

	local function place(column, index)
		if column == target and index == slot then
			return
		end
		if target then
			table.remove(target.sections, table.find(target.sections, placeholder))
		end
		target, slot = column, index
		table.insert(column.sections, math.min(index, #column.sections + 1), placeholder)
		placeholder.frame.Parent = column.frame
		tab:arrange()
	end

	begin_drag(function(point)
		if not lifted then
			if (point - start).Magnitude < 6 then
				return
			end
			lifted = true
			popup.close()
			local size = Vector2.new(section.frame.AbsoluteSize.X, section:content_height())
			grab = section.frame.AbsolutePosition - start
			local outline, fill = box({ Name = "placeholder" }, { { "accent_dark", 1 }, { "section_background" } })
			create("Frame", {
				Parent = fill,
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 0.82,
				Theme = { BackgroundColor3 = "accent" },
			})
			placeholder = {
				frame = outline,
				fill = false,
				content_height = function()
					return size.Y
				end,
			}
			for _, column in ipairs(tab.columns) do
				local index = table.find(column.sections, section)
				if index then
					table.remove(column.sections, index)
					place(column, index)
					break
				end
			end
			section.frame.Parent = state.layers.popups
			section.frame.Size = fromOffset(size.X, size.Y)
		end
		local origin = point + grab - state.root.AbsolutePosition
		section.frame.Position = fromOffset(origin.X, origin.Y)
		place(locate(point))
	end, function()
		if not lifted then
			return
		end
		target.sections[table.find(target.sections, placeholder)] = section
		section.frame.Parent = target.frame
		destroy(placeholder.frame)
		tab:arrange()
	end)
end

-- options: name, side ("left" | "right" | column index), fill, size (0-1 of the
-- page height), draggable
function Tab:section(options)
	options = options or {}
	local side = options.side
	local index = 1
	if type(side) == "number" then
		index = math.clamp(math.floor(side), 1, #self.columns)
	elseif type(side) == "string" and string.lower(side) == "right" then
		index = #self.columns
	end
	local column = self.columns[index]

	local section = setmetatable({
		tab = self,
		name = options.name or "section",
		fill = options.fill,
		height = if type(options.size) == "number" then math.clamp(options.size, 0, 1) else nil,
		count = 0,
	}, Section)

	local outer, fill = box({
		Parent = column.frame,
		Name = section.name,
		Size = UDim2.new(1, 0, 0, 40),
	}, { { "panel_outline", 1 }, { "section_inline", 1 }, { "section_background" } })
	section.frame = outer
	section.title = text("TextLabel", {
		Parent = outer,
		Name = "title",
		Position = fromOffset(6, -5),
		Size = fromOffset(0, 12),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = section.name,
		ZIndex = 3,
	}, { stroke = true })
	section.holder = create("Frame", {
		Parent = fill,
		Name = "elements",
		BackgroundTransparency = 1,
		Position = fromOffset(2, 6),
		Size = UDim2.new(1, -4, 1, -6),
	})
	section.list = create("UIListLayout", {
		Parent = section.holder,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	})
	section.list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		self:invalidate()
	end)
	if library.draggable_sections and options.draggable ~= false then
		local handle = create("TextButton", { Parent = section.title, Name = "move", Size = UDim2.new(1, 0, 1, 0) })
		handle.MouseButton1Down:Connect(function()
			drag_section(section)
		end)
	end

	table.insert(column.sections, section)
	self:invalidate()
	return section
end

-- Borders and padding around the element list: 8px above, 6px below.
function Section:content_height()
	return 8 + self.list.AbsoluteContentSize.Y + 6
end

-- Row frame for one element; `height` already includes any spacing below it.
function Section:row(name, height)
	self.count += 1
	return create("Frame", {
		Parent = self.holder,
		Name = name,
		BackgroundTransparency = 1,
		LayoutOrder = self.count,
		Size = UDim2.new(1, 0, 0, height),
	})
end

--// elements
local function register(object)
	if object.flag then
		library.options[object.flag] = object
	end
	return object
end

local function row_visibility(object, row)
	object.set_visible = method(object, function(visible)
		row.Visible = visible == true
	end)
end

-- Keybind list refresh is deferred so a burst of changes costs one rebuild.
local function refresh_keybind_list()
	local list = state.keybind_list
	if list then
		list.invalidate()
	end
end

-- Colour swatch: 15x10 with a 1px outline. options: flag, color, alpha, callback
local function new_colorpicker(parent, options, order)
	local object = {
		class = "colorpicker",
		flag = options.flag,
		color = options.color or options.default or fromRGB(255, 255, 255),
		alpha = math.clamp(options.alpha or 1, 0, 1),
		callback = options.callback,
	}
	local swatch = create("TextButton", {
		Parent = parent,
		Name = "color",
		BackgroundTransparency = 0,
		LayoutOrder = order,
		Size = fromOffset(15, 10),
		Theme = { BackgroundColor3 = "element_outline" },
	})
	local fill = create("Frame", {
		Parent = swatch,
		Position = fromOffset(1, 1),
		Size = fromOffset(13, 8),
		BackgroundColor3 = object.color,
	})

	local function set(color, alpha, silent)
		if typeof(color) == "Color3" then
			object.color = color
		end
		if type(alpha) == "number" then
			object.alpha = math.clamp(alpha, 0, 1)
		end
		fill.BackgroundColor3 = object.color
		if object.flag then
			flags[object.flag] = { color = object.color, alpha = object.alpha, transparency = 1 - object.alpha }
		end
		if picker.target == object then
			picker.sync()
		end
		if not silent then
			safe_call(object.callback, object.color, object.alpha)
		end
	end
	object.set = method(object, set)
	object.get = method(object, function()
		return object.color, object.alpha
	end)
	object.save = function()
		return { color = object.color:ToHex(), alpha = object.alpha }
	end
	object.load = function(data)
		if type(data) == "table" and type(data.color) == "string" then
			local ok, color = pcall(Color3.fromHex, data.color)
			if ok then
				set(color, tonumber(data.alpha) or 1)
			end
		end
	end
	swatch.MouseButton1Click:Connect(function()
		picker.open(object, swatch)
	end)
	set(object.color, object.alpha)
	return register(object)
end

local KEYBIND_MODES = { "toggle", "hold", "always" }

-- Keybind readout "[key]". Left click rebinds (escape clears), right click picks
-- the mode. options: flag, name, key, mode, callback, list (false hides it from the keybind list)
local function new_keybind(parent, options, order, fallback_name)
	local object = {
		class = "keybind",
		flag = options.flag,
		name = options.display or options.keybind_name or options.name or fallback_name or "keybind",
		key = options.key or options.default,
		mode = if table.find(KEYBIND_MODES, options.mode) then options.mode else "toggle",
		active = false,
		listed = options.list ~= false,
		callback = options.callback,
	}
	local button = text("TextButton", {
		Parent = parent,
		Name = "keybind",
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order,
		Size = fromOffset(0, 12),
		Text = "[none]",
	})
	local listening = false
	local reported = object.key

	local function write_flag()
		if object.flag then
			flags[object.flag] = { key = object.key, mode = object.mode, active = object.active }
		end
	end

	local function set_active(active, silent)
		active = active == true or object.mode == "always"
		if object.active == active then
			return
		end
		object.active = active
		write_flag()
		refresh_keybind_list()
		if not silent then
			safe_call(object.callback, active)
		end
	end

	local function refresh()
		button.Text = "[" .. (if listening then "..." else key_name(object.key)) .. "]"
		bind(button, "TextColor3", if listening then "accent_text" else "text")
		if options.hidden then
			button.Visible = listening or object.key ~= nil
		end
		write_flag()
		refresh_keybind_list()
		if object.key ~= reported then
			reported = object.key
			safe_call(options.changed, object.key)
		end
	end

	local function set_mode(mode)
		if not table.find(KEYBIND_MODES, mode) then
			return
		end
		object.mode = mode
		set_active(mode == "always")
		refresh()
	end

	-- Accepts a key (KeyCode / UserInputType / "none"), a mode name, an active
	-- boolean, or a { key, mode, active } table.
	local function set(value, mode)
		if typeof(value) == "EnumItem" then
			object.key = value
		elseif type(value) == "boolean" then
			set_active(value)
		elseif type(value) == "string" then
			if value == "none" then
				object.key = nil
			else
				set_mode(value)
			end
		elseif type(value) == "table" then
			if value.key ~= nil then
				object.key = if typeof(value.key) == "EnumItem" then value.key else nil
			end
			if value.mode then
				set_mode(value.mode)
			end
			if type(value.active) == "boolean" then
				set_active(value.active)
			end
		elseif value == nil and mode == nil then
			object.key = nil
		end
		if mode then
			set_mode(mode)
		end
		refresh()
	end

	object.set = method(object, set)
	object.set_mode = method(object, set_mode)
	object.set_active = set_active
	object.get = method(object, function()
		return object.key, object.mode, object.active
	end)
	object.save = function()
		return { key = serialize_key(object.key), mode = object.mode }
	end
	object.load = function(data)
		if type(data) == "table" then
			object.key = deserialize_key(data.key)
			set_mode(data.mode)
			refresh()
		end
	end

	local function stop_listening()
		listening = false
		state.capture = nil
		refresh()
	end

	-- Waits for the next key or mouse button and binds it (escape clears).
	local function listen()
		if listening then
			return
		end
		popup.close()
		if state.capture then
			state.capture.cancel()
		end
		listening = true
		refresh()
		state.capture = {
			cancel = stop_listening,
			handle = function(input)
				local kind = input.UserInputType
				if kind == Enum.UserInputType.Keyboard then
					local code = input.KeyCode
					object.key = if code == Enum.KeyCode.Escape or code == Enum.KeyCode.Backspace then nil else code
				elseif
					kind == Enum.UserInputType.MouseButton1
					or kind == Enum.UserInputType.MouseButton2
					or kind == Enum.UserInputType.MouseButton3
				then
					if kind == Enum.UserInputType.MouseButton1 and contains(button, pointer()) then
						return false
					end
					object.key = kind
				else
					return false
				end
				stop_listening()
				return true
			end,
		}
	end
	object.listen = listen

	button.MouseButton1Click:Connect(function()
		-- Clicking the readout again cancels the rebind.
		if listening then
			stop_listening()
		else
			listen()
		end
	end)
	button.MouseButton2Click:Connect(function()
		if listening or options.passive then
			return
		end
		list_popup.open({
			owner = object,
			items = KEYBIND_MODES,
			min_width = 54,
			selected = function(item)
				return item == object.mode
			end,
			pick = set_mode,
		}, button)
	end)

	-- Passive binds only store a key (the menu key); they are never triggered or listed.
	if not options.passive then
		table.insert(state.keybinds, object)
	end
	object.active = object.mode == "always"
	refresh()
	return register(object)
end

-- Right-aligned strip that holds swatches and keybind readouts on a row.
local function addon_strip(row)
	local strip = create("Frame", {
		Parent = row,
		Name = "addons",
		AnchorPoint = Vector2.new(1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -1, 0, 0),
		Size = UDim2.new(0, 0, 1, 0),
		ZIndex = 2,
	})
	create("UIListLayout", {
		Parent = strip,
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	})
	return strip
end

-- Gives `object` chainable :colorpicker() / :keybind() that land on its row and
-- keeps the row label clear of them.
local function attach_addons(object, row, label, label_offset)
	local strip = addon_strip(row)
	local count = 0
	strip:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local width = strip.AbsoluteSize.X
		label.Size = UDim2.new(1, -label_offset - (if width > 0 then width + 5 else 0), 1, 0)
	end)
	object.colorpicker = method(object, function(options)
		count += 1
		return new_colorpicker(strip, options or {}, count)
	end)
	object.keybind = method(object, function(options)
		count += 1
		local keybind = new_keybind(strip, options or {}, count, object.name)
		object.bind = object.bind or keybind
		return keybind
	end)
end

-- options: name, flag, default, callback
function Section:toggle(options)
	options = options or {}
	local toggle: { [string]: any } = {
		class = "toggle",
		name = options.name or "toggle",
		flag = options.flag,
		value = false,
		callback = options.callback,
	}
	local row = self:row("toggle", 12)
	local button = create("TextButton", { Parent = row, Size = UDim2.new(1, 0, 1, 0) })
	local _, inner = box({
		Parent = button,
		Position = fromOffset(1, 1),
		Size = fromOffset(10, 10),
	}, { { "element_outline", 1 }, { "element_background" } })
	inner.ClipsDescendants = true
	local fill = create("Frame", {
		Parent = inner,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = fromOffset(0, 0),
		Theme = { BackgroundColor3 = "accent_dark" },
	})
	local label = text("TextLabel", {
		Parent = button,
		Position = fromOffset(16, 0),
		Size = UDim2.new(1, -16, 1, 0),
		Text = toggle.name,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local function set(value, silent)
		value = value == true
		toggle.value = value
		if toggle.flag then
			flags[toggle.flag] = value
		end
		tween(fill, { Size = if value then fromOffset(8, 8) else fromOffset(0, 0) }, 0.16, true)
		if not silent then
			safe_call(toggle.callback, value)
		end
	end
	toggle.set = method(toggle, set)
	toggle.get = method(toggle, function()
		return toggle.value
	end)
	toggle.save = function()
		return toggle.value
	end
	toggle.load = function(value)
		set(value == true)
	end
	button.MouseButton1Click:Connect(function()
		set(not toggle.value)
	end)
	-- Right-click starts binding the toggle's keybind, if it has one.
	button.MouseButton2Click:Connect(function()
		if toggle.bind then
			toggle.bind.listen()
		end
	end)

	attach_addons(toggle, row, label, 16)
	row_visibility(toggle, row)
	self.last_toggle = toggle
	set(options.default == true)
	return register(toggle)
end

-- options: name, flag, min, max, interval, default, suffix, callback
-- A table default ({ low, high }) turns it into a two-thumb range slider.
function Section:slider(options)
	options = options or {}
	local minimum = options.min or options.minimum or 0
	local maximum = options.max or options.maximum or 100
	if maximum <= minimum then
		maximum = minimum + 1
	end
	local step = options.interval or options.decimal or options.step or 1
	local decimals = decimals_of(step)
	local is_range = type(options.default) == "table"
	local slider = {
		class = "slider",
		name = options.name or "slider",
		flag = options.flag,
		min = minimum,
		max = maximum,
		suffix = options.suffix or "",
		value = nil,
		callback = options.callback,
	}

	local row = self:row("slider", 27)
	text("TextLabel", {
		Parent = row,
		Position = fromOffset(7, 0),
		Size = UDim2.new(1, -14, 0, 12),
		Text = slider.name,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local track = stripes({
		Parent = row,
		Name = "track",
		Position = fromOffset(6, 14),
		Size = UDim2.new(1, -12, 0, 5),
	}, "track_top", "track_bottom", 3)
	local fill = stripes(
		{ Parent = track, Name = "fill", Size = UDim2.new(0, 0, 1, 0), ZIndex = 2 },
		"accent_mid",
		"accent_dark",
		3
	)
	-- A zero-width marker rides the end of the fill; the readout hangs centred under it.
	local marker = create("Frame", {
		Parent = track,
		Name = "marker",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 3),
		Size = fromOffset(0, 12),
		ZIndex = 3,
	})
	local readout = text("TextLabel", {
		Parent = marker,
		Size = fromOffset(0, 12),
		AutomaticSize = Enum.AutomaticSize.X,
	})
	-- Centred under the end of the fill, but kept inside the row at either end.
	local target = 0
	local function place_readout()
		local width, size = track.AbsoluteSize.X, readout.AbsoluteSize.X
		local x = target * width
		local left = math.clamp(x - math.floor(size / 2), -6, math.max(width + 6 - size, -6))
		readout.Position = fromOffset(math.floor(left - x + 0.5), 0)
	end
	readout:GetPropertyChangedSignal("AbsoluteSize"):Connect(place_readout)
	track:GetPropertyChangedSignal("AbsoluteSize"):Connect(place_readout)

	local minus = create(
		"TextButton",
		{ Parent = row, Name = "minus", Position = fromOffset(0, 11), Size = fromOffset(6, 11), ZIndex = 5 }
	)
	create(
		"Frame",
		{ Parent = minus, Position = fromOffset(0, 5), Size = fromOffset(5, 1), Theme = { BackgroundColor3 = "text" } }
	)
	local plus = create(
		"TextButton",
		{ Parent = row, Name = "plus", Position = UDim2.new(1, -6, 0, 11), Size = fromOffset(6, 11), ZIndex = 5 }
	)
	create(
		"Frame",
		{ Parent = plus, Position = fromOffset(1, 5), Size = fromOffset(5, 1), Theme = { BackgroundColor3 = "text" } }
	)
	create(
		"Frame",
		{ Parent = plus, Position = fromOffset(3, 3), Size = fromOffset(1, 5), Theme = { BackgroundColor3 = "text" } }
	)
	local grab = create(
		"TextButton",
		{ Parent = row, Name = "grab", Position = fromOffset(6, 9), Size = UDim2.new(1, -12, 0, 14), ZIndex = 4 }
	)

	local function snap(value)
		value = math.clamp(round(tonumber(value) or minimum, step), minimum, maximum)
		return tonumber(string.format("%." .. decimals .. "f", value))
	end
	local function format(value)
		return string.format("%." .. decimals .. "f", value)
	end
	local function alpha_of(value)
		return (value - minimum) / (maximum - minimum)
	end

	local function set(value, silent, duration)
		local low, high
		if is_range then
			local source = if type(value) == "table" then value else slider.value
			low, high = snap(source[1] or source.min), snap(source[2] or source.max)
			if low > high then
				low, high = high, low
			end
			slider.value = { low, high }
			readout.Text = format(low) .. " - " .. format(high) .. slider.suffix
		else
			low, high = minimum, snap(value)
			slider.value = high
			readout.Text = format(high) .. slider.suffix
		end
		local from, to = alpha_of(low), alpha_of(high)
		duration = duration or 0.18
		tween(fill, { Position = UDim2.new(from, 0, 0, 0), Size = UDim2.new(to - from, 0, 1, 0) }, duration)
		target = if is_range then (from + to) / 2 else to
		tween(marker, { Position = UDim2.new(target, 0, 0, 3) }, duration)
		place_readout()
		if slider.flag then
			flags[slider.flag] = slider.value
		end
		if not silent then
			safe_call(slider.callback, slider.value)
		end
	end
	slider.set = method(slider, set)
	slider.get = method(slider, function()
		return slider.value
	end)
	slider.save = function()
		return slider.value
	end
	slider.load = function(value)
		if is_range == (type(value) == "table") then
			set(value)
		end
	end

	local function nudge(direction)
		if is_range then
			set({ slider.value[1], slider.value[2] + step * direction })
		else
			set(slider.value + step * direction)
		end
	end
	minus.MouseButton1Click:Connect(function()
		nudge(-1)
	end)
	plus.MouseButton1Click:Connect(function()
		nudge(1)
	end)
	grab.MouseButton1Down:Connect(function()
		local thumb
		begin_drag(function(point)
			local fraction = math.clamp((point.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
			local value = minimum + (maximum - minimum) * fraction
			if is_range then
				-- The first movement decides which end is being dragged.
				if not thumb then
					thumb = if math.abs(value - slider.value[1]) < math.abs(value - slider.value[2]) then 1 else 2
				end
				local pair = { slider.value[1], slider.value[2] }
				pair[thumb] = value
				if pair[1] > pair[2] then
					thumb = 3 - thumb
				end
				set(pair, false, 0.06)
			elseif snap(value) ~= slider.value then
				set(value, false, 0.06)
			end
		end)
	end)

	row_visibility(slider, row)
	if is_range then
		slider.value = { minimum, maximum }
		set(options.default, false, 0)
	else
		set(options.default or minimum, false, 0)
	end
	return register(slider)
end

-- options: name, flag, items, default, multi, callback
function Section:dropdown(options)
	options = options or {}
	local multi = options.multi == true
	local dropdown = {
		class = "dropdown",
		name = options.name or "dropdown",
		flag = options.flag,
		items = options.items or {},
		multi = multi,
		value = if multi then {} else nil,
		callback = options.callback,
	}

	local row = self:row("dropdown", 32)
	text("TextLabel", {
		Parent = row,
		Position = fromOffset(7, 0),
		Size = UDim2.new(1, -14, 0, 12),
		Text = dropdown.name,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local outer, inner = box({
		Parent = row,
		Name = "field",
		Position = fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 15),
	}, { { "field_outline", 1 }, { "element_background" } })
	local readout = text("TextLabel", {
		Parent = inner,
		Position = fromOffset(2, 1),
		Size = UDim2.new(1, -14, 0, 12),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	create("Frame", {
		Parent = inner,
		Position = UDim2.new(1, -9, 0, 6),
		Size = fromOffset(7, 1),
		Theme = { BackgroundColor3 = "text" },
	})
	local stem = create("Frame", {
		Parent = inner,
		Position = UDim2.new(1, -6, 0, 3),
		Size = fromOffset(1, 7),
		Theme = { BackgroundColor3 = "text" },
	})
	local button = create("TextButton", { Parent = outer, Size = UDim2.new(1, 0, 1, 0), ZIndex = 3 })

	local function is_selected(item)
		if multi then
			return table.find(dropdown.value, item) ~= nil
		end
		return dropdown.value == item
	end

	local function set(value, silent)
		if multi then
			local chosen = {}
			if type(value) == "table" then
				-- Kept in item order so saved configs are stable.
				for _, item in ipairs(dropdown.items) do
					if table.find(value, item) then
						table.insert(chosen, item)
					end
				end
			elseif value ~= nil and table.find(dropdown.items, value) then
				chosen[1] = value
			end
			dropdown.value = chosen
			local names = {}
			for index, item in ipairs(chosen) do
				names[index] = tostring(item)
			end
			readout.Text = if #chosen > 0 then table.concat(names, ", ") else "-"
		else
			dropdown.value = value
			readout.Text = if value ~= nil then tostring(value) else "-"
		end
		if dropdown.flag then
			flags[dropdown.flag] = dropdown.value
		end
		if not silent then
			safe_call(dropdown.callback, dropdown.value)
		end
	end
	dropdown.set = method(dropdown, set)
	dropdown.get = method(dropdown, function()
		return dropdown.value
	end)
	dropdown.save = function()
		return dropdown.value
	end
	dropdown.load = function(value)
		if multi == (type(value) == "table") then
			set(value)
		end
	end
	dropdown.refresh_options = method(dropdown, function(items)
		dropdown.items = items or {}
		if list_popup.config and list_popup.config.owner == dropdown then
			popup.close()
		end
		if multi then
			set(dropdown.value, true)
		elseif dropdown.value ~= nil and not table.find(dropdown.items, dropdown.value) then
			set(nil, true)
		end
	end)

	button.MouseButton1Click:Connect(function()
		list_popup.open({
			owner = dropdown,
			items = dropdown.items,
			multi = multi,
			selected = is_selected,
			pick = function(item)
				if multi then
					local chosen = table.clone(dropdown.value)
					local index = table.find(chosen, item)
					if index then
						table.remove(chosen, index)
					else
						table.insert(chosen, item)
					end
					set(chosen)
				else
					set(item)
				end
			end,
			closed = function()
				stem.Visible = true
			end,
		}, outer)
		-- "+" while closed, "-" while the list is open.
		stem.Visible = not (list_popup.config ~= nil and list_popup.config.owner == dropdown)
	end)

	row_visibility(dropdown, row)
	set(options.default)
	return register(dropdown)
end

-- A 1px outlined gradient button. Used by sections and by list rows. `plain`
-- drops the grey text outline (the small list buttons in the design have none).
local function make_button(properties, name, callback, plain)
	properties.Theme = { BackgroundColor3 = "button_outline" }
	properties.ClipsDescendants = true
	local outer = create("Frame", properties)
	local face = create("Frame", {
		Parent = outer,
		Position = fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2),
		BackgroundColor3 = fromRGB(255, 255, 255),
	})
	gradient(face, 90, GRADIENTS.button)
	local glow = create("Frame", {
		Parent = outer,
		Position = fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2),
		BackgroundColor3 = fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	local label = text("TextLabel", {
		Parent = outer,
		Size = fromOffset(0, 14),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = name,
		ZIndex = 3,
	}, { size = "button", stroke = if plain then nil else "button_stroke" })
	-- The design rounds the half pixel up on the small list buttons, down elsewhere.
	center(label, outer, 0, plain)
	local button = create("TextButton", { Parent = outer, Size = UDim2.new(1, 0, 1, 0), ZIndex = 4 })
	button.MouseEnter:Connect(function()
		tween(glow, { BackgroundTransparency = 0.95 }, 0.1)
	end)
	button.MouseLeave:Connect(function()
		tween(glow, { BackgroundTransparency = 1 }, 0.1)
	end)
	button.MouseButton1Down:Connect(function()
		glow.BackgroundTransparency = 0.88
		tween(glow, { BackgroundTransparency = 0.95 }, 0.25)
	end)
	button.MouseButton1Click:Connect(function()
		safe_call(callback)
	end)
	return outer, label
end

-- options: name, callback
function Section:button(options)
	options = options or {}
	local object = { class = "button", name = options.name or options.text or "button" }
	local row = self:row("button", 19)
	local _, label = make_button({ Parent = row, Size = UDim2.new(1, 0, 0, 16) }, object.name, options.callback)
	object.set = method(object, function(name)
		object.name = tostring(name)
		label.Text = object.name
	end)
	row_visibility(object, row)
	return object
end

-- Several buttons sharing one row: section:button_row({ { name, callback }, ... })
function Section:button_row(buttons)
	local row = self:row("buttons", 19)
	local count = #buttons
	local gap = 4
	for index, entry in ipairs(buttons) do
		make_button({
			Parent = row,
			Position = UDim2.new((index - 1) / count, if index == 1 then 0 else gap / 2, 0, 0),
			Size = UDim2.new(1 / count, -(if index == 1 or index == count then gap / 2 else gap), 0, 16),
		}, entry.name or entry.text or tostring(index), entry.callback)
	end
	return row
end

-- options: name, flag, default, placeholder, live (fire on every change), callback
function Section:textbox(options)
	options = options or {}
	local textbox = {
		class = "textbox",
		name = options.name,
		flag = options.flag,
		value = "",
		callback = options.callback,
	}
	local has_name = type(options.name) == "string" and options.name ~= ""
	local row = self:row("textbox", if has_name then 32 else 18)
	if has_name then
		text("TextLabel", {
			Parent = row,
			Position = fromOffset(7, 0),
			Size = UDim2.new(1, -14, 0, 12),
			Text = options.name,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	local _, inner = box({
		Parent = row,
		Name = "field",
		Position = fromOffset(0, if has_name then 14 else 0),
		Size = UDim2.new(1, 0, 0, 15),
	}, { { "field_outline", 1 }, { "element_background" } })
	local input = text("TextBox", {
		Parent = inner,
		Position = fromOffset(2, 1),
		Size = UDim2.new(1, -4, 0, 12),
		ClipsDescendants = true,
		PlaceholderText = options.placeholder or options.placeholdertext or options.holder or options.holdertext or "",
		Theme = { PlaceholderColor3 = "text_dim" },
	})

	local function set(value, silent)
		value = tostring(if value == nil then "" else value)
		textbox.value = value
		if input.Text ~= value then
			input.Text = value
		end
		if textbox.flag then
			flags[textbox.flag] = value
		end
		if not silent then
			safe_call(textbox.callback, value)
		end
	end
	textbox.set = method(textbox, set)
	textbox.get = method(textbox, function()
		return textbox.value
	end)
	textbox.save = textbox.get
	textbox.load = function(value)
		if type(value) == "string" then
			set(value)
		end
	end
	if options.live then
		input:GetPropertyChangedSignal("Text"):Connect(function()
			if input.Text ~= textbox.value then
				set(input.Text)
			end
		end)
	else
		input.FocusLost:Connect(function()
			set(input.Text)
		end)
	end

	row_visibility(textbox, row)
	set(options.default or "", options.default == nil)
	return register(textbox)
end

-- options: name (or text), wrap
function Section:label(options)
	options = options or {}
	self.count += 1
	local label = text("TextLabel", {
		Parent = self.holder,
		Name = "label",
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = self.count,
		Size = UDim2.new(1, 0, 0, 12),
		Text = options.name or options.text or "",
		TextWrapped = options.wrap ~= false,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	create("UIPadding", { Parent = label, PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) })
	local object = { class = "label" }
	object.set = method(object, function(value)
		label.Text = tostring(value)
	end)
	row_visibility(object, label)
	return object
end

local function addon_row(section, name, label_text)
	local row = section:row(name, 12)
	local label = text("TextLabel", {
		Parent = row,
		Position = fromOffset(7, 0),
		Size = UDim2.new(1, -7, 1, 0),
		Text = label_text,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local strip = addon_strip(row)
	strip:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		label.Size = UDim2.new(1, -7 - strip.AbsoluteSize.X - 5, 1, 0)
	end)
	return row, strip
end

-- With a name the swatch gets its own labelled row; without one it joins the
-- toggle created just before it. options: name, flag, color, alpha, callback
function Section:colorpicker(options)
	options = options or {}
	if not options.name and self.last_toggle then
		return self.last_toggle.colorpicker(options)
	end
	local row, strip = addon_row(self, "colorpicker", options.name or "color")
	local object = new_colorpicker(strip, options, 1)
	row_visibility(object, row)
	return object
end

-- options: name, flag, key, mode, callback, list
function Section:keybind(options)
	options = options or {}
	if not options.name and self.last_toggle then
		return self.last_toggle.keybind(options)
	end
	local row, strip = addon_row(self, "keybind", options.name or "keybind")
	local object = new_keybind(strip, options, 1)
	row_visibility(object, row)
	return object
end

--// dock (top bar)
-- options: name. Every float registers a toggle here; dock:add() makes custom ones.
function library:dock(options)
	self:init()
	if state.dock then
		return state.dock
	end
	options = options or {}
	local dock = { items = {} }
	state.dock = dock

	local bar = create("Frame", {
		Parent = state.layers.dock,
		Name = "dock",
		Size = UDim2.new(1, 0, 0, 19),
		Visible = self.open,
		Theme = { BackgroundColor3 = "float_outline" },
	})
	local face = create("Frame", {
		Parent = bar,
		Size = UDim2.new(1, 0, 0, 18),
		Theme = { BackgroundColor3 = "bar_background" },
	})
	create("TextButton", { Parent = face, Size = UDim2.new(1, 0, 1, 0) })
	local strip = create("Frame", {
		Parent = face,
		BackgroundTransparency = 1,
		Position = fromOffset(5, 1),
		Size = UDim2.new(1, -10, 0, 16),
		ZIndex = 2,
	})
	create("UIListLayout", {
		Parent = strip,
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 7),
	})
	local brand = text("TextLabel", {
		Parent = strip,
		Name = "brand",
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 0,
		Size = fromOffset(0, 16),
		Text = options.name or "rainworld.club",
		TextColor3 = fromRGB(255, 255, 255),
	}, { font = "bold", size = "brand", stroke = true })
	gradient(brand, 0, GRADIENTS.brand)

	-- options: name, default, callback(enabled), toggle. Returns { set, get }.
	-- toggle = false makes a plain button: it stays white and just runs callback().
	function dock:add(item_options)
		local momentary = item_options.toggle == false
		local item = { name = item_options.name or "item", value = not momentary and item_options.default == true }
		local button = text("TextButton", {
			Parent = strip,
			Name = item.name,
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = #self.items + 1,
			Size = fromOffset(0, 15),
			Text = item.name,
			TextXAlignment = Enum.TextXAlignment.Center,
		}, { size = "dock", color = if item.value then "accent_text" else "text" })
		local function show(value)
			item.value = value == true
			bind(button, "TextColor3", if item.value then "accent_text" else "text", 0.12)
		end
		item.show = show
		item.set = method(item, function(value)
			show(value)
			safe_call(item_options.callback, item.value)
		end)
		item.get = method(item, function()
			return item.value
		end)
		button.MouseButton1Click:Connect(function()
			if momentary then
				safe_call(item_options.callback)
			else
				item.set(not item.value)
			end
		end)
		table.insert(self.items, item)
		return item
	end

	function dock:add_float(float)
		local item = self:add({
			name = float.label or float.name,
			default = float.enabled,
			callback = function(enabled)
				float:set_visible(enabled)
				float:remember()
			end,
		})
		table.insert(float.listeners, item.show)
		return item
	end

	function dock:refresh()
		local open = library.open
		if open then
			bar.Visible = true
			if animation.enabled then
				bar.Position = fromOffset(0, -19)
			end
			tween(bar, { Position = fromOffset(0, 0) }, 0.2, true)
		else
			bar.Visible = false
		end
	end

	for _, float in ipairs(state.floats) do
		if float.dock and float.body then
			dock:add_float(float)
		end
	end
	return dock
end

--// watermark
-- options: name (brand), text (string or function returning the stats text),
-- rate (seconds between refreshes), position, visible
function library:watermark(options)
	self:init()
	if state.watermark then
		return state.watermark
	end
	options = options or {}
	local watermark = { name = options.name or "rainworld.club", source = options.text, rate = options.rate or 0.5 }
	state.watermark = watermark

	local float = new_float({
		name = "watermark",
		position = to_vector(options.position, Vector2.new(124, 85)),
		hud = true,
		visible = options.visible,
		dock = options.dock,
	})
	watermark.float = float
	local outer, inner = box({
		Parent = float.holder,
		Name = "watermark",
		Size = fromOffset(120, 21),
	}, { { "float_outline", 1 }, { "window_background" } })
	local handle = create("TextButton", { Parent = inner, Size = UDim2.new(1, 0, 1, 0) })
	float:drag_handle(handle)
	local brand = text("TextLabel", {
		Parent = inner,
		Position = fromOffset(10, 4),
		Size = fromOffset(0, 12),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = watermark.name,
		TextColor3 = fromRGB(255, 255, 255),
		ZIndex = 2,
	}, { font = "bold", size = "brand", stroke = true })
	gradient(brand, 0, GRADIENTS.brand)
	local stats = text("TextLabel", {
		Parent = inner,
		Position = fromOffset(23, 2),
		Size = fromOffset(0, 14),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 2,
	}, { size = "tab", color = "text_soft", stroke = true })

	-- 11px left, 13px between brand and stats, 10px right, as measured in the design.
	local function fit()
		local brand_width = brand.AbsoluteSize.X
		local stats_width = stats.AbsoluteSize.X
		local gap = if stats.Text ~= "" then 13 else 0
		stats.Position = fromOffset(10 + brand_width + gap, 2)
		outer.Size = fromOffset(11 + brand_width + gap + stats_width + 10, 21)
	end
	brand:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	stats:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	local frames, elapsed, fps = 0, 0, 60
	local function describe()
		local source = watermark.source
		if type(source) == "function" then
			local ok, result = pcall(source, fps)
			return if ok then tostring(result) else ""
		elseif source ~= nil then
			return tostring(source)
		end
		local memory, ping = 0, 0
		pcall(function()
			memory = math.floor(Stats:GetTotalMemoryUsageMb() + 0.5)
			ping = math.floor(LocalPlayer:GetNetworkPing() * 1000 + 0.5)
		end)
		return string.format("ram: %dmb | %d fps | %d ping", memory, fps, ping)
	end
	local function update()
		local value = describe()
		if stats.Text ~= value then
			stats.Text = value
		end
	end
	local function run(active)
		if active then
			frames, elapsed = 0, 0
			frame.bind("watermark", function(delta)
				frames += 1
				elapsed += delta
				if elapsed >= watermark.rate then
					fps = math.floor(frames / elapsed + 0.5)
					frames, elapsed = 0, 0
					update()
				end
			end)
		else
			frame.unbind("watermark")
		end
	end
	table.insert(float.shown_listeners, run)

	watermark.set_name = method(watermark, function(name)
		watermark.name = tostring(name)
		brand.Text = watermark.name
	end)
	watermark.set_text = method(watermark, function(source)
		watermark.source = source
		update()
	end)
	watermark.set_visible = method(watermark, function(visible)
		float:set_visible(visible)
	end)

	float:attach(outer)
	update()
	fit()
	run(float.shown)
	return watermark
end

--// keybind list
-- options: name, position, visible, active_only (list only binds that are active)
function library:keybind_list(options)
	self:init()
	if state.keybind_list then
		return state.keybind_list
	end
	options = options or {}
	local list: { [string]: any } = { active_only = options.active_only == true, rows = {}, dirty = false }
	state.keybind_list = list

	local float = new_float({
		name = "keybinds",
		position = to_vector(options.position, Vector2.new(123, 269)),
		hud = true,
		visible = options.visible,
		dock = options.dock,
	})
	list.float = float
	local outer, inner = box({
		Parent = float.holder,
		Name = "keybinds",
		Size = fromOffset(130, 19),
	}, { { "popup_outline", 1 }, { "window_background" } })
	local handle = create("TextButton", { Parent = inner, Size = UDim2.new(1, 0, 1, 0) })
	float:drag_handle(handle)
	local title = text("TextLabel", {
		Parent = inner,
		Position = fromOffset(3, 1),
		Size = fromOffset(0, 14),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = options.name or "keybinds",
		TextColor3 = fromRGB(255, 255, 255),
		ZIndex = 2,
	}, { size = "tab", stroke = true })
	gradient(title, 0, GRADIENTS.title)

	local function row(index)
		local label = list.rows[index]
		if not label then
			label = text("TextLabel", {
				Parent = inner,
				Position = fromOffset(2, 16 + (index - 1) * 15),
				Size = fromOffset(0, 14),
				AutomaticSize = Enum.AutomaticSize.X,
				ZIndex = 2,
			}, { size = "tab" })
			label:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				list.invalidate()
			end)
			list.rows[index] = label
		end
		return label
	end

	local function rebuild()
		list.dirty = false
		local count, widest = 0, title.AbsoluteSize.X
		for _, keybind in ipairs(state.keybinds) do
			if keybind.listed and (keybind.active or not list.active_only) then
				count += 1
				local label = row(count)
				local value = keybind.name .. " - [" .. key_name(keybind.key) .. "]"
				if label.Text ~= value then
					label.Text = value
				end
				label.Visible = true
				bind(label, "TextColor3", if keybind.active then "accent_text" else "text")
				widest = math.max(widest, label.AbsoluteSize.X)
			end
		end
		for index = count + 1, #list.rows do
			list.rows[index].Visible = false
		end
		-- 34px tall with one row in the design: 2 + 14 title, 15 per row, 3 below.
		outer.Size = fromOffset(math.max(130, widest + 10), 19 + count * 15)
	end

	function list.invalidate()
		if list.dirty then
			return
		end
		list.dirty = true
		task.defer(function()
			if list.dirty and not library.unloaded then
				rebuild()
			end
		end)
	end

	list.set_visible = method(list, function(visible)
		float:set_visible(visible)
	end)
	float:attach(outer)
	rebuild()
	return list
end

--// notifications
local notifications = { active = {}, holder = nil }

local function reflow_notifications()
	local y = 0
	for _, entry in ipairs(notifications.active) do
		tween(entry.frame, { Position = UDim2.new(1, 0, 0, y) }, 0.22, true)
		y += 25
	end
end

-- options: text, time (seconds, default 4). Returns { close }.
function library:notification(options)
	self:init()
	options = if type(options) == "table" then options else { text = tostring(options) }
	if not notifications.holder then
		notifications.holder = create("Frame", {
			Parent = state.layers.notifications,
			Name = "notifications",
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -10, 0, 29),
			Size = fromOffset(0, 0),
		})
	end
	local lifetime = math.max(tonumber(options.time) or 4, 0.2)
	local entry = { closed = false }
	local outer, inner = box({
		Parent = notifications.holder,
		Name = "notification",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, #notifications.active * 25),
		Size = fromOffset(60, 21),
		ClipsDescendants = true,
	}, { { "float_outline", 1 }, { "window_background" } })
	entry.frame = outer
	local label = text("TextLabel", {
		Parent = inner,
		Position = fromOffset(8, 2),
		Size = fromOffset(0, 14),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = options.text or options.name or "",
		ZIndex = 2,
	}, { size = "tab", stroke = true })
	local progress = stripes({
		Parent = inner,
		Position = UDim2.new(0, 0, 1, -2),
		Size = UDim2.new(1, 0, 0, 2),
		ZIndex = 2,
	}, "accent_mid", "accent_dark", 1)
	local button = create("TextButton", { Parent = inner, Size = UDim2.new(1, 0, 1, 0), ZIndex = 3 })

	local width = 0
	local function fit()
		if entry.closed then
			return
		end
		local target = label.AbsoluteSize.X + 18
		if target ~= width then
			width = target
			tween(outer, { Size = fromOffset(width, 21) }, 0.2, true)
		end
	end
	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	local function close()
		if entry.closed or library.unloaded then
			return
		end
		entry.closed = true
		local index = table.find(notifications.active, entry)
		if index then
			table.remove(notifications.active, index)
		end
		after(tween(outer, { Size = fromOffset(0, 21) }, 0.18), function()
			destroy(outer)
		end)
		reflow_notifications()
	end
	entry.close = close
	button.MouseButton1Click:Connect(close)

	table.insert(notifications.active, entry)
	outer.Size = fromOffset(0, 21)
	fit()
	play(progress, TweenInfo.new(lifetime, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) })
	task.delay(lifetime, close)
	return entry
end
library.notify = library.notification

--// panels (small floating windows)
-- style "framed": 2px outline, 1px inline, title inside the frame (lua, theme).
-- style "header": black header strip with a framed body below it (esp preview).
local function new_panel(options)
	local size = options.size
	local float = new_float({
		name = options.name,
		position = options.position,
		size = size,
		visible = options.visible,
		dock = options.dock,
	})
	float.label = options.label or options.name
	local body, content, title_parent, title_y
	if options.style == "header" then
		body = create("Frame", {
			Parent = float.holder,
			Name = options.name,
			Size = fromOffset(size.X, size.Y),
			Theme = { BackgroundColor3 = "float_outline" },
		})
		local _, inner = box({
			Parent = body,
			Position = fromOffset(2, 37),
			Size = UDim2.new(1, -4, 1, -39),
			ZIndex = 2,
		}, { { "window_inline", 1 }, { "window_background" } })
		content, title_parent, title_y = inner, body, 10
	else
		body, content = box({
			Parent = float.holder,
			Name = options.name,
			Size = fromOffset(size.X, size.Y),
		}, { { "float_outline", 2 }, { "float_inline", 1 }, { "window_background" } })
		title_parent, title_y = content, 3
	end
	-- The drag surface goes under the content: in the framed style that means
	-- inside the innermost frame, because the border frames are nested.
	local sink = create("TextButton", {
		Parent = if options.style == "header" then body else content,
		Name = "drag",
		Size = UDim2.new(1, 0, 1, 0),
	})
	float:drag_handle(sink)
	local title = text("TextLabel", {
		Parent = title_parent,
		Name = "title",
		Size = fromOffset(0, 17),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = options.title or options.name,
		TextColor3 = fromRGB(255, 255, 255),
		ZIndex = 3,
	}, { font = "bold", size = "panel_title", stroke = true })
	center(title, title_parent, title_y)
	gradient(title, 0, GRADIENTS.title)
	local panel = { float = float, body = body, content = content, title = title, size = size }
	if options.resizable ~= false then
		local minimum = options.min_size or Vector2.new(150, 110)
		resize_grip(float, body, function()
			return panel.size
		end, function(requested)
			panel.size = clamp_size(requested, minimum)
			body.Size = fromOffset(panel.size.X, panel.size.Y)
			float:set_size(panel.size)
		end)
	end
	return panel
end

--// esp preview
local PREVIEW_ELEMENTS = { "box", "name", "healthbar", "distance", "flags" }

-- A ViewportFrame showing a copy of the local character (or any model handed to
-- set_model) with optional overlay elements for previewing visual settings.
-- options: name, position, size, model, rotation (degrees), spin, visible
function library:esp_preview(options)
	self:init()
	options = options or {}
	local size = to_vector(options.size, Vector2.new(229, 352))
	local panel = new_panel({
		name = "preview",
		label = options.label or "preview",
		title = options.name or "esp preview",
		style = "header",
		position = to_vector(options.position, Vector2.new(655, 112)),
		size = size,
		visible = options.visible,
		dock = options.dock,
	})
	local preview = {
		float = panel.float,
		model = nil,
		custom = false,
		rotation = options.rotation or 0,
		elements = {},
	}

	local viewport = create("ViewportFrame", {
		Parent = panel.content,
		Name = "viewport",
		Size = UDim2.new(1, 0, 1, 0),
		Ambient = fromRGB(190, 190, 190),
		LightColor = fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-1, -1, -1),
	})
	local world = create("WorldModel", { Parent = viewport })
	local camera = create("Camera", { Parent = viewport, FieldOfView = 40 })
	viewport.CurrentCamera = camera
	preview.viewport, preview.world, preview.camera = viewport, world, camera

	local overlay = create("Frame", {
		Parent = panel.content,
		Name = "overlay",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 2,
	})

	-- Overlay pieces. Everything is hidden until a script enables it.
	local function outline(color_key)
		local line = create("Frame", { Parent = overlay, BackgroundTransparency = 1, Visible = false })
		local stroke = create("UIStroke", {
			Parent = line,
			Thickness = 1,
			LineJoinMode = Enum.LineJoinMode.Miter,
			Color = if color_key then theme[color_key] else fromRGB(255, 255, 255),
		})
		return line, stroke
	end
	local box_outer = outline("stroke")
	local box_inner = outline("stroke")
	local box_line, box_stroke = outline(nil)
	local name_label = text("TextLabel", {
		Parent = overlay,
		Size = fromOffset(200, 12),
		AnchorPoint = Vector2.new(0.5, 1),
		Text = LocalPlayer.DisplayName,
		TextColor3 = fromRGB(255, 255, 255),
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	}, { stroke = true })
	local distance_label = text("TextLabel", {
		Parent = overlay,
		Size = fromOffset(200, 12),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "7m",
		TextColor3 = fromRGB(255, 255, 255),
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	}, { stroke = true })
	local flags_label = text("TextLabel", {
		Parent = overlay,
		Size = fromOffset(100, 12),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = "",
		TextColor3 = fromRGB(255, 255, 255),
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = false,
	}, { stroke = true })
	local health_back = create("Frame", {
		Parent = overlay,
		Visible = false,
		Theme = { BackgroundColor3 = "stroke" },
	})
	local health_fill = create("Frame", {
		Parent = health_back,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 1, 1, -1),
		Size = UDim2.new(1, -2, 1, -2),
		BackgroundColor3 = fromRGB(110, 255, 120),
	})

	for _, name in ipairs(PREVIEW_ELEMENTS) do
		preview.elements[name] = { enabled = false, color = fromRGB(255, 255, 255) }
	end
	preview.elements.healthbar.color = fromRGB(110, 255, 120)
	local health = 1
	local bounds = nil -- { min = Vector2, max = Vector2 } of the model on the overlay

	local function draw()
		local elements = preview.elements
		local visible = bounds ~= nil
		box_line.Visible = visible and elements.box.enabled
		box_outer.Visible, box_inner.Visible = box_line.Visible, box_line.Visible
		name_label.Visible = visible and elements.name.enabled
		distance_label.Visible = visible and elements.distance.enabled
		flags_label.Visible = visible and elements.flags.enabled
		health_back.Visible = visible and elements.healthbar.enabled
		box_stroke.Color = elements.box.color
		name_label.TextColor3 = elements.name.color
		distance_label.TextColor3 = elements.distance.color
		flags_label.TextColor3 = elements.flags.color
		health_fill.BackgroundColor3 = elements.healthbar.color
		if not bounds then
			return
		end
		local x, y = math.floor(bounds.min.X + 0.5), math.floor(bounds.min.Y + 0.5)
		local width = math.max(math.floor(bounds.max.X - bounds.min.X + 0.5), 4)
		local height = math.max(math.floor(bounds.max.Y - bounds.min.Y + 0.5), 4)
		box_line.Position, box_line.Size = fromOffset(x, y), fromOffset(width, height)
		box_outer.Position, box_outer.Size = fromOffset(x - 1, y - 1), fromOffset(width + 2, height + 2)
		box_inner.Position, box_inner.Size = fromOffset(x + 1, y + 1), fromOffset(width - 2, height - 2)
		name_label.Position = fromOffset(x + math.floor(width / 2), y - 4)
		distance_label.Position = fromOffset(x + math.floor(width / 2), y + height + 3)
		flags_label.Position = fromOffset(x + width + 5, y - 2)
		health_back.Position, health_back.Size = fromOffset(x - 7, y - 1), fromOffset(4, height + 2)
		health_fill.Size = UDim2.new(1, -2, math.clamp(health, 0, 1), -2)
	end

	-- Places the camera in front of the model and records where the model's
	-- bounding box lands on screen. Projection is done by hand because
	-- WorldToViewportPoint is not reliable for cameras inside a ViewportFrame.
	local function frame_model()
		local model = preview.model
		local view = viewport.AbsoluteSize
		if not model or view.X < 2 or view.Y < 2 then
			bounds = nil
			draw()
			return
		end
		local pivot, extents = model:GetBoundingBox()
		local half = extents / 2
		local tangent = math.tan(math.rad(camera.FieldOfView) / 2)
		local aspect = view.X / view.Y
		local radius = math.max(half.X, half.Z)
		local reach = math.max(half.Y * 1.22 / tangent, radius * 1.9 / (tangent * aspect)) + radius
		local facing = (pivot * CFrame.Angles(0, math.rad(preview.rotation), 0)).LookVector
		local eye = CFrame.lookAt(pivot.Position + facing * reach, pivot.Position)
		camera.CFrame = eye

		local low_x, low_y, high_x, high_y = math.huge, math.huge, -math.huge, -math.huge
		for sx = -1, 1, 2 do
			for sy = -1, 1, 2 do
				for sz = -1, 1, 2 do
					local point = eye:PointToObjectSpace(pivot * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
					local depth = math.max(-point.Z, 0.05)
					local px = (point.X / (depth * tangent * aspect) + 1) / 2 * view.X
					local py = (1 - point.Y / (depth * tangent)) / 2 * view.Y
					low_x, low_y = math.min(low_x, px), math.min(low_y, py)
					high_x, high_y = math.max(high_x, px), math.max(high_y, py)
				end
			end
		end
		bounds = { min = Vector2.new(low_x, low_y), max = Vector2.new(high_x, high_y) }
		draw()
	end

	local function clear()
		if preview.model then
			preview.model:Destroy()
			preview.model = nil
		end
	end

	-- Copies a character so the copy can live in the viewport: characters are not
	-- Archivable by default, and scripts or sounds must not come along.
	local function copy_character(character)
		local archivable = character.Archivable
		character.Archivable = true
		local ok, copy = pcall(function()
			return character:Clone()
		end)
		character.Archivable = archivable
		if not ok or not copy then
			return nil
		end
		for _, descendant in ipairs(copy:GetDescendants()) do
			if
				descendant:IsA("LuaSourceContainer")
				or descendant:IsA("Sound")
				or descendant:IsA("ForceField")
				or descendant:IsA("BillboardGui")
			then
				descendant:Destroy()
			elseif descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end
		local humanoid = copy:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		return copy
	end

	local function show(model)
		clear()
		if model then
			model.Parent = world
			preview.model = model
		end
		frame_model()
	end

	-- Rebuilds the copy of the local character (skipped while a custom model is set).
	preview.refresh = method(preview, function()
		if preview.custom or library.unloaded then
			return
		end
		local character = LocalPlayer.Character
		show(if character then copy_character(character) else nil)
	end)

	-- Shows `model` instead of the character. Pass nil to go back to the character.
	-- The model is cloned unless clone is false, in which case it is moved in.
	preview.set_model = method(preview, function(model, clone)
		if model == nil then
			preview.custom = false
			preview.refresh()
			return
		end
		preview.custom = true
		if clone ~= false then
			local ok, copy = pcall(function()
				return model:Clone()
			end)
			model = if ok then copy else nil
		end
		show(model)
	end)

	preview.set_rotation = method(preview, function(degrees)
		preview.rotation = degrees % 360
		frame_model()
	end)

	-- preview.set("box", true, Color3) : element is one of box, name, healthbar, distance, flags
	preview.set = method(preview, function(element, enabled, color)
		local entry = preview.elements[element]
		if not entry then
			return
		end
		if type(enabled) == "boolean" then
			entry.enabled = enabled
		end
		if typeof(color) == "Color3" then
			entry.color = color
		end
		draw()
	end)
	preview.set_name = method(preview, function(value)
		name_label.Text = tostring(value)
	end)
	preview.set_distance = method(preview, function(value)
		distance_label.Text = tostring(value)
	end)
	preview.set_flags = method(preview, function(list)
		flags_label.Text = if type(list) == "table" then table.concat(list, "\n") else tostring(list or "")
	end)
	preview.set_health = method(preview, function(fraction)
		health = tonumber(fraction) or 1
		draw()
	end)
	preview.set_visible = method(preview, function(visible)
		panel.float:set_visible(visible)
	end)

	-- Drag across the viewport to turn the model.
	local turn =
		create("TextButton", { Parent = panel.content, Name = "turn", Size = UDim2.new(1, 0, 1, 0), ZIndex = 3 })
	turn.MouseButton1Down:Connect(function()
		local start, origin = pointer(), preview.rotation
		panel.float:focus()
		begin_drag(function(point)
			preview.set_rotation(origin + (point.X - start.X) * 1.2)
		end)
	end)

	local function spin(active)
		if active and options.spin then
			frame.bind(preview, function(delta)
				preview.rotation = (preview.rotation + delta * 40) % 360
				frame_model()
			end)
		else
			frame.unbind(preview)
		end
	end
	table.insert(panel.float.shown_listeners, spin)

	viewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(frame_model)
	track(LocalPlayer.CharacterAdded:Connect(function()
		task.delay(1, preview.refresh)
	end))
	track(LocalPlayer.CharacterAppearanceLoaded:Connect(function()
		preview.refresh()
	end))

	panel.float:attach(panel.body)
	if options.model then
		preview.set_model(options.model)
	else
		preview.refresh()
	end
	spin(panel.float.shown)
	return preview
end

--// list window
local LIST_HEIGHT = 17

-- A floating list with per-row action buttons (the "lua" window of the design).
-- options: name, label, position, size, items, actions = { { name, callback(item) } }, callback(item)
function library:list(options)
	self:init()
	options = options or {}
	local panel = new_panel({
		name = options.name or "list",
		label = options.label,
		title = options.title or options.name or "list",
		position = to_vector(options.position, Vector2.new(655, 475)),
		size = to_vector(options.size, Vector2.new(229, 191)),
		visible = options.visible,
		dock = options.dock,
	})
	local list: { [string]: any } =
		{ float = panel.float, items = {}, selected = nil, rows = {}, callback = options.callback }

	local scroll = create("ScrollingFrame", {
		Parent = panel.content,
		Name = "rows",
		Position = fromOffset(0, 27),
		Size = UDim2.new(1, 0, 1, -27),
		ZIndex = 2,
	})

	-- One strip of action buttons, moved onto whichever row is selected.
	local actions = create("Frame", {
		Name = "actions",
		AnchorPoint = Vector2.new(1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -1, 0, 1),
		Size = fromOffset(0, 15),
		ZIndex = 3,
	})
	create("UIListLayout", {
		Parent = actions,
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	})
	-- Known up front: AbsoluteSize is not reliable while the strip is unparented.
	local actions_width = 0
	for index, action in ipairs(options.actions or {}) do
		local name = tostring(action.name or index)
		local width = math.max(23, #name * 6 + 5)
		actions_width += width + (if index > 1 then 2 else 0)
		make_button(
			{
				Parent = actions,
				LayoutOrder = index,
				Size = fromOffset(width, 15),
			},
			name,
			function()
				if list.selected ~= nil then
					safe_call(action.callback, list.selected)
				end
			end,
			true
		)
	end

	local function row(index)
		local entry = list.rows[index]
		if entry then
			return entry
		end
		local button = create("TextButton", {
			Parent = scroll,
			Position = fromOffset(0, (index - 1) * LIST_HEIGHT),
			Size = UDim2.new(1, 0, 0, LIST_HEIGHT),
			Theme = { BackgroundColor3 = "highlight" },
		})
		local label = text("TextLabel", {
			Parent = button,
			Position = fromOffset(5, 0),
			Size = UDim2.new(1, -10, 0, 14),
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, { size = "button", stroke = true })
		entry = { button = button, label = label, item = nil }
		list.rows[index] = entry
		button.MouseButton1Click:Connect(function()
			if entry.item ~= nil then
				list.select(entry.item)
			end
		end)
		return entry
	end

	local function render()
		actions.Parent = nil
		for index, item in ipairs(list.items) do
			local entry = row(index)
			local selected = item == list.selected
			entry.item = item
			entry.button.Visible = true
			entry.button.BackgroundTransparency = if selected then 0.89 else 1
			entry.label.Text = tostring(item)
			entry.label.Size = UDim2.new(1, if selected then -12 - actions_width else -10, 0, 14)
			bind(entry.label, "TextColor3", if selected then "text_selected" else "text")
			if selected then
				actions.Parent = entry.button
			end
		end
		for index = #list.items + 1, #list.rows do
			list.rows[index].button.Visible = false
			list.rows[index].item = nil
		end
		scroll.CanvasSize = fromOffset(0, #list.items * LIST_HEIGHT)
	end

	list.select = method(list, function(item, silent)
		if item ~= nil and not table.find(list.items, item) then
			return
		end
		list.selected = item
		render()
		if not silent then
			safe_call(list.callback, item)
		end
	end)
	list.set_items = method(list, function(items)
		list.items = table.clone(items or {})
		if list.selected ~= nil and not table.find(list.items, list.selected) then
			list.selected = nil
		end
		render()
	end)
	list.add = method(list, function(item)
		if not table.find(list.items, item) then
			table.insert(list.items, item)
			render()
		end
	end)
	list.remove = method(list, function(item)
		local index = table.find(list.items, item)
		if index then
			table.remove(list.items, index)
			if list.selected == item then
				list.selected = nil
			end
			render()
		end
	end)
	list.get = method(list, function()
		return list.selected
	end)
	list.set_visible = method(list, function(visible)
		panel.float:set_visible(visible)
	end)

	table.insert(state.unload_callbacks, function()
		actions:Destroy()
	end)
	panel.float:attach(panel.body)
	list.set_items(options.items)
	if options.default ~= nil then
		list.select(options.default, true)
	end
	return list
end

--// theme window
local THEME_ORDER = {
	"accent_mid",
	"accent_dark",
	"accent_text",
	"highlight",
	"gradient_mid",
	"brand_mid",
	"text",
	"text_soft",
	"text_selected",
	"text_dim",
	"stroke",
	"button_stroke",
	"window_outline",
	"window_inline",
	"window_background",
	"panel_outline",
	"panel_background",
	"section_inline",
	"section_background",
	"element_outline",
	"element_background",
	"field_outline",
	"track_top",
	"track_bottom",
	"button_outline",
	"button_top",
	"button_bottom",
	"bar_background",
	"float_outline",
	"float_inline",
	"popup_outline",
	"bar_outline",
}

function library:get_theme()
	local data = {}
	for key, color in pairs(theme) do
		data[key] = color:ToHex()
	end
	return HttpService:JSONEncode(data)
end

-- Accepts the JSON from get_theme() or a { key = Color3 | hex } table.
function library:load_theme(source)
	local data = source
	if type(source) == "string" then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(source)
		end)
		data = if ok then decoded else nil
	end
	if type(data) ~= "table" then
		return false
	end
	local changes = {}
	for key, value in pairs(data) do
		if type(value) == "string" then
			local ok, color = pcall(Color3.fromHex, value)
			value = if ok then color else nil
		end
		if typeof(value) == "Color3" then
			changes[key] = value
		end
	end
	apply_theme(changes)
	return true
end

function library:save_theme()
	return files.write(self.directory .. "/theme.json", self:get_theme())
end

function library:reset_theme()
	self:load_theme(DEFAULT_THEME)
	files.delete(self.directory .. "/theme.json")
end

-- Its own window, as the design notes ask. The first row drives the whole accent
-- family; the rest edit single colours.
function library:theme_window(options)
	self:init()
	options = options or {}
	local panel = new_panel({
		name = options.name or "theme",
		label = options.label,
		title = options.title or options.name or "theme",
		position = to_vector(options.position, Vector2.new(891, 112)),
		size = to_vector(options.size, Vector2.new(229, 250)),
		visible = options.visible,
		dock = options.dock,
	})
	local window = { float = panel.float }
	local scroll = create("ScrollingFrame", {
		Parent = panel.content,
		Name = "rows",
		Position = fromOffset(0, 27),
		Size = UDim2.new(1, 0, 1, -48),
		ZIndex = 2,
	})
	local holder = create("Frame", {
		Parent = scroll,
		BackgroundTransparency = 1,
		Position = fromOffset(4, 0),
		Size = UDim2.new(1, -8, 1, 0),
	})
	local swatches = {}

	local function add_row(index, label_text, key, apply)
		local row = create("Frame", {
			Parent = holder,
			BackgroundTransparency = 1,
			Position = fromOffset(0, (index - 1) * 14),
			Size = UDim2.new(1, 0, 0, 12),
		})
		text("TextLabel", {
			Parent = row,
			Position = fromOffset(1, 0),
			Size = UDim2.new(1, -24, 1, 0),
			Text = label_text,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local strip = addon_strip(row)
		swatches[key] = new_colorpicker(strip, {
			color = theme[key],
			callback = function(color)
				if theme[key] ~= color then
					apply(color)
				end
			end,
		}, 1)
	end

	add_row(1, "accent", "accent", function(color)
		library:set_accent(color)
	end)
	for index, key in ipairs(THEME_ORDER) do
		add_row(index + 1, string.gsub(key, "_", " "), key, function(color)
			library:update_theme(key, color)
		end)
	end
	scroll.CanvasSize = fromOffset(0, (#THEME_ORDER + 1) * 14 + 2)

	make_button(
		{
			Parent = panel.content,
			Position = UDim2.new(0, 4, 1, -19),
			Size = UDim2.new(0.5, -6, 0, 15),
			ZIndex = 3,
		},
		"save",
		function()
			library:save_theme()
			library:notification({ text = "theme saved" })
		end
	)
	make_button(
		{
			Parent = panel.content,
			Position = UDim2.new(0.5, 2, 1, -19),
			Size = UDim2.new(0.5, -6, 0, 15),
			ZIndex = 3,
		},
		"reset",
		function()
			library:reset_theme()
		end
	)

	-- Keeps the swatches in step with theme changes made anywhere else.
	table.insert(state.theme_listeners, function(key, color)
		local swatch = swatches[key]
		if swatch and swatch.color ~= color then
			swatch.set(color, 1, true)
		end
	end)

	window.set_visible = method(window, function(visible)
		panel.float:set_visible(visible)
	end)
	panel.float:attach(panel.body)
	return window
end

--// configs
local function config_folder()
	return library.directory .. "/configs"
end

-- Config names become file names: keep them to letters, digits, space, - and _.
local function clean_name(name)
	if type(name) ~= "string" then
		return nil
	end
	name = string.gsub(string.gsub(name, "[^%w _%-]", ""), "^%s*(.-)%s*$", "%1")
	return if name ~= "" then name else nil
end

-- Every flagged element as a JSON string.
function library:get_config()
	local data = {}
	for flag, object in pairs(self.options) do
		if object.save then
			data[flag] = object.save()
		end
	end
	return HttpService:JSONEncode(data)
end

-- Applies a JSON string from get_config(). Unknown flags are ignored.
function library:load_config(source)
	local ok, data = pcall(function()
		return HttpService:JSONDecode(source)
	end)
	if not ok or type(data) ~= "table" then
		return false
	end
	for flag, value in pairs(data) do
		local object = self.options[flag]
		if object and object.load then
			local loaded, message = pcall(object.load, value)
			if not loaded then
				warn("[rainworld] could not load '" .. tostring(flag) .. "': " .. tostring(message))
			end
		end
	end
	return true
end

function library:save_config(name)
	name = clean_name(name)
	if not name then
		return false
	end
	files.folder(config_folder())
	return files.write(config_folder() .. "/" .. name .. ".json", self:get_config())
end

function library:read_config(name)
	name = clean_name(name)
	local source = name and files.read(config_folder() .. "/" .. name .. ".json")
	return source ~= nil and self:load_config(source)
end

function library:delete_config(name)
	name = clean_name(name)
	if name then
		files.delete(config_folder() .. "/" .. name .. ".json")
		if self:get_autoload() == name then
			self:set_autoload(nil)
		end
	end
end

function library:list_configs()
	local names = {}
	for _, file in ipairs(files.list(config_folder())) do
		local name = string.match(file, "^(.+)%.json$")
		if name then
			table.insert(names, name)
		end
	end
	return names
end

-- The autoload config is applied by load_autoload(), which a script calls once
-- its interface is built.
function library:set_autoload(name)
	name = clean_name(name)
	if name then
		files.write(self.directory .. "/autoload.txt", name)
	else
		files.delete(self.directory .. "/autoload.txt")
	end
end

function library:get_autoload()
	return clean_name(files.read(self.directory .. "/autoload.txt"))
end

function library:load_autoload()
	local name = self:get_autoload()
	return name ~= nil and self:read_config(name)
end

--// persistent interface settings
local settings_dirty = false

function save_settings()
	if settings_dirty then
		return
	end
	settings_dirty = true
	task.defer(function()
		settings_dirty = false
		if library.unloaded then
			return
		end
		settings.animations = animation.enabled
		settings.style = animation.style
		settings.speed = animation.speed
		settings.menu_key = serialize_key(library.menu_key)
		files.write(library.directory .. "/settings.json", HttpService:JSONEncode(settings))
	end)
end

local function load_settings()
	local source = files.read(library.directory .. "/settings.json")
	if not source then
		return
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(source)
	end)
	if not ok or type(data) ~= "table" then
		return
	end
	if type(data.animations) == "boolean" then
		animation.enabled = data.animations
	end
	if EASING[data.style] then
		animation.style = data.style
	end
	if type(data.speed) == "number" then
		animation.speed = math.clamp(data.speed, 0.25, 4)
	end
	local menu_key = deserialize_key(data.menu_key)
	if menu_key then
		library.menu_key = menu_key
	end
	if table.find(TITLE_MODES, data.title) then
		settings.title = data.title
	end
	if type(data.floats) == "table" then
		settings.floats = data.floats
	end
end

function library:set_animation(options)
	if type(options.enabled) == "boolean" then
		animation.enabled = options.enabled
	end
	if EASING[options.style] then
		animation.style = options.style
	end
	if type(options.speed) == "number" then
		animation.speed = math.clamp(options.speed, 0.25, 4)
	end
	for _, window in ipairs(state.windows) do
		window:set_title_animation(window.title_mode)
	end
	save_settings()
end

-- Adds the settings sections (configs on the left, interface options on the
-- right) to options.tab, or to a new tab called options.name ("settings").
function Window:settings(options)
	options = options or {}
	local window = self
	local tab = options.tab or self:tab({ name = options.name or "settings" })

	local configs = tab:section({ name = "configs", side = "left" })
	local name_box = configs:textbox({ name = "name", placeholder = "config name" })
	local saved
	local status = nil
	local function refresh()
		saved.refresh_options(library:list_configs())
		local autoload = library:get_autoload()
		status.set("autoload: " .. (autoload or "none"))
	end
	local function chosen()
		return clean_name(name_box.get()) or saved.get()
	end
	saved = configs:dropdown({
		name = "saved",
		items = library:list_configs(),
		callback = function(value)
			if value then
				name_box.set(value, true)
			end
		end,
	})
	configs:button_row({
		{
			name = "save",
			callback = function()
				local name = chosen()
				if name and library:save_config(name) then
					refresh()
					saved.set(name, true)
					library:notification({ text = "saved config '" .. name .. "'" })
				else
					library:notification({ text = "enter a config name first" })
				end
			end,
		},
		{
			name = "load",
			callback = function()
				local name = chosen()
				if name and library:read_config(name) then
					library:notification({ text = "loaded config '" .. name .. "'" })
				else
					library:notification({ text = "config not found" })
				end
			end,
		},
	})
	configs:button_row({
		{
			name = "delete",
			callback = function()
				local name = chosen()
				if name then
					library:delete_config(name)
					name_box.set("", true)
					refresh()
					library:notification({ text = "deleted config '" .. name .. "'" })
				end
			end,
		},
		{
			name = "refresh",
			callback = function()
				refresh()
			end,
		},
	})
	configs:button_row({
		{
			name = "set autoload",
			callback = function()
				local name = chosen()
				if name then
					library:set_autoload(name)
					refresh()
				end
			end,
		},
		{
			name = "clear autoload",
			callback = function()
				library:set_autoload(nil)
				refresh()
			end,
		},
	})
	status = configs:label({ name = "autoload: " .. (library:get_autoload() or "none") })

	local menu = tab:section({ name = "menu", side = "right" })
	local menu_bind
	menu_bind = menu:keybind({
		name = "menu key",
		key = library.menu_key,
		passive = true,
		changed = function(key)
			-- Never left unbound: a closed menu could not be opened again.
			if key == nil then
				menu_bind.set(library.menu_key)
				return
			end
			library.menu_key = key
			save_settings()
		end,
	})
	menu:toggle({
		name = "animations",
		default = animation.enabled,
		callback = function(value)
			library:set_animation({ enabled = value })
		end,
	})
	menu:dropdown({
		name = "animation style",
		items = { "smooth", "spring", "elastic" },
		default = animation.style,
		callback = function(value)
			if value then
				library:set_animation({ style = value })
			end
		end,
	})
	menu:slider({
		name = "animation speed",
		min = 0.5,
		max = 2,
		interval = 0.1,
		default = animation.speed,
		suffix = "x",
		callback = function(value)
			library:set_animation({ speed = value })
		end,
	})
	menu:dropdown({
		name = "title animation",
		items = TITLE_MODES,
		default = window.title_mode,
		callback = function(value)
			if value then
				settings.title = value
				window:set_title_animation(value)
				save_settings()
			end
		end,
	})
	if state.keybind_list then
		menu:toggle({
			name = "keybind list",
			default = state.keybind_list.float.enabled,
			callback = function(value)
				state.keybind_list.set_visible(value)
				state.keybind_list.float:remember()
			end,
		})
	end
	menu:button({
		name = "unload",
		callback = function()
			library:unload()
		end,
	})
	return tab
end

--// lifecycle
local function handle_input_began(input, processed)
	local capture = state.capture
	if capture and capture.handle(input) then
		return
	end
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
		local point = pointer()
		popup.outside_click(point)
		focus_float_at(point)
	end
	-- Typing in a text box or clicking interface the game already handled.
	if processed then
		return
	end
	if input_matches(input, library.menu_key) then
		library:set_open(not library.open)
	end
	for _, keybind in ipairs(state.keybinds) do
		if input_matches(input, keybind.key) then
			if keybind.mode == "toggle" then
				keybind.set_active(not keybind.active)
			elseif keybind.mode == "hold" then
				keybind.set_active(true)
			end
		end
	end
end

local function handle_input_ended(input)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
		end_drag()
	end
	for _, keybind in ipairs(state.keybinds) do
		if keybind.mode == "hold" and keybind.active and input_matches(input, keybind.key) then
			keybind.set_active(false)
		end
	end
end

-- Builds the ScreenGui on first use. Called by every constructor, so scripts
-- never need to call it themselves.
function library:init()
	if state.gui then
		return
	end
	if self.unloaded then
		error("[rainworld] the library was unloaded; load it again to create a new interface", 2)
	end
	files.folder(self.directory)
	files.folder(self.directory .. "/configs")
	files.folder(self.directory .. "/fonts")
	load_settings()
	local saved_theme = files.read(self.directory .. "/theme.json")
	if saved_theme then
		self:load_theme(saved_theme)
	end

	for key, source in pairs(self.font_sources) do
		local font, real = load_font(source)
		self.fonts[key] = font
		if not real then
			for size_key, size in pairs(FALLBACK_SIZES[key] or {}) do
				self.text_sizes[size_key] = size
			end
		end
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "rainworld"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 9999
	state.gui = gui

	local root =
		create("Frame", { Parent = gui, Name = "root", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0) })
	state.root = root
	for index, name in ipairs({ "floats", "dock", "popups", "notifications" }) do
		state.layers[name] = create("Frame", {
			Parent = root,
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = index,
		})
	end
	-- A visible Modal button frees the mouse in first person while the menu is open.
	state.modal = create(
		"TextButton",
		{ Parent = root, Name = "modal", Modal = true, Size = fromOffset(0, 0), Visible = self.open }
	)

	local parent = self.parent
	if not parent then
		local ok, core = pcall(function()
			local container = game:GetService("CoreGui")
			local _ = container.Name
			return container
		end)
		parent = if ok then core else LocalPlayer:WaitForChild("PlayerGui")
	end
	local parented = pcall(function()
		gui.Parent = parent
	end)
	if not parented then
		gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	end

	track(UserInputService.InputBegan:Connect(handle_input_began))
	track(UserInputService.InputEnded:Connect(handle_input_ended))
	rawset(environment, GLOBAL_KEY, self)
end

-- Shows or hides the menu. HUD pieces (watermark, keybind list) stay visible.
function library:set_open(open)
	open = open == true
	if self.open == open or not state.gui then
		self.open = open
		return
	end
	self.open = open
	popup.close()
	end_drag()
	if state.capture then
		state.capture.cancel()
	end
	for _, float in ipairs(state.floats) do
		float:refresh()
	end
	if state.dock then
		state.dock:refresh()
	end
	state.modal.Visible = open
end

function library:toggle()
	self:set_open(not self.open)
end

-- What the library currently holds; handy for checking that nothing leaks.
function library:stats()
	local bindings, tweens = 0, 0
	for _ in pairs(state.bindings) do
		bindings += 1
	end
	for _ in pairs(state.tweens) do
		tweens += 1
	end
	return {
		bindings = bindings,
		tweens = tweens,
		frame_jobs = frame.count,
		connections = #state.connections,
		floats = #state.floats,
		keybinds = #state.keybinds,
	}
end

-- Runs when the library unloads, for scripts to stop their own loops.
function library:on_unload(callback)
	table.insert(state.unload_callbacks, callback)
end

-- Removes every instance, connection, tween and per-frame job the library made.
function library:unload()
	if self.unloaded then
		return
	end
	for _, callback in ipairs(state.unload_callbacks) do
		safe_call(callback)
	end
	popup.current = nil
	state.capture = nil
	state.drag = nil
	self.unloaded = true

	if frame.connection then
		frame.connection:Disconnect()
		frame.connection = nil
	end
	table.clear(frame.jobs)
	table.clear(frame.queued)
	frame.count = 0

	for _, connection in ipairs(state.connections) do
		connection:Disconnect()
	end
	for _, running in pairs(state.tweens) do
		for _, handle in pairs(running) do
			handle:Cancel()
		end
	end
	if state.gui then
		state.gui:Destroy()
	end
	for _, key in ipairs({
		"connections",
		"bindings",
		"tweens",
		"floats",
		"keybinds",
		"windows",
		"theme_listeners",
		"unload_callbacks",
		"layers",
	}) do
		table.clear(state[key])
	end
	state.gui, state.root, state.modal, state.dock, state.keybind_list, state.watermark = nil, nil, nil, nil, nil, nil
	table.clear(self.options)
	if rawget(environment, GLOBAL_KEY) == self then
		rawset(environment, GLOBAL_KEY, nil)
	end
end

return library
