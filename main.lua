--- zryx
---
--- zryx by zaerrruwww | Original by Rzor731
---
--- Automated survivor farming, low-population server hopping,
--- webhook reporting, and teleport recovery for Violence District.
---
--- @module zryx
--- @author zaerrruwww
--- @version 1.0.0
pcall(function()
	game:GetService("GuiService"):SetErrorPromptEnabled(false)
end)
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

--- Base URL for the Obsidian UI library.
--- @local
local REPO = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"

--- Obsidian UI library instance.
--- @local
local Library = loadstring(game:HttpGet(REPO .. "Library.lua"))()

--- Obsidian theme manager.
--- @local
local ThemeManager = loadstring(game:HttpGet(REPO .. "addons/ThemeManager.lua"))()

--- Obsidian save manager.
--- @local
local SaveManager = loadstring(game:HttpGet(REPO .. "addons/SaveManager.lua"))()

--- UI option registry.
--- @local
local Options = Library.Options

--- UI toggle registry.
--- @local
local Toggles = Library.Toggles
Library.ForceCheckbox = false
Library.ShowToggleFrameInKeybinds = true

--- Main application window.
--- @local
local Window = Library:CreateWindow({
	Title = "zryx",
	Footer = "zryx by zaerrruwww | version 1.0.0",
	Icon = "bot",
	NotifySide = "Right",
	ShowCustomCursor = true,
})
Window:SetSidebarWidth(40)

--- Application tabs.
--- @local
local Tabs = {
	AutoFarm = Window:AddTab("", "zap"),
	Settings = Window:AddTab("", "settings"),
}

--- Auto Farm UI group.
--- @local
local AutoFarmGroup = Tabs.AutoFarm:AddLeftGroupbox("Auto Farm", "zap")

--- Webhook UI group.
--- @local
local WebhookGroup = Tabs.AutoFarm:AddRightGroupbox("Webhook", "webhook")

--- State used by the survivor completion system.
--- @class BeatState
--- @field LastFinishPos Vector3|nil Last detected finish position.
--- @field BeatSurvivorDone boolean Whether the current survivor round was already processed.
--- @field LastRole string|nil Last detected player role.
--- @local
local BeatState = {
	LastFinishPos = nil,
	BeatSurvivorDone = false,
	LastRole = nil,
}

--- Forces the server-hop routine to execute on its next iteration.
--- @type boolean
--- @local
local ForceServerHop = false

--- Timestamp of the last notification.
--- @type number
--- @local
local LastNotifTime = 0

--- Reference to the server-hop function.
--- @type function|nil
--- @local
local ServerHop

--- Displays a throttled UI notification.
---
--- Notifications are limited to one every 2.5 seconds
--- to prevent excessive UI spam.
---
--- @param title string Notification title.
--- @param desc string Notification description.
--- @param duration number|nil Display duration in seconds.
--- @return nil
--- @local
local function Notify(title, desc, duration)
	local now = os.clock()
	if now - LastNotifTime < 2.5 then
		return
	end
	LastNotifTime = now
	Library:Notify({
		Title = title .. "   \n",
		Description = desc .. "   ",
		Time = duration or 3,
	})
end

--- Returns the current role of the local player.
---
--- Supported roles are `Killer`, `Survivor`, `Spectator`,
--- `Lobby`, and `Unknown`.
---
--- @return string role Current player role.
--- @local
local function GetRole()
	local team = LocalPlayer.Team
	if not team then
		return "Unknown"
	end
	local n = team.Name
	if n == "Killer" then
		return "Killer"
	elseif n == "Survivors" then
		return "Survivor"
	elseif n == "Spectator" or n == "Spectators" then
		return "Spectator"
	end
	return "Lobby"
end

--- Returns the local player's HumanoidRootPart.
---
--- @return BasePart|nil root Character root part, if available.
--- @local
local function GetRoot()
	local c = LocalPlayer.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

--- Sends an HTTP request using an executor-provided request function.
---
--- Supports several common executor request APIs.
---
--- @param opts table HTTP request options.
--- @return table|nil response HTTP response object, if supported.
--- @local
local function SafeReq(opts)
	local fn = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request) or (krnl and krnl.request)
	return fn and fn(opts)
end

--- Returns the current executor name.
---
--- @return string name Detected executor name.
--- @local
local function ExecutorName()
	return (identifyexecutor and identifyexecutor()) or (getexecutorname and getexecutorname()) or "Unknown Executor"
end

--- File used to persist previous player attributes.
--- @local
local ATTR_FILE = "VD_AutoFarm_Attributes.json"

--- Previously stored player attributes.
--- @type table|nil
--- @local
local PrevAttrs

--- Loads the previously saved attribute snapshot.
---
--- The snapshot is rejected when it belongs to another Roblox user.
---
--- @return table|nil snapshot Stored attribute values.
--- @local
local function LoadSnapshot()
	if not isfile or not readfile or not isfile(ATTR_FILE) then
		return nil
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(ATTR_FILE))
	end)
	if not ok or type(data) ~= "table" or tonumber(data.UserId) ~= LocalPlayer.UserId then
		return nil
	end
	return {
		KillerChance = tonumber(data.KillerChance),
		EXP = tonumber(data.EXP),
		Screws = tonumber(data.Screws),
		Gears = tonumber(data.Gears),
	}
end

--- Saves the current attribute snapshot to disk.
---
--- @param attrs table Attribute snapshot.
--- @return boolean success Whether the write operation succeeded.
--- @local
local function SaveSnapshot(attrs)
	if not writefile then
		return false
	end
	local data = {
		UserId = LocalPlayer.UserId,
		KillerChance = attrs.KillerChance,
		EXP = attrs.EXP,
		Screws = attrs.Screws,
		Gears = attrs.Gears,
		UpdatedAt = os.time(),
	}
	return pcall(function()
		writefile(ATTR_FILE, HttpService:JSONEncode(data))
	end)
end

--- Calculates the numeric difference between two values.
---
--- @param cur number|string Current value.
--- @param prev number|string|nil Previous value.
--- @return number delta Difference between current and previous values.
--- @local
local function Delta(cur, prev)
	cur = tonumber(cur) or 0
	if prev == nil then
		return 0
	end
	return cur - (tonumber(prev) or 0)
end
PrevAttrs = LoadSnapshot()

--- Determines whether webhook reporting is enabled.
---
--- @return boolean enabled Whether the webhook toggle is enabled.
--- @local
local function WebhookEnabled()
	return Toggles.EnableWebhook and Toggles.EnableWebhook.Value
end

--- Returns the configured Discord webhook URL.
---
--- @return string url Configured webhook URL.
--- @local
local function WebhookUrl()
	return Options.WebhookLink and Options.WebhookLink.Value or ""
end

--- Validates the configured webhook URL.
---
--- @param url string Webhook URL to validate.
--- @return boolean valid Whether the URL appears to be a Discord webhook.
--- @local
local function ValidWebhook(url)
	return url ~= "" and string.find(url, "discord.com/api/webhooks")
end

--- Sends a diagnostic message to the configured webhook.
---
--- This function is intended for server-hop and teleport debugging.
---
--- @param title string Embed title.
--- @param desc string Embed description.
--- @return boolean success Whether the request was accepted.
--- @local
local function SendDebug(title, desc)
	if not WebhookEnabled() then
		return false
	end
	local url = WebhookUrl()
	if not ValidWebhook(url) then
		return false
	end
	local payload = {
		embeds = {
			{
				title = title,
				description = desc,
				color = 16711680,
				footer = {
					text = "ServerHop Debug",
				},
				timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z"),
			},
		},
	}
	local res = SafeReq({
		Url = url,
		Method = "POST",
		Headers = {
			["Content-Type"] = "application/json",
		},
		Body = HttpService:JSONEncode(payload),
	})
	return res and (res.StatusCode == 200 or res.StatusCode == 204)
end

--- Sends a player-statistic webhook.
---
--- The embed includes current KillerChance, EXP, Screws,
--- Gears, server ID, and the delta from the previous snapshot.
---
--- @param title string|nil Optional embed title.
--- @param desc string|nil Embed description.
--- @param force boolean|nil Whether to send even when the webhook toggle is disabled.
--- @return boolean success Whether the webhook request succeeded.
--- @return string status Result description.
--- @local
local function SendWebhook(title, desc, force)
	if not force and not WebhookEnabled() then
		return false, "Disabled"
	end
	local url = WebhookUrl()
	if not ValidWebhook(url) then
		return false, "Invalid URL"
	end
	local attrs = LocalPlayer:GetAttributes()
	local kc = tonumber(attrs.KillerChance) or 0
	local exp = tonumber(attrs.EXP) or 0
	local screws = tonumber(attrs.Screws) or 0
	local gears = tonumber(attrs.Gears) or 0
	local lvl = tonumber(attrs.Level) or 0
	if not PrevAttrs then
		PrevAttrs = {
			KillerChance = kc,
			EXP = exp,
			Screws = screws,
			Gears = gears,
		}
	end
	local payload = {
		embeds = {
			{
				title = title or string.format("%s · Level %d", LocalPlayer.DisplayName, lvl),
				url = string.format("https://www.roblox.com/users/%d/profile", LocalPlayer.UserId),
				description = desc,
				color = 3638942,
				fields = {
					{
						name = "💀 SIN",
						value = string.format("%s (**%+d**)", kc, Delta(kc, PrevAttrs.KillerChance)),
						inline = false,
					},
					{
						name = "🧪 EXP",
						value = string.format("%s (**%+d**)", exp, Delta(exp, PrevAttrs.EXP)),
						inline = false,
					},
					{
						name = "🔩 Screws",
						value = string.format("%s (**%+d**)", screws, Delta(screws, PrevAttrs.Screws)),
						inline = false,
					},
					{
						name = "⚙️ Gears",
						value = string.format("%s (**%+d**)", gears, Delta(gears, PrevAttrs.Gears)),
						inline = false,
					},
					{
						name = "🆔 Server ID",
						value = string.format("```\n%s\n```", game.JobId ~= "" and game.JobId or "Singleplayer"),
						inline = false,
					},
				},
				footer = {
					text = string.format("zryx by zaerrruwww · %s", ExecutorName()),
				},
				timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z"),
			},
		},
	}
	local res = SafeReq({
		Url = url,
		Method = "POST",
		Headers = {
			["Content-Type"] = "application/json",
		},
		Body = HttpService:JSONEncode(payload),
	})
	if res and (res.StatusCode == 200 or res.StatusCode == 204) then
		PrevAttrs = {
			KillerChance = kc,
			EXP = exp,
			Screws = screws,
			Gears = gears,
		}
		SaveSnapshot(PrevAttrs)
		return true, "OK"
	end
	return false, "Status: " .. tostring(res and res.StatusCode or "No Response")
end

--- Searches a map for the survivor finish position.
---
--- Several known map layouts are handled through dedicated
--- coordinates, while generic finish objects are discovered
--- dynamically.
---
--- @param map Instance Active map instance.
--- @return Vector3|nil position Detected finish position.
--- @local
local function FindFinish(map)
	local pos
	pcall(function()
		if map:FindFirstChild("RooftopHitbox") or map:FindFirstChild("Rooftop") then
			pos = Vector3.new(3098.16, 454.04, - 4918.74)
			return
		end
		if map:FindFirstChild("HooksMeat") then
			pos = Vector3.new(1546.12, 152.21, - 796.72)
			return
		end
		if map:FindFirstChild("churchbell") then
			pos = Vector3.new(760.98, - 20.14, - 78.48)
			return
		end
		local finish = map:FindFirstChild("Finishline") or map:FindFirstChild("FinishLine") or map:FindFirstChild("Fininshline")
		if finish then
			if finish:IsA("BasePart") then
				pos = finish.Position
			elseif finish:IsA("Model") then
				local p = finish:FindFirstChildWhichIsA("BasePart")
				if p then
					pos = p.Position
				end
			end
			return
		end
		for _, obj in ipairs(map:GetDescendants()) do
			if obj.Name:lower():find("finish") then
				if obj:IsA("BasePart") then
					pos = obj.Position
					break
				elseif obj:IsA("Model") then
					local p = obj:FindFirstChildWhichIsA("BasePart")
					if p then
						pos = p.Position
						break
					end
				end
			end
		end
		if pos then
			return
		end
		for _, obj in ipairs(map:GetDescendants()) do
			if obj:IsA("MeshPart") and obj.Material == Enum.Material.Limestone then
				pos = Vector3.new(- 947.90, 152.12, - 7579.52)
				break
			end
		end
		if pos then
			return
		end
		for _, obj in ipairs(map:GetDescendants()) do
			if obj:IsA("MeshPart") and obj.Material == Enum.Material.Leather then
				pos = Vector3.new(1546.12, 152.21, - 796.72)
				break
			end
		end
	end)
	return pos
end

--- Number of finish teleport attempts before considering the round stuck.
--- @type number
--- @local
local FINISH_ATTEMPTS = 3

--- Seconds to wait after each teleport attempt for the round to complete.
--- @type number
--- @local
local FINISH_CONFIRM = 4

--- Studs before the finish line used as the approach offset.
--- @type number
--- @local
local FINISH_NUDGE = 3

--- Teleports the player just before the finish line and walks
--- through it, so the round completion trigger reliably fires.
---
--- @param root BasePart Character root part.
--- @param exitPos Vector3 Finish position.
--- @return nil
--- @local
local function ApproachFinish(root, exitPos)
	local look = root.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.1 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit
	root.CFrame = CFrame.new(exitPos - look * FINISH_NUDGE + Vector3.new(0, 2, 0))
	pcall(function()
		root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	end)
	task.wait(0.1)
	local ok, tween = pcall(function()
		return TweenService:Create(root, TweenInfo.new(0.35, Enum.EasingStyle.Linear), {
			CFrame = CFrame.new(exitPos + look * 2),
		})
	end)
	if ok then
		tween:Play()
		task.wait(0.4)
	end
	root.CFrame = CFrame.new(exitPos + Vector3.new(0, 1, 0))
	task.wait(0.3)
end

--- Whether the current round can be considered completed.
---
--- @return boolean done Whether the round has ended.
--- @local
local function FinishConfirmed()
	local r = GetRole()
	return r == "Spectator" or r == "Lobby"
end

--- Completes the current survivor round by teleporting
--- the local player to the detected finish position.
---
--- The function retries the teleport up to `FINISH_ATTEMPTS`
--- times and only reports a stuck round when all attempts fail.
---
--- @return nil
--- @local
local function BeatGame()
	if not Toggles.EnableAutoFarm.Value then
		BeatState.BeatSurvivorDone = false
		BeatState.LastFinishPos = nil
		return
	end
	local role = GetRole()
	if BeatState.LastRole ~= role then
		if role == "Survivor" then
			Notify("🟢 Survivor!", "Ready to farm.")
		end
		BeatState.LastRole = role
	end
	if role ~= "Survivor" then
		return
	end
	local root = GetRoot()
	if not root then
		Notify("⏳ Waiting", "Character not loaded")
		return
	end
	local map = Workspace:FindFirstChild("Map")
	if not map then
		Notify("⚠️ No Map", "Waiting for map")
		return
	end
	local exitPos = FindFinish(map)
	if not exitPos then
		Notify("⚠️ Finish Not Found", "Map unsupported")
		return
	end
	if BeatState.LastFinishPos and (exitPos - BeatState.LastFinishPos).Magnitude > 50 then
		BeatState.BeatSurvivorDone = false
	end
	if BeatState.BeatSurvivorDone then
		return
	end
	Notify("📍 Finish Found", "Waiting 3s...")
	task.wait(6)
	if not Toggles.EnableAutoFarm.Value then
		Notify("⛔ Cancelled", "Toggle turned off")
		return
	end
	if GetRole() ~= "Survivor" then
		Notify("⛔ Cancelled", "Not Survivor anymore")
		return
	end
	Notify("🚀 Teleporting", "Moving to finish...")
	local completed = false
	for attempt = 1, FINISH_ATTEMPTS do
		local cr = GetRoot()
		if not cr then
			Notify("⛔ Cancelled", "Character missing")
			return
		end
		ApproachFinish(cr, exitPos)
		local waited = 0
		while waited < FINISH_CONFIRM do
			task.wait(0.5)
			waited = waited + 0.5
			if not Toggles.EnableAutoFarm.Value then
				Notify("⛔ Cancelled", "Toggle turned off")
				return
			end
			if FinishConfirmed() then
				completed = true
				break
			end
		end
		if completed then
			break
		end
		if attempt < FINISH_ATTEMPTS then
			Notify("⚠️ Retrying", string.format("Finish attempt %d/%d", attempt, FINISH_ATTEMPTS))
		end
	end
	BeatState.BeatSurvivorDone = true
	BeatState.LastFinishPos = exitPos
	if completed then
		Notify("✅ Match Finished", "Round completed!")
	else
		Notify("🔴 Match Stuck", "Still Survivor after finish. Server hopping...")
		pcall(function()
			SendDebug("🔴 Match Stuck", string.format("Role remained `%s` after %d attempts.\nServer: `%s`", tostring(GetRole()), FINISH_ATTEMPTS, tostring(game.JobId)))
		end)
		if Toggles.ServerHop and Toggles.ServerHop.Value then
			ForceServerHop = true
		end
	end
	task.wait(5)
	SendWebhook()
end

--- File used to persist ignored server IDs.
--- @local
local IGNORE_FILE = "ServerHop.txt"

--- Lifetime for candidate servers.
--- @type number
--- @local
local IGNORE_CANDIDATE = 180

--- Lifetime for failed servers.
--- @type number
--- @local
local IGNORE_FAILED = 600

--- Delay before retrying a failed server API request.
--- @type number
--- @local
local API_RETRY = 3

--- Delay between API pages.
--- @type number
--- @local
local PAGE_WAIT = 0.5

--- Delay when no compatible server exists.
--- @type number
--- @local
local NO_SERVER_WAIT = 3

--- Maximum wait for a teleport destination to respond.
--- @type number
--- @local
local TELEPORT_TIMEOUT = 7

--- Delay before retrying after teleport failure.
--- @type number
--- @local
local TELEPORT_RETRY_WAIT = 2.5

--- Server IDs currently ignored by the hopper.
--- @type table<string, number>
--- @local
local IgnoredServers = {}

--- Server ID currently being targeted.
--- @type string|nil
--- @local
local TargetServer = nil

--- Job ID of the server the player is currently leaving.
--- @type string|nil
--- @local
local OriginalJob = nil

--- Whether a teleport is currently in progress.
--- @type boolean
--- @local
local TeleportInProgress = false

--- Whether the current teleport attempt failed.
--- @type boolean
--- @local
local TeleportFailed = false

--- Whether the main server-hop routine is already running.
--- @type boolean
--- @local
local IsHopping = false

--- Loads non-expired ignored server entries from disk.
---
--- Each line uses the following format:
---
--- `SERVER_ID|UNIX_EXPIRATION`
---
--- @return table<string, number> Server ID to expiration timestamp mapping.
--- @local
local function LoadIgnored()
	if not isfile or not readfile or not isfile(IGNORE_FILE) then
		return {}
	end
	local ok, content = pcall(readfile, IGNORE_FILE)
	if not ok then
		return {}
	end
	local now = os.time()
	local list = {}
	for _, line in ipairs(content:split("\n")) do
		local id, exp = line:match("^([^|]+)|(%d+)$")
		exp = tonumber(exp)
		if id and id ~= "" and exp and now < exp then
			list[id] = exp
		end
	end
	return list
end

--- Saves currently active ignored servers to disk.
---
--- Expired entries are automatically discarded.
---
--- @param list table<string, number> Server ID to expiration timestamp mapping.
--- @return nil
--- @local
local function SaveIgnored(list)
	if not writefile then
		return
	end
	local now = os.time()
	local lines = {}
	for id, exp in pairs(list) do
		if id and exp and now < exp then
			table.insert(lines, id .. "|" .. exp)
		end
	end
	pcall(function()
		writefile(IGNORE_FILE, table.concat(lines, "\n"))
	end)
end

--- Adds a server ID to the ignore list.
---
--- @param id string Server ID.
--- @param duration number Duration in seconds.
--- @return nil
--- @local
local function AddIgnored(id, duration)
	if not id then
		return
	end
	IgnoredServers[id] = os.time() + duration
	SaveIgnored(IgnoredServers)
end

--- Checks whether a server is currently ignored.
---
--- Expired entries are removed automatically.
---
--- @param id string Server ID.
--- @return boolean ignored Whether the server is currently ignored.
--- @local
local function IsIgnored(id)
	local exp = IgnoredServers[id]
	if not exp then
		return false
	end
	if os.time() >= exp then
		IgnoredServers[id] = nil
		SaveIgnored(IgnoredServers)
		return false
	end
	return true
end

--- Indicates whether a round is currently active.
--- @type boolean
--- @local
local IsRound = false

--- Remote event container.
--- @local
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

--- Round status event.
--- @local
local StatusEvent = Remotes:WaitForChild("StatusUpdateEvent")

--- Round timer event.
--- @local
local TimeEvent = Remotes:WaitForChild("TimeUpdateEvent")
StatusEvent.OnClientEvent:Connect(function(s)
	if s == "WaitingForPlayers" or s == "IntermissionStarting" or s == "Intermission" then
		IsRound = false
		BeatState.BeatSurvivorDone = false
	end
end)
TimeEvent.OnClientEvent:Connect(function(s)
	if s == "Round" then
		IsRound = true
	end
end)

--- Whether the local player is alone in the server.
---
--- @return boolean alone Whether no other players are present.
--- @local
local function IsAlone()
	return #Players:GetPlayers() <= 1
end

--- Determines whether server hopping is allowed at the current moment.
---
--- Server hopping is allowed whenever the player is alone, or during
--- an active round when the player is either a spectator or killer.
---
--- @return boolean allowed Whether server hopping is currently allowed.
--- @local
local function CanHop()
	if IsAlone() then
		return true
	end
	if not IsRound then
		return false
	end
	local r = GetRole()
	return r == "Spectator" or r == "Killer"
end

--- Clears the current teleport state.
---
--- @return nil
--- @local
local function ResetTeleportState()
	TargetServer = nil
	OriginalJob = nil
	TeleportInProgress = false
	TeleportFailed = false
end

--- Initializes a new teleport attempt.
---
--- @param id string Target server instance ID.
--- @return nil
--- @local
local function BeginTeleport(id)
	TargetServer = id
	OriginalJob = game.JobId
	TeleportInProgress = true
	TeleportFailed = false
end

--- Handles native Roblox teleport initialization failures.
---
--- Failed target servers are temporarily blacklisted for 10 minutes.
TeleportService.TeleportInitFailed:Connect(function(player, result, err)
	if player ~= LocalPlayer or not TeleportInProgress then
		return
	end
	local id = TargetServer
	TeleportFailed = true
	if id then
		AddIgnored(id, IGNORE_FAILED)
		Notify("❌ Teleport Failed", string.format("Server %s blacklisted 10m", id:sub(1, 8)))
		pcall(function()
			SendDebug("🐛 Teleport Failed", string.format("Server: `%s`\nCode: `%s`\nError: `%s`", id, tostring(result), tostring(err)))
		end)
	end
end)

--- Starts a teleport to a specific public server.
---
--- @param id string Roblox server instance ID.
--- @return boolean success Whether the teleport call was started successfully.
--- @local
local function DoTeleport(id)
	BeginTeleport(id)
	local ok, err = pcall(function()
		TeleportService:TeleportToPlaceInstance(
			game.PlaceId, id, LocalPlayer)
	end)
	if not ok then
		TeleportInProgress = false
		AddIgnored(id, IGNORE_FAILED)
		Notify("❌ Teleport Error", "Call failed, retrying later")
		pcall(function()
			SendDebug("🐛 Teleport Call Failed", string.format("Server: `%s`\nError: `%s`", id, tostring(err)))
		end)
		ResetTeleportState()
		return false
	end
	return true
end

--- Waits until the current teleport either succeeds,
--- fails, or reaches its timeout.
---
--- @return string result `Success`, `Failed`, or `Timeout`.
--- @local
local function WaitTeleport()
	local start = os.clock()
	while TeleportInProgress and not TeleportFailed and os.clock() - start < TELEPORT_TIMEOUT do
		if game.JobId ~= OriginalJob then
			return "Success"
		end
		task.wait(0.1)
	end
	if TeleportFailed then
		return "Failed"
	end
	if game.JobId ~= OriginalJob then
		return "Success"
	end
	return "Timeout"
end

--- Finds and teleports to a low-population public server.
---
--- Candidate servers must contain between 1 and 3 players,
--- must not be the current server, and must not be present
--- in the temporary ignore list.
---
--- Failed API requests reset pagination after five consecutive failures.
---
--- @usage
--- ServerHop()
---
--- @return nil
--- @local
ServerHop = function()
	if IsHopping then
		return
	end
	IsHopping = true
	IgnoredServers = LoadIgnored()
	ResetTeleportState()
	local cursor = ""
	local apiFails = 0
	while Toggles.ServerHop and Toggles.ServerHop.Value and not Library.Unloaded do
		local forced = ForceServerHop
		ForceServerHop = false
		if not forced and not CanHop() then
			ResetTeleportState()
			task.wait(0.5)
			continue
		end
		local url = string.format("https://games.roblox.com/v1/games/%s/servers/Public?limit=100&sortOrder=Asc&excludeFullGames=true&cursor=%s", game.PlaceId, HttpService:UrlEncode(cursor))
		local ok, res = pcall(function()
			return HttpService:JSONDecode(game:HttpGet(url))
		end)
		if not ok or not res or type(res.data) ~= "table" then
			apiFails = apiFails + 1
			if apiFails >= 5 then
				cursor = ""
				apiFails = 0
				pcall(function()
					SendDebug("API Error", "Reset pagination after 5 failures")
				end)
			end
			task.wait(API_RETRY)
			continue
		end
		apiFails = 0
		local curJob = game.JobId
		local found = false
		for _, srv in ipairs(res.data) do
			if not Toggles.ServerHop.Value or Library.Unloaded then
				break
			end
			if not forced and not CanHop() then
				break
			end
			if srv.id and srv.id ~= curJob and srv.playing and srv.playing >= 1 and srv.playing <= 3 and not IsIgnored(srv.id) then
				found = true
				local id = srv.id
				local count = srv.playing
				AddIgnored(id, IGNORE_CANDIDATE)
				Notify("📡 Teleporting", string.format("%d player | %s", count, id:sub(1, 8)))
				task.wait(2)
				if not DoTeleport(id) then
					task.wait(TELEPORT_RETRY_WAIT)
					continue
				end
				local result = WaitTeleport()
				if result == "Success" then
					ResetTeleportState()
					IsHopping = false
					return
				elseif result == "Failed" then
					ResetTeleportState()
					task.wait(TELEPORT_RETRY_WAIT)
					continue
				else
					local failId = TargetServer
					if failId then
						AddIgnored(
							failId, IGNORE_FAILED)
						pcall(function()
							SendDebug("🐛 Teleport Timeout", string.format("Server %s no response in %ds", failId, TELEPORT_TIMEOUT))
						end)
					end
					Notify("⚠️ Timeout", "Server didn't respond, trying next")
					ResetTeleportState()
					task.wait(TELEPORT_RETRY_WAIT)
				end
			end
		end
		if not found then
			local nextCursor = res.nextPageCursor or ""
			if nextCursor ~= "" then
				cursor = nextCursor
				task.wait(PAGE_WAIT)
			else
				cursor = ""
				Notify("⚠️ Server Hop", "No 1-3 player server available")
				task.wait(NO_SERVER_WAIT)
			end
		end
	end
	ResetTeleportState()
	IsHopping = false
end

--- Enables or disables automated survivor farming.
AutoFarmGroup:AddToggle("EnableAutoFarm", {
	Text = "Enable Auto Farm",
	Tooltip = "Teleport Survivor to finish",
	Default = false,
})

--- Enables or disables automatic low-population server hopping.
AutoFarmGroup:AddToggle("ServerHop", {
	Text = "Server Hop",
	Tooltip = "Hop to 1-3 player servers when round is active",
	Default = false,
	Callback = function(v)
		if v then
			task.spawn(ServerHop)
		end
	end,
})

--- Remote loader URL used by `queue_on_teleport`.
--- @local
local LOADER_URL = "https://raw.githubusercontent.com/zaerrruwww/zryx-auto-farm-vd/refs/heads/main/main.lua"

--- Indicates whether the current teleport already has
--- an auto-execution payload queued.
--- @type boolean
--- @local
local AutoExecuteQueued = false

--- Queues the loader script for execution after teleport.
---
--- @return nil
--- @local
local function QueueAutoExec()
	if AutoExecuteQueued or not Toggles.AutoExecute.Value then
		return
	end
	if type(queue_on_teleport) ~= "function" then
		Notify("Auto Execute", "queue_on_teleport not available", 5)
		return
	end
	local code = string.format([[loadstring(game:HttpGet(%q))()]], LOADER_URL)
	local ok, err = pcall(function()
		queue_on_teleport(code)
	end)
	if ok then
		AutoExecuteQueued = true
		Notify("Auto Execute", "Queued for next teleport")
	else
		Notify("Auto Execute", "Failed: " .. tostring(err), 5)
	end
end

--- Enables or disables automatic execution after teleport.
AutoFarmGroup:AddToggle("AutoExecute", {
	Text = "Auto Execute",
	Tooltip = "Auto-execute script after server hop",
	Default = false,
	Callback = function(v)
		if v then
			QueueAutoExec()
		else
			AutoExecuteQueued = false
		end
	end,
})

--- Enables or disables the anti-idle protection.
AutoFarmGroup:AddToggle("AntiAfk", {
	Text = "Anti AFK",
	Tooltip = "Simulate input to avoid the 20-minute idle disconnect",
	Default = true,
})

--- Enables Discord webhook notifications.
WebhookGroup:AddToggle("EnableWebhook", {
	Text = "Enable Webhook",
	Default = false,
})

--- Webhook endpoint configuration input.
WebhookGroup:AddInput("WebhookLink", {
	Text = "Webhook Link",
	Default = "",
	Placeholder = "Enter webhook URL...",
	Numeric = false,
})

--- Sends a webhook test message.
WebhookGroup:AddButton("Test Webhook", function()
	local ok, msg = SendWebhook("🔔 Webhook Test", "Test from zryx!", true)
	if ok then
		Notify("Webhook Success", "Test message sent!")
	else
		Notify("Webhook Failed", msg, 5)
	end
end)

--- Settings menu group.
--- @local
local MenuGroup = Tabs.Settings:AddLeftGroupbox("Menu", "wrench")

--- Toggles visibility of the keybind menu.
MenuGroup:AddToggle("KeybindMenuOpen", {
	Default = Library.KeybindFrame.Visible,
	Text = "Open Keybind Menu",
	Callback = function(v)
		Library.KeybindFrame.Visible = v
	end,
})

--- Enables or disables the custom cursor.
MenuGroup:AddToggle("ShowCustomCursor", {
	Text = "Custom Cursor",
	Default = Library.ShowCustomCursor,
	Callback = function(v)
		Library.ShowCustomCursor = v
	end,
})

--- Controls the UI notification side.
MenuGroup:AddDropdown("NotificationSide", {
	Values = {
		"Left",
		"Right",
	},
	Default = "Right",
	Text = "Notification Side",
	Callback = function(v)
		Library:SetNotifySide(v)
	end,
})

--- Controls the UI DPI scale.
MenuGroup:AddDropdown("DPIDropdown", {
	Values = {
		"50%",
		"75%",
		"100%",
		"125%",
		"150%",
		"175%",
		"200%",
	},
	Default = "100%",
	Text = "DPI Scale",
	Callback = function(v)
		Library:SetDPIScale(
			tonumber(v:gsub("%%", "")))
	end,
})

--- Controls the UI corner radius.
MenuGroup:AddSlider("UICornerSlider", {
	Text = "Corner Radius",
	Default = Library.CornerRadius,
	Min = 0,
	Max = 20,
	Rounding = 0,
	Callback = function(v)
		Window:SetCornerRadius(v)
	end,
})
MenuGroup:AddDivider()

--- Configures the menu keybind.
MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
	Default = "RightShift",
	NoUI = true,
	Text = "Menu keybind",
})

--- Unloads the UI and script state.
MenuGroup:AddButton("Unload", function()
	Library:Unload()
end)
Library.ToggleKeybind = Options.MenuKeybind
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
ThemeManager:SetFolder("AutoFarm")
SaveManager:SetFolder("AutoFarm")
SaveManager:SetSubFolder("Settings")
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({
	"MenuKeybind",
})
SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)
SaveManager:LoadAutoloadConfig()

--- Queue auto-execution if enabled by the loaded configuration.
QueueAutoExec()

--- Prevents the client's 20-minute idle disconnect by simulating
--- input whenever the `Idled` event fires.
task.spawn(function()
	local VirtualUser = game:GetService("VirtualUser")
	LocalPlayer.Idled:Connect(function()
		if not (Toggles.AntiAfk and Toggles.AntiAfk.Value) then
			return
		end
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:Button2Down(Vector2.new(0, 0))
			task.wait(1)
			VirtualUser:Button2Up(Vector2.new(0, 0))
		end)
	end)
end)

--- Main Auto Farm worker.
---
--- Executes `BeatGame` once per second while the UI remains loaded.
--- Errors are isolated so one failed iteration does not terminate
--- the worker loop.
task.spawn(function()
	while not Library.Unloaded do
		pcall(BeatGame)
		task.wait(1)
	end
end)
