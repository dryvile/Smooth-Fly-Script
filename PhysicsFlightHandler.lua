-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Variables
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- State Variables
local character = nil
local humanoid = nil
local hrp = nil
local isFlying = false
local currentSpeed = 16
local currentVelocity = Vector3.zero
local floatUpVelocity = Vector3.zero
local currentPitch = 0

local linearVelocity = nil
local alignOrientation = nil
local renderConnection = nil
local antifling = nil

-- Configuration
local FLY_SPEED = 16

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
    linearVelocity.MaxForce = 1000000
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
    alignOrientation.MaxTorque = 1000000
    alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
    alignOrientation.Attachment0 = attachment
    alignOrientation.Responsiveness = 200
    alignOrientation.Parent = hrp

    humanoid.PlatformStand = true
    humanoid.AutoRotate = false

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
    currentPitch = 0

    if linearVelocity then
        linearVelocity:Destroy()
        linearVelocity = nil
    end

    if alignOrientation then
        alignOrientation:Destroy()
        alignOrientation = nil
    end

    if humanoid and hrp then
        humanoid.PlatformStand = false
        humanoid.AutoRotate = true
        -- Reset linear velocity to prevent physics glitching upon landing
        hrp.AssemblyLinearVelocity = Vector3.zero
        humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
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
            targetVelocity = targetVelocity.Unit * currentSpeed
        end
    end

    currentVelocity = currentVelocity:Lerp(targetVelocity, 1 - math.exp(-12 * deltaTime))

    if linearVelocity then
        linearVelocity.VectorVelocity = currentVelocity + floatUpVelocity
    end

    if alignOrientation then
        local baseCFrame = CFrame.lookAt(hrp.Position, hrp.Position + camCFrame.LookVector)
        local forwardSpeed = currentVelocity:Dot(camCFrame.LookVector)
        local targetPitchRatio = math.clamp(forwardSpeed / 50, -1, 1)
        local targetPitch = -targetPitchRatio * math.rad(25)

        -- Smoothly ease into/out of the lean angle
        currentPitch = currentPitch + (targetPitch - currentPitch) * (1 - math.exp(-8 * deltaTime))
        alignOrientation.CFrame = baseCFrame * CFrame.Angles(currentPitch, 0, 0)
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

    currentSpeed = speed or (humanoid and humanoid.WalkSpeed) or FLY_SPEED

    if isFlying then
        if not wasFlying then
            enableFlightPhysics(true)
            if not renderConnection then
                renderConnection = RunService.PreSimulation:Connect(onRenderStep)
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

-- Player Chat Commands (;fly, ;fly <speed>, ;fly me, ;fly me <speed>, ;unfly)
player.Chatted:Connect(function(msg)
    local lowerMsg = string.lower(msg)
    local args = string.split(lowerMsg, " ")

    if args[1] == ";fly" then
        local speed = nil
        if args[2] == "me" then
            if args[3] then
                speed = tonumber(args[3])
            end
        elseif args[2] then
            speed = tonumber(args[2])
        end
        toggleFly(true, speed)
    elseif lowerMsg == ";unfly" or lowerMsg == ";unfly me" then
        toggleFly(false)
    end
end)

-- Character Handling
local function onCharacterAdded(newChar)
    character = newChar
    humanoid = character:WaitForChild("Humanoid")
    hrp = character:WaitForChild("HumanoidRootPart")

    toggleFly(false)

    local deathConn
    deathConn = humanoid.Died:Connect(function()
        toggleFly(false)
        if deathConn then
            deathConn:Disconnect()
            deathConn = nil
        end
    end)
end

if player.Character then
    onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
