-- Vega Hub | MM2 AutoFarm (Anti-AFK + Pill Toggle + Top-Right Close X + On Floor + Speed 1-25)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")

local player = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait() and Players.LocalPlayer

local state = {
	autoFarm = false,
	antiAfk = true, -- защита от кика за 20 мин бездействия
	speed = 12, -- 1 (медленно) .. 25 (максимум)
	minSpeed = 1,
	maxSpeed = 25,
	floorTouchOffset = 0.25, -- позиция прямо на поверхности пола, чтобы касаться монеты
	noClip = true,
	faceUpAngle = 90, -- горизонтальное положение у пола
	maxFarmDistance = 140, -- не лететь с лобби
}

local function getGuiParent()
	if typeof(gethui) == "function" then
		local ok, res = pcall(gethui)
		if ok and res then
			return res
		end
	end

	local okCore, core = pcall(function()
		return game:GetService("CoreGui")
	end)
	if okCore and core then
		local testOk = pcall(function()
			local f = Instance.new("Folder")
			f.Name = "VegaGuiProbe"
			f.Parent = core
			f:Destroy()
		end)
		if testOk then
			return core
		end
	end

	local lp = Players.LocalPlayer
	return lp and lp:WaitForChild("PlayerGui", 10)
end

local function getCharacterParts()
	local char = player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return nil end
	return char, hrp, hum
end

local savedAnimSpeed = 1
local function freezeAnimations(hum)
	if not hum then return end
	hum.PlatformStand = true
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:AdjustSpeed(0)
		end
	end
end

local function restoreNormalPose(hum)
	if not hum then return end
	hum.PlatformStand = false
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:AdjustSpeed(savedAnimSpeed)
		end
	end
end

local function getActiveRoundMap()
	local lobby = workspace:FindFirstChild("Lobby")
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj ~= lobby and obj:IsA("Model") then
			local coinContainer = obj:FindFirstChild("CoinContainer", true)
			if coinContainer then
				return obj, coinContainer
			end
		end
	end

	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj.Name == "CoinContainer" then
			if lobby and obj:IsDescendantOf(lobby) then
				continue
			end
			return obj.Parent, obj
		end
	end

	return nil, nil
end

local function findRoundCoins(coinContainer)
	local coins = {}
	if not coinContainer then return coins end

	for _, coin in ipairs(coinContainer:GetChildren()) do
		if coin:IsA("BasePart") and coin.Parent then
			local hasTouch = coin:FindFirstChildWhichIsA("TouchTransmitter", true) ~= nil
			if coin.Transparency < 0.95 or hasTouch then
				table.insert(coins, coin)
			end
		elseif coin:IsA("Model") and coin.PrimaryPart then
			table.insert(coins, coin.PrimaryPart)
		end
	end

	return coins
end

local function getNearestCoin(coins, fromPos)
	local closest = nil
	local minDist = math.huge
	for _, coin in ipairs(coins) do
		if coin and coin.Parent then
			local d = (coin.Position - fromPos).Magnitude
			if d < minDist then
				minDist = d
				closest = coin
			end
		end
	end
	return closest, minDist
end

local function getFloorSurfaceY(targetCoin)
	local coinPos = targetCoin.Position
	local rayOrigin = Vector3.new(coinPos.X, coinPos.Y + 4, coinPos.Z)
	local rayDirection = Vector3.new(0, -10, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignoreList = {}
	if player.Character then
		table.insert(ignoreList, player.Character)
	end
	local coinContainer = targetCoin.Parent
	if coinContainer then
		table.insert(ignoreList, coinContainer)
	end
	params.FilterDescendantsInstances = ignoreList

	local result = workspace:Raycast(rayOrigin, rayDirection, params)
	if result then
		return result.Position.Y
	end

	return coinPos.Y
end

local function rollSmoothlyToTarget(hrp, hum, currentPos, targetPos, dt)
	freezeAnimations(hum)

	local delta = targetPos - currentPos
	local dist = delta.Magnitude
	local stepDist = math.max(state.speed * dt, 0.004)

	local nextPos
	if dist > stepDist then
		nextPos = currentPos + delta.Unit * stepDist
	else
		nextPos = targetPos
	end

	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	hrp.CFrame = CFrame.new(nextPos) * CFrame.Angles(math.rad(state.faceUpAngle), 0, 0)
end

-- ==================== АНТИ-AFK ====================
player.Idled:Connect(function()
	if not state.antiAfk then return end
	pcall(function()
		local cam = workspace.CurrentCamera
		local cf = cam and cam.CFrame or CFrame.new()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new(0, 0), cf)
	end)
end)

task.spawn(function()
	while true do
		task.wait(600) -- каждые 10 минут мягкий пульс для сохранения активности сессии
		if state.antiAfk then
			pcall(function()
				local cam = workspace.CurrentCamera
				local cf = cam and cam.CFrame or CFrame.new()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.new(0, 0), cf)
			end)
		end
	end
end)

-- ==================== GUI: VEGA HUB ====================
local guiParent = getGuiParent()
if not guiParent then return end

local oldGui = guiParent:FindFirstChild("VegaHubGui")
if oldGui then oldGui:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "VegaHubGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = guiParent

local panelHeight = 208

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.fromOffset(296, panelHeight)
mainFrame.Position = UDim2.fromScale(0.05, 0.25)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Visible = false
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = mainFrame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(58, 64, 82)
stroke.Thickness = 1
stroke.Parent = mainFrame

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 40)
header.BackgroundColor3 = Color3.fromRGB(28, 31, 40)
header.BorderSizePixel = 0
header.Parent = mainFrame

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 12)
headerCorner.Parent = header

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -54, 1, 0)
titleLabel.Position = UDim2.fromOffset(14, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 15
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextColor3 = Color3.fromRGB(240, 244, 255)
titleLabel.Text = "VEGA HUB  •  MM2"
titleLabel.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseButton"
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.Position = UDim2.new(1, -36, 0.5, -14)
closeBtn.BackgroundColor3 = Color3.fromRGB(45, 49, 64)
closeBtn.BorderSizePixel = 0
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.TextColor3 = Color3.fromRGB(235, 240, 255)
closeBtn.Text = "✕"
closeBtn.AutoButtonColor = false
closeBtn.Parent = header

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = closeBtn

local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, -24, 1, -50)
content.Position = UDim2.fromOffset(12, 46)
content.BackgroundTransparency = 1
content.Parent = mainFrame

local tweenInfo = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function createCapsuleToggle(parent, yPos, labelText, initialValue, onChanged)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 42)
	row.Position = UDim2.fromOffset(0, yPos)
	row.BackgroundColor3 = Color3.fromRGB(29, 32, 42)
	row.BorderSizePixel = 0
	row.Parent = parent

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 10)
	rowCorner.Parent = row

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -74, 1, 0)
	lbl.Position = UDim2.fromOffset(12, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamSemibold
	lbl.TextSize = 13
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextColor3 = Color3.fromRGB(235, 238, 245)
	lbl.Text = labelText
	lbl.Parent = row

	local capsule = Instance.new("TextButton")
	capsule.Size = UDim2.fromOffset(50, 24)
	capsule.Position = UDim2.new(1, -60, 0.5, -12)
	capsule.BackgroundColor3 = initialValue and Color3.fromRGB(46, 196, 118) or Color3.fromRGB(65, 70, 88)
	capsule.Text = ""
	capsule.AutoButtonColor = false
	capsule.Parent = row

	local capsuleCorner = Instance.new("UICorner")
	capsuleCorner.CornerRadius = UDim.new(1, 0)
	capsuleCorner.Parent = capsule

	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(18, 18)
	knob.Position = initialValue and UDim2.fromOffset(29, 3) or UDim2.fromOffset(3, 3)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	knob.Parent = capsule

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob

	local current = initialValue
	local function setVal(v)
		current = v
		TweenService:Create(knob, tweenInfo, {
			Position = current and UDim2.fromOffset(29, 3) or UDim2.fromOffset(3, 3)
		}):Play()
		TweenService:Create(capsule, tweenInfo, {
			BackgroundColor3 = current and Color3.fromRGB(46, 196, 118) or Color3.fromRGB(65, 70, 88)
		}):Play()
		if onChanged then
			onChanged(current)
		end
	end

	capsule.MouseButton1Click:Connect(function()
		setVal(not current)
	end)

	return setVal
end

-- 1. Плавный тумблер Автофарм
createCapsuleToggle(content, 0, "Автофарм", state.autoFarm, function(val)
	state.autoFarm = val
	if not val then
		local _, _, hum = getCharacterParts()
		restoreNormalPose(hum)
	end
end)

-- 2. Плавный тумблер Анти-AFK
createCapsuleToggle(content, 48, "Анти-AFK", state.antiAfk, function(val)
	state.antiAfk = val
end)

-- 3. Ползунок скорости (1 .. 25)
local speedBox = Instance.new("Frame")
speedBox.Size = UDim2.new(1, 0, 0, 54)
speedBox.Position = UDim2.fromOffset(0, 96)
speedBox.BackgroundColor3 = Color3.fromRGB(29, 32, 42)
speedBox.BorderSizePixel = 0
speedBox.Parent = content

local speedCorner = Instance.new("UICorner")
speedCorner.CornerRadius = UDim.new(0, 10)
speedCorner.Parent = speedBox

local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.new(1, -24, 0, 20)
speedLabel.Position = UDim2.fromOffset(12, 4)
speedLabel.BackgroundTransparency = 1
speedLabel.Font = Enum.Font.GothamSemibold
speedLabel.TextSize = 12
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.TextColor3 = Color3.fromRGB(210, 215, 230)
speedLabel.Text = "Скорость: " .. tostring(state.speed) .. " / " .. tostring(state.maxSpeed)
speedLabel.Parent = speedBox

local track = Instance.new("Frame")
track.Size = UDim2.new(1, -24, 0, 8)
track.Position = UDim2.fromOffset(12, 33)
track.BackgroundColor3 = Color3.fromRGB(52, 57, 74)
track.BorderSizePixel = 0
track.Parent = speedBox

local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(1, 0)
trackCorner.Parent = track

local initAlpha = math.clamp((state.speed - state.minSpeed) / (state.maxSpeed - state.minSpeed), 0, 1)

local fill = Instance.new("Frame")
fill.Size = UDim2.new(initAlpha, 0, 1, 0)
fill.BackgroundColor3 = Color3.fromRGB(92, 148, 255)
fill.BorderSizePixel = 0
fill.Parent = track

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = fill

local sliderKnob = Instance.new("Frame")
sliderKnob.Size = UDim2.fromOffset(16, 16)
sliderKnob.AnchorPoint = Vector2.new(0.5, 0.5)
sliderKnob.Position = UDim2.new(initAlpha, 0, 0.5, 0)
sliderKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
sliderKnob.BorderSizePixel = 0
sliderKnob.Parent = track

local sliderKnobCorner = Instance.new("UICorner")
sliderKnobCorner.CornerRadius = UDim.new(1, 0)
sliderKnobCorner.Parent = sliderKnob

local dragging = false
local function updateSpeedFromInput(inputX)
	local relX = math.clamp((inputX - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
	fill.Size = UDim2.new(relX, 0, 1, 0)
	sliderKnob.Position = UDim2.new(relX, 0, 0.5, 0)
	state.speed = math.clamp(math.floor(state.minSpeed + (state.maxSpeed - state.minSpeed) * relX + 0.5), state.minSpeed, state.maxSpeed)
	speedLabel.Text = "Скорость: " .. tostring(state.speed) .. " / " .. tostring(state.maxSpeed)
end

track.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		updateSpeedFromInput(input.Position.X)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		updateSpeedFromInput(input.Position.X)
	end
end)

-- Кнопка Vega Hub: открывает меню и пропадает
local pillBtn = Instance.new("TextButton")
pillBtn.Name = "VegaHubPill"
pillBtn.Size = UDim2.fromOffset(112, 30)
pillBtn.Position = UDim2.fromOffset(66, 74)
pillBtn.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
pillBtn.BackgroundTransparency = 0.08
pillBtn.BorderSizePixel = 0
pillBtn.Font = Enum.Font.GothamBold
pillBtn.TextSize = 12
pillBtn.TextColor3 = Color3.fromRGB(242, 245, 255)
pillBtn.Text = "Vega Hub"
pillBtn.AutoButtonColor = false
pillBtn.Active = true
pillBtn.Draggable = true
pillBtn.ZIndex = 10
pillBtn.Parent = screenGui

local pillCorner = Instance.new("UICorner")
pillCorner.CornerRadius = UDim.new(0, 8)
pillCorner.Parent = pillBtn

local pillStroke = Instance.new("UIStroke")
pillStroke.Color = Color3.fromRGB(72, 82, 118)
pillStroke.Thickness = 1
pillStroke.Parent = pillBtn

pillBtn.MouseButton1Click:Connect(function()
	mainFrame.Visible = true
	pillBtn.Visible = false
end)

closeBtn.MouseButton1Click:Connect(function()
	mainFrame.Visible = false
	pillBtn.Visible = true
end)

-- ==================== ЛОГИКА АВТОФАРМА ====================
RunService.Stepped:Connect(function()
	if not state.autoFarm or not state.noClip then return end
	local char = player.Character
	if char then
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") and part.CanCollide then
				part.CanCollide = false
			end
		end
	end
end)

RunService.Heartbeat:Connect(function(dt)
	if not state.autoFarm then return end

	local char, hrp, hum = getCharacterParts()
	if not char then return end

	local activeMap, coinContainer = getActiveRoundMap()
	if not activeMap or not coinContainer then
		restoreNormalPose(hum)
		return
	end

	local coins = findRoundCoins(coinContainer)
	if #coins == 0 then
		restoreNormalPose(hum)
		return
	end

	local targetCoin, distToCoin = getNearestCoin(coins, hrp.Position)
	if not targetCoin or not distToCoin or distToCoin > state.maxFarmDistance then
		restoreNormalPose(hum)
		return
	end

	local floorSurfaceY = getFloorSurfaceY(targetCoin)
	local targetY = math.max(floorSurfaceY + state.floorTouchOffset, targetCoin.Position.Y)
	local targetPos = Vector3.new(targetCoin.Position.X, targetY, targetCoin.Position.Z)

	rollSmoothlyToTarget(hrp, hum, hrp.Position, targetPos, dt)
end)
