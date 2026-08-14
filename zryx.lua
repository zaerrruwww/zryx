-- ZRYX
-- Standalone client-side utility for the Roblox experience Violence District.
-- Version: 1.1.0

local VERSION = "1.1.0"
local SUPPORTED_PLACE_IDS = {
	[93978595733734] = true,
}

local STORAGE_FOLDER = "ZRYX"
local SETTINGS_FILE = STORAGE_FOLDER .. "/settings.json"
local SNAPSHOT_FILE = STORAGE_FOLDER .. "/attributes.json"
local IGNORED_SERVERS_FILE = STORAGE_FOLDER .. "/ignored_servers.json"

local FINISH_DELAY = 4
local FINISH_CONFIRM_TIMEOUT = 12
local CANDIDATE_IGNORE_SECONDS = 180
local FAILED_IGNORE_SECONDS = 600
local TELEPORT_TIMEOUT = 8

local function getGlobalEnvironment()
	if type(getgenv) == "function" then
		local ok, environment = pcall(getgenv)
		if ok and type(environment) == "table" then
			return environment
		end
	end

	return _G
end

local GLOBAL_ENV = getGlobalEnvironment()

local function getGlobal(name)
	local value = GLOBAL_ENV[name]
	if value == nil and GLOBAL_ENV ~= _G then
		value = _G[name]
	end
	return value
end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	warn("ZRYX must run from a Roblox client.")
	return
end

if not SUPPORTED_PLACE_IDS[game.PlaceId] then
	warn(string.format("ZRYX only supports Violence District (current PlaceId: %s).", tostring(game.PlaceId)))
	return
end

local previous = GLOBAL_ENV.__ZRYX__
if type(previous) == "table" and type(previous.Unload) == "function" then
	pcall(previous.Unload)
	task.wait()
end

local state = {
	running = true,
	status = "Starting...",
	connections = {},
	ui = nil,
	roundActive = Workspace:FindFirstChild("Map") ~= nil,
	roundId = 0,
	farmToken = 0,
	farmBusy = false,
	farmTaskId = 0,
	farmAttemptedMap = nil,
	farmUnsupportedMap = nil,
	ignoredServers = {},
	snapshot = nil,
	teleport = {
		active = false,
		failed = false,
		id = nil,
		originJobId = nil,
	},
	hop = {
		running = false,
		forceUntil = 0,
	},
	settings = {
		autoFarm = false,
		serverHop = false,
		autoExecute = false,
		webhook = false,
		minPlayers = 1,
		maxPlayers = 3,
		scriptUrl = "",
	},
	webhookUrl = "",
}

local function addConnection(connection)
	table.insert(state.connections, connection)
	return connection
end

local function getFileCapability(name)
	local value = getGlobal(name)
	return type(value) == "function" and value or nil
end

local storageReady = false

local function initializeStorage()
	local isfolder = getFileCapability("isfolder")
	local makefolder = getFileCapability("makefolder")
	local isfile = getFileCapability("isfile")
	local readfile = getFileCapability("readfile")
	local writefile = getFileCapability("writefile")

	if not isfolder or not makefolder or not isfile or not readfile or not writefile then
		return false
	end

	local ok = pcall(function()
		if not isfolder(STORAGE_FOLDER) then
			makefolder(STORAGE_FOLDER)
		end
	end)

	return ok
end

local function readJson(path)
	if not storageReady then
		return nil
	end

	local isfile = getFileCapability("isfile")
	local readfile = getFileCapability("readfile")
	if not isfile or not readfile then
		return nil
	end

	local ok, contents = pcall(function()
		if not isfile(path) then
			return nil
		end
		return readfile(path)
	end)
	if not ok or type(contents) ~= "string" or contents == "" then
		return nil
	end

	local decoded, value = pcall(function()
		return HttpService:JSONDecode(contents)
	end)
	if decoded and type(value) == "table" then
		return value
	end

	return nil
end

local function writeJson(path, value)
	if not storageReady then
		return false
	end

	local writefile = getFileCapability("writefile")
	if not writefile then
		return false
	end

	local encoded, contents = pcall(function()
		return HttpService:JSONEncode(value)
	end)
	if not encoded then
		return false
	end

	return pcall(writefile, path, contents)
end

local function clampNumber(value, fallback, minimum, maximum)
	value = tonumber(value)
	if not value then
		return fallback
	end
	return math.clamp(math.floor(value), minimum, maximum)
end

local function loadSettings()
	local saved = readJson(SETTINGS_FILE)
	if type(saved) ~= "table" then
		return
	end

	state.settings.autoFarm = saved.autoFarm == true
	state.settings.serverHop = saved.serverHop == true
	state.settings.autoExecute = saved.autoExecute == true
	state.settings.webhook = saved.webhook == true
	state.settings.minPlayers = clampNumber(saved.minPlayers, 1, 1, 20)
	state.settings.maxPlayers = clampNumber(saved.maxPlayers, 3, state.settings.minPlayers, 20)
	state.settings.scriptUrl = type(saved.scriptUrl) == "string" and saved.scriptUrl or ""
end

local function saveSettings()
	writeJson(SETTINGS_FILE, {
		version = 1,
		autoFarm = state.settings.autoFarm,
		serverHop = state.settings.serverHop,
		autoExecute = state.settings.autoExecute,
		webhook = state.settings.webhook,
		minPlayers = state.settings.minPlayers,
		maxPlayers = state.settings.maxPlayers,
		scriptUrl = state.settings.scriptUrl,
	})
end

local function loadSnapshot()
	local saved = readJson(SNAPSHOT_FILE)
	if type(saved) ~= "table" or tonumber(saved.userId) ~= LocalPlayer.UserId then
		return nil
	end

	return {
		killerChance = tonumber(saved.killerChance),
		exp = tonumber(saved.exp),
		screws = tonumber(saved.screws),
		gears = tonumber(saved.gears),
	}
end

local function saveSnapshot(snapshot)
	return writeJson(SNAPSHOT_FILE, {
		version = 1,
		userId = LocalPlayer.UserId,
		killerChance = snapshot.killerChance,
		exp = snapshot.exp,
		screws = snapshot.screws,
		gears = snapshot.gears,
		updatedAt = os.time(),
	})
end

local function loadIgnoredServers()
	local saved = readJson(IGNORED_SERVERS_FILE)
	if type(saved) ~= "table" or tonumber(saved.userId) ~= LocalPlayer.UserId or tonumber(saved.placeId) ~= game.PlaceId then
		return {}
	end

	local now = os.time()
	local entries = {}
	if type(saved.entries) == "table" then
		for id, expiresAt in pairs(saved.entries) do
			if type(id) == "string" and tonumber(expiresAt) and tonumber(expiresAt) > now then
				entries[id] = tonumber(expiresAt)
			end
		end
	end
	return entries
end

local function saveIgnoredServers()
	writeJson(IGNORED_SERVERS_FILE, {
		version = 1,
		userId = LocalPlayer.UserId,
		placeId = game.PlaceId,
		entries = state.ignoredServers,
	})
end

local function isIgnoredServer(id)
	local expiresAt = state.ignoredServers[id]
	if not expiresAt then
		return false
	end

	if expiresAt <= os.time() then
		state.ignoredServers[id] = nil
		saveIgnoredServers()
		return false
	end

	return true
end

local function ignoreServer(id, seconds)
	if type(id) ~= "string" or id == "" then
		return
	end

	state.ignoredServers[id] = os.time() + seconds
	saveIgnoredServers()
end

local function clearIgnoredServer(id)
	if state.ignoredServers[id] then
		state.ignoredServers[id] = nil
		saveIgnoredServers()
	end
end

local function getRole()
	local team = LocalPlayer.Team
	if not team then
		return "Unknown"
	end

	if team.Name == "Killer" then
		return "Killer"
	end
	if team.Name == "Survivors" then
		return "Survivor"
	end
	if team.Name == "Spectator" or team.Name == "Spectators" then
		return "Spectator"
	end
	return "Lobby"
end

local function getRoot()
	local character = LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function getRequestFunction()
	local syn = getGlobal("syn")
	if type(syn) == "table" and type(syn.request) == "function" then
		return syn.request
	end

	local http = getGlobal("http")
	if type(http) == "table" and type(http.request) == "function" then
		return http.request
	end

	for _, name in ipairs({ "http_request", "request", "fluxus_request", "krnl_request" }) do
		local request = getGlobal(name)
		if type(request) == "function" then
			return request
		end
	end

	return nil
end

local function httpGet(url)
	local request = getRequestFunction()
	if request then
		local ok, response = pcall(request, {
			Url = url,
			Method = "GET",
		})
		if ok and type(response) == "table" then
			local status = tonumber(response.StatusCode or response.Status or response.status_code) or 200
			local body = response.Body or response.body
			if status >= 200 and status < 300 and type(body) == "string" then
				return body, status
			end
			return nil, status
		end
	end

	local ok, body = pcall(function()
		return game:HttpGet(url)
	end)
	if ok and type(body) == "string" then
		return body, 200
	end

	return nil, 0
end

local function postJson(url, body)
	local request = getRequestFunction()
	if not request then
		return nil, "This executor does not expose an HTTP request API."
	end

	local ok, response = pcall(request, {
		Url = url,
		Method = "POST",
		Headers = {
			["Content-Type"] = "application/json",
		},
		Body = HttpService:JSONEncode(body),
	})
	if not ok then
		return nil, tostring(response)
	end

	local status = type(response) == "table" and tonumber(response.StatusCode or response.status_code) or nil
	if status and status >= 200 and status < 300 then
		return true, "OK"
	end

	return nil, string.format("HTTP %s", tostring(status or "unknown"))
end

local function validWebhookUrl(url)
	if type(url) ~= "string" then
		return false
	end

	local host, webhookId, token = url:match("^https://([^/]+)/api/webhooks/(%d+)/([%w_%-]+)/?$")
	if not host or not webhookId or not token then
		return false
	end

	return host == "discord.com" or host == "canary.discord.com" or host == "ptb.discord.com" or host == "discordapp.com"
end

local function playerStats()
	local attributes = LocalPlayer:GetAttributes()
	return {
		killerChance = tonumber(attributes.KillerChance) or 0,
		exp = tonumber(attributes.EXP) or 0,
		screws = tonumber(attributes.Screws) or 0,
		gears = tonumber(attributes.Gears) or 0,
		level = tonumber(attributes.Level) or 0,
	}
end

local function delta(current, previous)
	if not previous then
		return 0
	end
	return current - (tonumber(previous) or 0)
end

local setStatus
local sendWebhook
local startServerHop
local requestServerHop
local unload

local function sendWebhookReport(title, description, updateSnapshot, force)
	if not force and not state.settings.webhook then
		return false, "Webhook reporting is disabled."
	end

	if not validWebhookUrl(state.webhookUrl) then
		return false, "Enter a valid Discord webhook URL first."
	end

	local stats = playerStats()
	local previous = state.snapshot
	local payload = {
		username = "ZRYX",
		embeds = {
			{
				title = title or string.format("%s | Level %d", LocalPlayer.DisplayName, stats.level),
				description = description or "Survivor round completed.",
				url = string.format("https://www.roblox.com/users/%d/profile", LocalPlayer.UserId),
				color = 3638942,
				fields = {
					{ name = "SIN", value = string.format("%.0f (%+.0f)", stats.killerChance, delta(stats.killerChance, previous and previous.killerChance)), inline = true },
					{ name = "EXP", value = string.format("%.0f (%+.0f)", stats.exp, delta(stats.exp, previous and previous.exp)), inline = true },
					{ name = "Screws", value = string.format("%.0f (%+.0f)", stats.screws, delta(stats.screws, previous and previous.screws)), inline = true },
					{ name = "Gears", value = string.format("%.0f (%+.0f)", stats.gears, delta(stats.gears, previous and previous.gears)), inline = true },
					{ name = "Server", value = string.format("`%s`", game.JobId ~= "" and game.JobId or "Singleplayer"), inline = false },
				},
				footer = { text = "ZRYX " .. VERSION },
				timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z"),
			},
		},
	}

	local ok, message = postJson(state.webhookUrl, payload)
	if ok and updateSnapshot then
		state.snapshot = {
			killerChance = stats.killerChance,
			exp = stats.exp,
			screws = stats.screws,
			gears = stats.gears,
		}
		saveSnapshot(state.snapshot)
	end

	return ok, message
end

sendWebhook = sendWebhookReport

local function findBasePart(instance)
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function findFinishPosition(map)
	if map:FindFirstChild("RooftopHitbox", true) or map:FindFirstChild("Rooftop", true) then
		return Vector3.new(3098.16, 454.04, -4918.74)
	end
	if map:FindFirstChild("HooksMeat", true) then
		return Vector3.new(1546.12, 152.21, -796.72)
	end
	if map:FindFirstChild("churchbell", true) then
		return Vector3.new(760.98, -20.14, -78.48)
	end

	for _, name in ipairs({ "Finishline", "FinishLine", "Fininshline" }) do
		local finish = map:FindFirstChild(name, true)
		if finish then
			local part = findBasePart(finish)
			if part then
				return part.Position
			end
		end
	end

	return nil
end

local function resetFarm()
	state.farmToken = state.farmToken + 1
	state.farmAttemptedMap = nil
	state.farmUnsupportedMap = nil
end

local function farmStillCurrent(token, map)
	return state.running
		and state.settings.autoFarm
		and state.farmToken == token
		and Workspace:FindFirstChild("Map") == map
		and getRole() == "Survivor"
end

local function waitForFarm(seconds, token, map)
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		if not farmStillCurrent(token, map) then
			return false
		end
		task.wait(math.min(0.25, deadline - os.clock()))
	end
	return farmStillCurrent(token, map)
end

local function farmCurrentRound(map)
	if state.farmBusy then
		return
	end

	state.farmBusy = true
	state.farmTaskId = state.farmTaskId + 1
	local taskId = state.farmTaskId
	local token = state.farmToken

	local function finishTask()
		if state.farmTaskId == taskId then
			state.farmBusy = false
		end
	end

	local finishPosition = findFinishPosition(map)
	if not finishPosition then
		if state.farmUnsupportedMap ~= map then
			state.farmUnsupportedMap = map
			setStatus("Finish line was not found on this map.")
		end
		finishTask()
		return
	end

	setStatus(string.format("Survivor detected. Moving in %ds...", FINISH_DELAY))
	if not waitForFarm(FINISH_DELAY, token, map) then
		finishTask()
		return
	end

	local root = getRoot()
	if not root then
		setStatus("Waiting for the Survivor character.")
		finishTask()
		return
	end

	local moved, moveError = pcall(function()
		root.CFrame = CFrame.new(finishPosition + Vector3.new(0, 3, 0))
	end)
	if not moved then
		setStatus("Could not move to finish: " .. tostring(moveError))
		finishTask()
		return
	end

	state.farmAttemptedMap = map
	setStatus("Finish action sent. Confirming round state...")

	local deadline = os.clock() + FINISH_CONFIRM_TIMEOUT
	while os.clock() < deadline and state.running and state.farmToken == token do
		local role = getRole()
		if role ~= "Survivor" or Workspace:FindFirstChild("Map") ~= map then
			setStatus("Round completed.")
			if state.settings.webhook then
				task.spawn(function()
					local ok, message = sendWebhook(nil, "Survivor round completed.", true, false)
					if not ok and state.running then
						setStatus("Round completed. Webhook failed: " .. message)
					end
				end)
			end
			finishTask()
			return
		end
		task.wait(0.25)
	end

	if state.running and state.farmToken == token and getRole() == "Survivor" then
		if state.settings.serverHop then
			setStatus("Finish was not confirmed. Looking for another server...")
			requestServerHop(true)
		else
			setStatus("Finish was not confirmed. Enable Server Hop to recover.")
		end
	end

	finishTask()
end

local function canHop(force)
	if not state.settings.serverHop then
		return false
	end
	if force then
		return true
	end
	if not state.roundActive then
		return false
	end
	local role = getRole()
	return role == "Spectator" or role == "Killer"
end

local function getQueueOnTeleport()
	for _, name in ipairs({ "queue_on_teleport", "queueonteleport" }) do
		local queue = getGlobal(name)
		if type(queue) == "function" then
			return queue
		end
	end
	return nil
end

local function queueAutoExecute()
	if not state.settings.autoExecute then
		return true
	end

	local url = state.settings.scriptUrl:match("^%s*(.-)%s*$")
	if not url:match("^https://") then
		setStatus("Auto Execute needs a HTTPS Script URL.")
		return false
	end

	local queue = getQueueOnTeleport()
	if not queue then
		setStatus("This executor does not support queue_on_teleport.")
		return false
	end

	local code = string.format("loadstring(game:HttpGet(%q))()", url)
	local ok, errorMessage = pcall(queue, code)
	if not ok then
		setStatus("Could not queue Auto Execute: " .. tostring(errorMessage))
		return false
	end

	return true
end

local function fetchServerPage(cursor)
	local url = string.format(
		"https://games.roblox.com/v1/games/%d/servers/Public?limit=100&sortOrder=Asc&excludeFullGames=true&cursor=%s",
		game.PlaceId,
		HttpService:UrlEncode(cursor or "")
	)
	local contents, status = httpGet(url)
	if not contents then
		return nil, status
	end

	local ok, page = pcall(function()
		return HttpService:JSONDecode(contents)
	end)
	if not ok or type(page) ~= "table" or type(page.data) ~= "table" then
		return nil, status
	end

	return page, status
end

local function chooseServer(page)
	local currentJobId = game.JobId
	for _, server in ipairs(page.data) do
		local id = server.id
		local playerCount = tonumber(server.playing)
		if type(id) == "string"
			and id ~= currentJobId
			and playerCount
			and playerCount >= state.settings.minPlayers
			and playerCount <= state.settings.maxPlayers
			and not isIgnoredServer(id) then
			return id, playerCount
		end
	end
	return nil, nil
end

local function resetTeleport()
	state.teleport.active = false
	state.teleport.failed = false
	state.teleport.id = nil
	state.teleport.originJobId = nil
end

local function teleportToServer(id)
	if not queueAutoExecute() then
		return "queue_failed"
	end

	state.teleport.active = true
	state.teleport.failed = false
	state.teleport.id = id
	state.teleport.originJobId = game.JobId

	local started, errorMessage = pcall(function()
		TeleportService:TeleportToPlaceInstance(game.PlaceId, id, LocalPlayer)
	end)
	if not started then
		resetTeleport()
		return "error:" .. tostring(errorMessage)
	end

	local deadline = os.clock() + TELEPORT_TIMEOUT
	while state.running and state.teleport.active and not state.teleport.failed and os.clock() < deadline do
		if game.JobId ~= state.teleport.originJobId then
			resetTeleport()
			return "success"
		end
		task.wait(0.1)
	end

	if state.teleport.failed then
		resetTeleport()
		return "failed"
	end
	if game.JobId ~= state.teleport.originJobId then
		resetTeleport()
		return "success"
	end

	resetTeleport()
	return "timeout"
end

startServerHop = function()
	if state.hop.running or not state.settings.serverHop then
		return
	end

	state.hop.running = true
	task.spawn(function()
		local cursor = ""
		local seenCursors = {}
		local apiFailures = 0

		while state.running and state.settings.serverHop do
			local force = state.hop.forceUntil > os.clock()
			if not canHop(force) then
				task.wait(0.75)
			else
				local page, status = fetchServerPage(cursor)
				if not page then
					apiFailures = apiFailures + 1
					if status == 429 then
						setStatus("Server list is rate limited. Retrying shortly...")
						task.wait(5)
					else
						setStatus("Could not read server list. Retrying...")
						task.wait(math.min(8, apiFailures + 2))
					end
					if apiFailures >= 5 then
						cursor = ""
						seenCursors = {}
						apiFailures = 0
					end
				else
					apiFailures = 0
					local id, playerCount = chooseServer(page)
					if id then
						local stillForced = state.hop.forceUntil > os.clock()
						if canHop(stillForced) then
							state.hop.forceUntil = 0
							ignoreServer(id, CANDIDATE_IGNORE_SECONDS)
							setStatus(string.format("Teleporting to a %d-player server...", playerCount))
							local result = teleportToServer(id)
							if result == "success" then
								state.hop.running = false
								return
							end
							if result == "queue_failed" then
								clearIgnoredServer(id)
								state.hop.running = false
								return
							end

							ignoreServer(id, FAILED_IGNORE_SECONDS)
							setStatus("Teleport failed. Trying another server...")
							task.wait(2.5)
						end
					else
						local nextCursor = type(page.nextPageCursor) == "string" and page.nextPageCursor or ""
						if nextCursor ~= "" and not seenCursors[nextCursor] then
							seenCursors[nextCursor] = true
							cursor = nextCursor
							task.wait(0.5)
						else
							cursor = ""
							seenCursors = {}
							setStatus(string.format("No %d-%d player server is available.", state.settings.minPlayers, state.settings.maxPlayers))
							task.wait(3)
						end
					end
				end
			end
		end

		state.hop.running = false
	end)
end

requestServerHop = function(force)
	if not state.settings.serverHop then
		setStatus("Enable Server Hop first.")
		return
	end

	if force then
		state.hop.forceUntil = os.clock() + 20
	end
	startServerHop()
end

local function updateRoundState(active)
	if state.roundActive ~= active then
		state.roundActive = active
		state.roundId = state.roundId + 1
		if not active then
			resetFarm()
		end
	end
end

local function bindRoundEvents()
	task.spawn(function()
		local deadline = os.clock() + 15
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		while state.running and not remotes and os.clock() < deadline do
			task.wait(0.5)
			remotes = ReplicatedStorage:FindFirstChild("Remotes")
		end

		if not state.running or not remotes then
			return
		end

		local statusEvent = remotes:FindFirstChild("StatusUpdateEvent")
		if statusEvent and statusEvent:IsA("RemoteEvent") then
			addConnection(statusEvent.OnClientEvent:Connect(function(value)
				local message = tostring(value):lower()
				if message:find("waiting") or message:find("intermission") then
					updateRoundState(false)
				elseif message:find("round") then
					updateRoundState(true)
				end
			end))
		end

		local timeEvent = remotes:FindFirstChild("TimeUpdateEvent")
		if timeEvent and timeEvent:IsA("RemoteEvent") then
			addConnection(timeEvent.OnClientEvent:Connect(function(value)
				if tostring(value):lower():find("round") then
					updateRoundState(true)
				end
			end))
		end
	end)
end

local function buildInterface()
	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 8)
	if not playerGui then
		warn("ZRYX could not find PlayerGui.")
		return false
	end

	local colors = {
		background = Color3.fromRGB(12, 16, 27),
		surface = Color3.fromRGB(24, 31, 48),
		surfaceHover = Color3.fromRGB(31, 41, 62),
		border = Color3.fromRGB(55, 68, 95),
		text = Color3.fromRGB(238, 242, 255),
		muted = Color3.fromRGB(151, 163, 188),
		accent = Color3.fromRGB(84, 157, 255),
		positive = Color3.fromRGB(58, 201, 137),
		danger = Color3.fromRGB(244, 101, 101),
	}

	local function make(className, properties)
		local object = Instance.new(className)
		for property, value in pairs(properties) do
			object[property] = value
		end
		return object
	end

	local function round(object, radius)
		make("UICorner", {
			CornerRadius = UDim.new(0, radius),
			Parent = object,
		})
	end

	local function stroke(object, color)
		make("UIStroke", {
			Color = color,
			Thickness = 1,
			Transparency = 0.35,
			Parent = object,
		})
	end

	local gui = make("ScreenGui", {
		Name = "ZRYX",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})

	local scale = make("UIScale", {
		Scale = 1,
		Parent = gui,
	})

	local main = make("Frame", {
		Name = "Main",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(470, 590),
		BackgroundColor3 = colors.background,
		BorderSizePixel = 0,
		Parent = gui,
	})
	round(main, 14)
	stroke(main, colors.border)

	local header = make("Frame", {
		Size = UDim2.new(1, 0, 0, 68),
		BackgroundColor3 = colors.surface,
		BorderSizePixel = 0,
		Parent = main,
	})
	round(header, 14)

	make("TextLabel", {
		Position = UDim2.fromOffset(20, 12),
		Size = UDim2.new(1, -92, 0, 24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "ZRYX",
		TextColor3 = colors.text,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})

	make("TextLabel", {
		Position = UDim2.fromOffset(20, 37),
		Size = UDim2.new(1, -92, 0, 18),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "Violence District | v" .. VERSION,
		TextColor3 = colors.muted,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})

	local hideButton = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = colors.surfaceHover,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "-",
		TextColor3 = colors.text,
		TextSize = 22,
		Parent = header,
	})
	round(hideButton, 10)

	local content = make("ScrollingFrame", {
		Position = UDim2.fromOffset(14, 80),
		Size = UDim2.new(1, -28, 1, -136),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = colors.border,
		Parent = main,
	})
	make("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = content,
	})

	local footer = make("TextLabel", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, -14),
		Size = UDim2.new(1, -36, 0, 30),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = state.status,
		TextColor3 = colors.muted,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Parent = main,
	})

	local reopen = make("TextButton", {
		Name = "Reopen",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -20),
		Size = UDim2.fromOffset(54, 54),
		BackgroundColor3 = colors.accent,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "Z",
		TextColor3 = colors.text,
		TextSize = 14,
		Visible = false,
		Parent = gui,
	})
	round(reopen, 18)

	local function section(title)
		local frame = make("Frame", {
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, -8, 0, 0),
			BackgroundColor3 = colors.surface,
			BorderSizePixel = 0,
			Parent = content,
		})
		round(frame, 10)
		stroke(frame, colors.border)
		make("UIPadding", {
			PaddingTop = UDim.new(0, 12),
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
			Parent = frame,
		})
		make("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = frame,
		})
		make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = title,
			TextColor3 = colors.text,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		return frame
	end

	local function toggle(parent, title, detail, initial, callback)
		local row = make("TextButton", {
			Size = UDim2.new(1, 0, 0, 52),
			BackgroundColor3 = colors.background,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			Parent = parent,
		})
		round(row, 8)
		make("TextLabel", {
			Position = UDim2.fromOffset(12, 8),
			Size = UDim2.new(1, -84, 0, 18),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Text = title,
			TextColor3 = colors.text,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		make("TextLabel", {
			Position = UDim2.fromOffset(12, 27),
			Size = UDim2.new(1, -84, 0, 16),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = detail,
			TextColor3 = colors.muted,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		local switch = make("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(46, 24),
			BorderSizePixel = 0,
			Parent = row,
		})
		round(switch, 12)
		local knob = make("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(3, 12),
			Size = UDim2.fromOffset(18, 18),
			BackgroundColor3 = colors.text,
			BorderSizePixel = 0,
			Parent = switch,
		})
		round(knob, 9)

		local value = initial
		local function refresh(nextValue)
			value = nextValue
			switch.BackgroundColor3 = value and colors.positive or colors.border
			knob.Position = value and UDim2.fromOffset(25, 12) or UDim2.fromOffset(3, 12)
		end
		refresh(value)
		addConnection(row.Activated:Connect(function()
			refresh(not value)
			callback(not value)
		end))
		return refresh
	end

	local function input(parent, title, placeholder, initial, callback)
		make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 17),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Text = title,
			TextColor3 = colors.text,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = parent,
		})
		local box = make("TextBox", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundColor3 = colors.background,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Font = Enum.Font.Gotham,
			PlaceholderText = placeholder,
			PlaceholderColor3 = colors.muted,
			Text = initial,
			TextColor3 = colors.text,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = parent,
		})
		round(box, 8)
		make("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
			Parent = box,
		})
		addConnection(box.FocusLost:Connect(function()
			callback(box.Text)
		end))
		return box
	end

	local function button(parent, title, accent, callback)
		local control = make("TextButton", {
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = Enum.Font.GothamBold,
			Text = title,
			TextColor3 = colors.text,
			TextSize = 12,
			Parent = parent,
		})
		round(control, 8)
		addConnection(control.Activated:Connect(callback))
		return control
	end

	local automation = section("AUTOMATION")
	local autoFarmRefresh = toggle(automation, "Auto Farm", "Move Survivors to the known finish line.", state.settings.autoFarm, function(value)
		state.settings.autoFarm = value
		resetFarm()
		saveSettings()
		setStatus(value and "Auto Farm enabled." or "Auto Farm disabled.")
	end)
	local serverHopRefresh = toggle(automation, "Server Hop", "Find 1-3 player servers during a round.", state.settings.serverHop, function(value)
		state.settings.serverHop = value
		saveSettings()
		if value then
			setStatus("Server Hop enabled. Waiting for a valid role.")
			startServerHop()
		else
			setStatus("Server Hop disabled.")
		end
	end)
	local autoExecuteRefresh = toggle(automation, "Auto Execute", "Queue this script before a server teleport.", state.settings.autoExecute, function(value)
		state.settings.autoExecute = value
		saveSettings()
		setStatus(value and "Auto Execute enabled." or "Auto Execute disabled.")
	end)

	local serverSection = section("SERVER HOP")
	local minimumBox
	minimumBox = input(serverSection, "Minimum players", "1", tostring(state.settings.minPlayers), function(value)
		state.settings.minPlayers = clampNumber(value, state.settings.minPlayers, 1, 20)
		state.settings.maxPlayers = math.max(state.settings.minPlayers, state.settings.maxPlayers)
		minimumBox.Text = tostring(state.settings.minPlayers)
		saveSettings()
	end)
	local maximumBox
	maximumBox = input(serverSection, "Maximum players", "3", tostring(state.settings.maxPlayers), function(value)
		state.settings.maxPlayers = clampNumber(value, state.settings.maxPlayers, state.settings.minPlayers, 20)
		maximumBox.Text = tostring(state.settings.maxPlayers)
		saveSettings()
	end)
	button(serverSection, "HOP NOW", colors.accent, function()
		requestServerHop(true)
	end)

	local executeSection = section("AUTO EXECUTE")
	local scriptUrlBox
	scriptUrlBox = input(executeSection, "Script URL", "https://raw.githubusercontent.com/.../zryx.lua", state.settings.scriptUrl, function(value)
		state.settings.scriptUrl = value:match("^%s*(.-)%s*$")
		scriptUrlBox.Text = state.settings.scriptUrl
		saveSettings()
	end)

	local webhookSection = section("DISCORD WEBHOOK")
	local webhookRefresh = toggle(webhookSection, "Webhook reporting", "Send stats after a confirmed Survivor round.", state.settings.webhook, function(value)
		state.settings.webhook = value
		saveSettings()
		setStatus(value and "Webhook reporting enabled." or "Webhook reporting disabled.")
	end)
	local webhookBox
	webhookBox = input(webhookSection, "Webhook URL", "https://discord.com/api/webhooks/...", state.webhookUrl, function(value)
		state.webhookUrl = value:match("^%s*(.-)%s*$")
		webhookBox.Text = state.webhookUrl
	end)
	button(webhookSection, "TEST WEBHOOK", colors.surfaceHover, function()
		task.spawn(function()
			setStatus("Sending webhook test...")
			local ok, message = sendWebhook("ZRYX test", "Webhook connectivity check.", false, true)
			setStatus(ok and "Webhook test sent." or "Webhook test failed: " .. message)
		end)
	end)

	local utility = section("UTILITY")
	button(utility, "UNLOAD", colors.danger, function()
		unload()
	end)

	state.ui = {
		gui = gui,
		main = main,
		reopen = reopen,
		footer = footer,
		refresh = {
			autoFarm = autoFarmRefresh,
			serverHop = serverHopRefresh,
			autoExecute = autoExecuteRefresh,
			webhook = webhookRefresh,
		},
	}

	local visible = true
	local function setVisible(nextVisible)
		visible = nextVisible
		main.Visible = visible
		reopen.Visible = not visible
	end

	addConnection(hideButton.Activated:Connect(function()
		setVisible(false)
	end))
	addConnection(reopen.Activated:Connect(function()
		setVisible(true)
	end))
	addConnection(UserInputService.InputBegan:Connect(function(inputObject, gameProcessed)
		if not gameProcessed and inputObject.KeyCode == Enum.KeyCode.RightShift then
			setVisible(not visible)
		end
	end))

	local dragging = false
	local dragStart = nil
	local startPosition = nil
	addConnection(header.InputBegan:Connect(function(inputObject)
		if inputObject.UserInputType == Enum.UserInputType.MouseButton1 or inputObject.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = inputObject.Position
			startPosition = main.Position
		end
	end))
	addConnection(UserInputService.InputChanged:Connect(function(inputObject)
		if dragging and (inputObject.UserInputType == Enum.UserInputType.MouseMovement or inputObject.UserInputType == Enum.UserInputType.Touch) then
			local deltaPosition = inputObject.Position - dragStart
			main.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + deltaPosition.X, startPosition.Y.Scale, startPosition.Y.Offset + deltaPosition.Y)
		end
	end))
	addConnection(UserInputService.InputEnded:Connect(function(inputObject)
		if inputObject.UserInputType == Enum.UserInputType.MouseButton1 or inputObject.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))

	local function updateScale()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local viewport = camera.ViewportSize
		scale.Scale = math.clamp(math.min(viewport.X / 500, viewport.Y / 630), 0.68, 1)
	end
	updateScale()
	if Workspace.CurrentCamera then
		addConnection(Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale))
	end

	return true
end

setStatus = function(message)
	if state.status == message then
		return
	end
	state.status = message
	if state.ui and state.ui.footer then
		state.ui.footer.Text = message
	end
end

unload = function()
	if not state.running then
		return
	end

	state.running = false
	state.farmToken = state.farmToken + 1
	resetTeleport()

	for _, connection in ipairs(state.connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	state.connections = {}

	if state.ui and state.ui.gui then
		state.ui.gui:Destroy()
	end
	if GLOBAL_ENV.__ZRYX__ == state then
		GLOBAL_ENV.__ZRYX__ = nil
	end
end

GLOBAL_ENV.__ZRYX__ = state
state.Unload = unload

storageReady = initializeStorage()
loadSettings()
state.snapshot = loadSnapshot()
state.ignoredServers = loadIgnoredServers()

if not buildInterface() then
	state.ui = nil
end

addConnection(TeleportService.TeleportInitFailed:Connect(function(player)
	if player == LocalPlayer and state.teleport.active then
		state.teleport.failed = true
		if state.teleport.id then
			ignoreServer(state.teleport.id, FAILED_IGNORE_SECONDS)
		end
	end
end))

addConnection(Workspace.ChildAdded:Connect(function(child)
	if child.Name == "Map" then
		updateRoundState(true)
		resetFarm()
	end
end))
addConnection(Workspace.ChildRemoved:Connect(function(child)
	if child.Name == "Map" then
		updateRoundState(false)
		resetFarm()
	end
end))

bindRoundEvents()

task.spawn(function()
	while state.running do
		local map = Workspace:FindFirstChild("Map")
		if state.settings.autoFarm and map and getRole() == "Survivor" and not state.farmBusy and state.farmAttemptedMap ~= map then
			task.spawn(farmCurrentRound, map)
		end
		task.wait(0.5)
	end
end)

if state.settings.serverHop then
	startServerHop()
end

if storageReady then
	setStatus("Ready. RightShift toggles the panel.")
else
	setStatus("Ready. Local storage is unavailable in this executor.")
end
