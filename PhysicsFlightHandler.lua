-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Variables
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Configuration
local FLY_SPEED = 50

-- State Variables
local character = nil
local humanoid = nil
local hrp = nil
local isFlying = false
local currentSpeed = FLY_SPEED
local currentVelocity = Vector3.zero
local floatUpVelocity = Vector3.zero

local linearVelocity = nil
local alignOrientation = nil
local renderConnection = nil
local antifling = nil

-- Anti-Fling System (Runs globally)
if antifling then
    antifling:Disconnect()
    antifling = nil
end

antifling = RunService.Stepped:Connect(function()
    for _, otherPlayer in pairs(Players:GetPlayers()) do
        if otherPlayer ~= player and otherPlayer.Character then
            for _, v in pairs(otherPlayer.Character:GetDescendants()) do
                if v:IsA("BasePart") then
                    v.CanCollide = false
                end
            end
        end
    end
end)

-- GUI Setup
local playerGui = player:WaitForChild("PlayerGui")
local existingGui = playerGui:FindFirstChild("FlyGui")
if existingGui then existingGui:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FlyGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "MainFrame"
frame.Size = UDim2.new(0, 180, 0, 130)
frame.Position = UDim2.new(0.7, 0, 0.3, 0)
frame.BackgroundColor3 = Color3.fromRGB(25, 27, 33)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -10, 0, 25)
title.Position = UDim2.new(0, 10, 0, 5)
title.BackgroundTransparency = 1
title.Text = "Fly"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 16
title.Font = Enum.Font.SourceSansBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 20)
statusLabel.Position = UDim2.new(0, 10, 0, 30)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Status: OFF"
statusLabel.TextColor3 = Color3.fromRGB(220, 60, 60)
statusLabel.TextSize = 14
statusLabel.Font = Enum.Font.SourceSans
statusLabel.Parent = frame

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -20, 0, 30)
toggleBtn.Position = UDim2.new(0, 10, 0, 55)
toggleBtn.BackgroundColor3 = Color3.fromRGB(45, 50, 62)
toggleBtn.Text = "ENABLE"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.TextSize = 14
toggleBtn.Font = Enum.Font.SourceSansBold
toggleBtn.Parent = frame

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 6)
btnCorner.Parent = toggleBtn

local speedBox = Instance.new("TextBox")
speedBox.Size = UDim2.new(1, -20, 0, 25)
speedBox.Position = UDim2.new(0, 10, 0, 92)
speedBox.BackgroundColor3 = Color3.fromRGB(15, 17, 22)
speedBox.Text = "Speed: " .. tostring(FLY_SPEED)
speedBox.TextColor3 = Color3.fromRGB(200, 200, 200)
speedBox.TextSize = 14
speedBox.Font = Enum.Font.SourceSans
speedBox.Parent = frame

local boxCorner = Instance.new("UICorner")
boxCorner.CornerRadius = UDim.new(0, 6)
boxCorner.Parent = speedBox

-- Function to Update GUI Visual State
local function updateGuiState()
    if isFlying then
        statusLabel.Text = "Status: ON"
        statusLabel.TextColor3 = Color3.fromRGB(60, 220, 60)
        toggleBtn.Text = "DISABLE"
    else
        statusLabel.Text = "Status: OFF"
        statusLabel.TextColor3 = Color3.fromRGB(220, 60, 60)
        toggleBtn.Text = "ENABLE"
    end
    speedBox.Text = "Speed: " .. tostring(math.round(currentSpeed))
end

-- Helper function to setup physics instances
local function enableFlightPhysics(isInitialEnable)
    if not hrp or not humanoid then return end

    local oldLV = hrp:FindFirstChild("FlyLinearVelocity")
    if oldLV then oldLV:Destroy() end

    local oldAO = hrp:FindFirstChild("FlyAlignOrientation")
    if oldAO then oldAO:Destroy() end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in animator:GetPlayingAnimationTracks() do
            track:Stop()
        end
    end

    linearVelocity = Instance.new("LinearVelocity")
    linearVelocity.Name = "FlyLinearVelocity"
    linearVelocity.MaxForce = 100000
    linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
    linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World

    local attachment = hrp:FindFirstChild("RootAttachment")
    if not attachment then
        attachment = Instance.new("Attachment")
        attachment.Name = "RootAttachment"
        attachment.Parent = hrp
    end

    linearVelocity.Attachment0 = attachment
    linearVelocity.Parent = hrp

    alignOrientation = Instance.new("AlignOrientation")
    alignOrientation.Name = "FlyAlignOrientation"
    alignOrientation.MaxTorque = 100000
    alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
    alignOrientation.Attachment0 = attachment
    alignOrientation.Responsiveness = 35
    alignOrientation.Parent = hrp

    humanoid.PlatformStand = true

    if isInitialEnable then
        task.spawn(function()
            local floatValue = Instance.new("NumberValue")
            floatValue.Value = 10
            
            local tweenInfo = TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
            local tween = TweenService:Create(floatValue, tweenInfo, {Value = 0})
            
            local connection
            connection = RunService.Heartbeat:Connect(function()
                if not isFlying then
                    floatUpVelocity = Vector3.zero
                    connection:Disconnect()
                    floatValue:Destroy()
                    return
                end
                floatUpVelocity = Vector3.new(0, floatValue.Value, 0)
            end)

            tween.Completed:Connect(function()
                floatUpVelocity = Vector3.zero
                connection:Disconnect()
                floatValue:Destroy()
            end)

            tween:Play()
        end)
    end
end

local function disableFlightPhysics()
    currentVelocity = Vector3.zero
    floatUpVelocity = Vector3.zero
    if linearVelocity then
        linearVelocity:Destroy()
        linearVelocity = nil
    end
    if alignOrientation then
        alignOrientation:Destroy()
        alignOrientation = nil
    end
    if humanoid then
        humanoid.PlatformStand = false
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
end

-- Update Movement Frame-by-Frame
local function onRenderStep(deltaTime)
    if not isFlying or not character or not humanoid or not hrp then return end

    if not humanoid.PlatformStand then
        humanoid.PlatformStand = true
    end

    local moveDir = humanoid.MoveDirection
    local camCFrame = camera.CFrame
    local targetVelocity = Vector3.zero

    if moveDir.Magnitude > 0 then
        local rawLook = Vector3.new(camCFrame.LookVector.X, 0, camCFrame.LookVector.Z)
        local flatLook = rawLook.Magnitude > 0 and rawLook.Unit or Vector3.new(0, 0, -1)

        local rawRight = Vector3.new(camCFrame.RightVector.X, 0, camCFrame.RightVector.Z)
        local flatRight = rawRight.Magnitude > 0 and rawRight.Unit or Vector3.new(1, 0, 0)

        local forwardInput = moveDir:Dot(flatLook)
        local rightInput = moveDir:Dot(flatRight)

        targetVelocity = (camCFrame.LookVector * forwardInput) + (camCFrame.RightVector * rightInput)
        if targetVelocity.Magnitude > 0 then
            local rawInputMagnitude = math.clamp(moveDir.Magnitude, 0, 1)
            local easedInput = rawInputMagnitude * rawInputMagnitude
            targetVelocity = targetVelocity.Unit * (currentSpeed * easedInput)
        end
    end

    currentVelocity = currentVelocity:Lerp(targetVelocity, math.min(deltaTime * 6, 1))

    if linearVelocity then
        linearVelocity.VectorVelocity = currentVelocity + floatUpVelocity
    end

    if alignOrientation then
        local baseCFrame = CFrame.lookAt(hrp.Position, hrp.Position + camCFrame.LookVector)
        local forwardSpeed = currentVelocity:Dot(camCFrame.LookVector)
        local pitchRatio = math.clamp(forwardSpeed / FLY_SPEED, -1, 1)
        alignOrientation.CFrame = baseCFrame * CFrame.Angles(-pitchRatio * math.rad(25), 0, 0)
    end
end

-- Toggle Flying State
local function toggleFly(forceState, speed)
    local wasFlying = isFlying

    if forceState ~= nil then
        isFlying = forceState
    else
        isFlying = not isFlying
    end

    currentSpeed = speed or currentSpeed or FLY_SPEED

    if isFlying then
        if not wasFlying then
            enableFlightPhysics(true)
            if not renderConnection then
                renderConnection = RunService.RenderStepped:Connect(onRenderStep)
            end
        end
    else
        disableFlightPhysics()
        if renderConnection then
            renderConnection:Disconnect()
            renderConnection = nil
        end
    end

    updateGuiState()
end

-- GUI Interactivity
toggleBtn.MouseButton1Click:Connect(function()
    toggleFly()
end)

speedBox.FocusLost:Connect(function()
    local cleanText = speedBox.Text:gsub("%D", "")
    local num = tonumber(cleanText)
    if num then
        currentSpeed = num
    end
    updateGuiState()
end)

-- Player Chat Commands (:fly, :fly <speed>, :fly me, :fly me <speed>, :unfly)
player.Chatted:Connect(function(msg)
    local lowerMsg = string.lower(msg)
    local args = string.split(lowerMsg, " ")

    if args[1] == ":fly" or args[1] == ";fly" then
        local speed = nil
        if args[2] == "me" then
            if args[3] then
                speed = tonumber(args[3])
            end
        elseif args[2] then
            speed = tonumber(args[2])
        end
        toggleFly(true, speed)
    elseif lowerMsg == ":unfly" or lowerMsg == ":unfly me" or lowerMsg == ";unfly" or lowerMsg == ";unfly me" then
        toggleFly(false)
    end
end)

-- Character Handling
local function onCharacterAdded(newChar)
    character = newChar
    humanoid = character:WaitForChild("Humanoid")
    hrp = character:WaitForChild("HumanoidRootPart")

    toggleFly(false)

    humanoid.Died:Connect(function()
        toggleFly(false)
    end)
end

if player.Character then
    onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
