-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextChatService = game:GetService("TextChatService")

-- Variables
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Configuration
local FLY_SPEED = 50
local LERP_SMOOTHNESS = 6 -- Smooth movement responsiveness factor

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

-- Anti-Fling System (Optimized pass to prevent severe lag)
if antifling then
    antifling:Disconnect()
    antifling = nil
end

antifling = RunService.Stepped:Connect(function()
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player and otherPlayer.Character then
            for _, v in ipairs(otherPlayer.Character:GetChildren()) do
                if v:IsA("BasePart") and v.CanCollide then
                    v.CanCollide = false
                end
            end
        end
    end
end)

-- Helper function to setup physics instances
local function enableFlightPhysics(isInitialEnable)
    if not hrp or not humanoid then return end

    -- Clean up existing forces
    local oldLV = hrp:FindFirstChild("FlyLinearVelocity")
    if oldLV then oldLV:Destroy() end

    local oldAO = hrp:FindFirstChild("FlyAlignOrientation")
    if oldAO then oldAO:Destroy() end

    -- Stop active animation tracks safely
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in animator:GetPlayingAnimationTracks() do
            track:Stop()
        end
    end

    -- Create LinearVelocity for smooth directional flying
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

    -- Create AlignOrientation to keep player facing camera direction
    alignOrientation = Instance.new("AlignOrientation")
    alignOrientation.Name = "FlyAlignOrientation"
    alignOrientation.MaxTorque = 100000
    alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
    alignOrientation.Attachment0 = attachment
    alignOrientation.Responsiveness = 35
    alignOrientation.Parent = hrp

    humanoid.PlatformStand = true

    -- Smoothly float up using physics speed rather than resetting CFrame mid-physics
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
                    if connection then connection:Disconnect() end
                    floatValue:Destroy()
                    return
                end
                floatUpVelocity = Vector3.new(0, floatValue.Value, 0)
            end)

            tween.Completed:Connect(function()
                floatUpVelocity = Vector3.zero
                if connection then connection:Disconnect() end
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

    -- Frame-rate independent Lerp interpolation calculation
    local alpha = 1 - math.exp(-LERP_SMOOTHNESS * deltaTime)
    currentVelocity = currentVelocity:Lerp(targetVelocity, alpha)

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

    currentSpeed = speed or FLY_SPEED

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
end

-- Chat Command Processing Function
local function parseCommand(msg)
    local lowerMsg = string.lower(msg)
    local args = string.split(lowerMsg, " ")

    if args[1] == ":fly" then
        local speed = nil
        if args[2] == "me" then
            if args[3] then
                speed = tonumber(args[3])
            end
        elseif args[2] then
            speed = tonumber(args[2])
        end
        toggleFly(true, speed)
    elseif lowerMsg == ":unfly" or lowerMsg == ":unfly me" then
        toggleFly(false)
    end
end

-- Player Chat Commands (Supports both modern TextChatService & legacy chat)
if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
    TextChatService.OnIncomingChatMessage = function(message)
        if message.TextSource and message.TextSource.UserId == player.UserId then
            parseCommand(message.Text)
        end
    end
else
    player.Chatted:Connect(parseCommand)
end

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
