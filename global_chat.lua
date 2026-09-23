-- ==============================================================================
-- 💬 SERENITY HUB - GLOBAL CHAT SYSTEM (STANDALONE GUI)
-- ==============================================================================
-- Connects all players running Serenity Hub across different Roblox games & servers!
-- Works in any Roblox executor (Synapse, Wave, KRNL, Fluxus, Delta, Solara, etc.)
-- Features: Real-time global messaging, player headshots, auto-scroll, anti-spam,
--           draggable window, minimize pill, and differential polling.
-- ==============================================================================

local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

-- Prevent duplicate instances if executed multiple times
if _G.SerenityGlobalChatGui and _G.SerenityGlobalChatGui.Parent then
    pcall(function() _G.SerenityGlobalChatGui:Destroy() end)
end

local ChatConfig = {
    ApiUrls = {
        "https://serenityhub.site/api/chat",
        "https://www.serenityhub.site/api/chat",
        "https://serenity-admin-5pra.onrender.com/api/chat",
        "http://localhost:3000/api/chat"
    },
    PollInterval = 2.5,              -- Poll for new messages every 2.5 seconds
    MaxDisplayMessages = 70,         -- Maximum chat bubbles kept in the feed
    CooldownSeconds = 1.5,           -- Anti-spam cooldown per message
    SoundEnabled = true,
    ToggleKey = Enum.KeyCode.RightShift
}

-- State
local lastMessageId = 0
local activeBaseUrl = nil
local lastSendTime = 0
local isWindowVisible = true
local isMinimized = false
local unreadCount = 0

-- Target GUI container
local function GetGuiParent()
    local parent = nil
    pcall(function() parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    if not parent or not pcall(function() return parent.Name end) then
        parent = localPlayer:WaitForChild("PlayerGui")
    end
    return parent
end

-- ==============================================================================
-- Universal HTTP Helpers
-- ==============================================================================
local function FetchRaw(url)
    local reqFn = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if reqFn then
        local ok, res = pcall(function()
            return reqFn({
                Url = url,
                Method = "GET",
                Headers = { ["Cache-Control"] = "no-cache" }
            })
        end)
        if ok and res then
            local body = res.Body or res.body
            if body and body ~= "" and body ~= "null" then
                return body
            end
        end
    end

    if game.HttpGet then
        local ok, body = pcall(function() return game:HttpGet(url) end)
        if ok and body and body ~= "" and body ~= "null" then
            return body
        end
    end

    if HttpService and HttpService.GetAsync then
        local ok, body = pcall(function() return HttpService:GetAsync(url) end)
        if ok and body and body ~= "" and body ~= "null" then
            return body
        end
    end

    return nil
end

local function PostRaw(url, payloadJson)
    local reqFn = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if reqFn then
        local ok, res = pcall(function()
            return reqFn({
                Url = url,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["Cache-Control"] = "no-cache"
                },
                Body = payloadJson
            })
        end)
        if ok and res then
            local body = res.Body or res.body
            local code = res.StatusCode or res.Status or 200
            return body, code
        end
    end

    if HttpService and HttpService.PostAsync then
        local ok, body = pcall(function()
            return HttpService:PostAsync(url, payloadJson, Enum.HttpContentType.ApplicationJson)
        end)
        if ok and body and body ~= "" then
            return body, 200
        end
    end

    return nil, 0
end

-- Resolve working API endpoint
local function GetWorkingApiUrl()
    if activeBaseUrl then return activeBaseUrl end
    for _, base in ipairs(ChatConfig.ApiUrls) do
        local testUrl = string.format("%s/messages?limit=1&_t=%d", base, os.time())
        local raw = FetchRaw(testUrl)
        if raw then
            local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
            if ok and data and data.success then
                activeBaseUrl = base
                return activeBaseUrl
            end
        end
    end
    -- Fallback to primary domain
    activeBaseUrl = ChatConfig.ApiUrls[1]
    return activeBaseUrl
end

-- Logo asset loader
local cachedLogoAsset = nil
local function GetLogoImage()
    if cachedLogoAsset then return cachedLogoAsset end
    local getAsset = (syn and syn.custom_asset) or getcustomasset or getsynasset
    if getAsset and writefile and isfile then
        local ok, asset = pcall(function()
            if not isfile("serenity_logo_v2.png") then
                local imgData = FetchRaw("https://serenityhub.site/serenity_logo_v2.png")
                    or FetchRaw("https://raw.githubusercontent.com/TripNation/announcement/main/serenity_logo_v2.png")
                    or FetchRaw("http://localhost:3000/serenity_logo_v2.png")
                if imgData and #imgData > 200 then
                    writefile("serenity_logo_v2.png", imgData)
                end
            end
            if isfile("serenity_logo_v2.png") then
                return getAsset("serenity_logo_v2.png")
            end
        end)
        if ok and asset then
            cachedLogoAsset = asset
            return cachedLogoAsset
        end
    end
    return "rbxassetid://10709790644"
end

-- ==============================================================================
-- GUI Construction
-- ==============================================================================
local targetParent = GetGuiParent()
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SerenityGlobalChatGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = targetParent
_G.SerenityGlobalChatGui = screenGui

-- Main Chat Window
local mainWindow = Instance.new("Frame")
mainWindow.Name = "MainWindow"
mainWindow.Size = UDim2.new(0, 360, 0, 460)
mainWindow.Position = UDim2.new(0.5, -180, 0.5, -230)
mainWindow.BackgroundColor3 = Color3.fromRGB(15, 17, 24)
mainWindow.BorderSizePixel = 0
mainWindow.ClipsDescendants = true
mainWindow.Parent = screenGui

local windowCorner = Instance.new("UICorner")
windowCorner.CornerRadius = UDim.new(0, 12)
windowCorner.Parent = mainWindow

local windowStroke = Instance.new("UIStroke")
windowStroke.Color = Color3.fromRGB(38, 44, 62)
windowStroke.Thickness = 1.2
windowStroke.Parent = mainWindow

-- Neon accent top glow bar
local accentBar = Instance.new("Frame")
accentBar.Name = "AccentBar"
accentBar.Size = UDim2.new(1, 0, 0, 3)
accentBar.Position = UDim2.new(0, 0, 0, 0)
accentBar.BorderSizePixel = 0
accentBar.BackgroundColor3 = Color3.fromRGB(0, 210, 255)
accentBar.Parent = mainWindow

local accentGradient = Instance.new("UIGradient")
accentGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 210, 255)),
    ColorSequenceKeypoint.new(0.6, Color3.fromRGB(130, 90, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 210, 255))
})
accentGradient.Parent = accentBar

-- Title Header Bar (Draggable)
local headerBar = Instance.new("Frame")
headerBar.Name = "HeaderBar"
headerBar.Size = UDim2.new(1, 0, 0, 48)
headerBar.Position = UDim2.new(0, 0, 0, 3)
headerBar.BackgroundColor3 = Color3.fromRGB(20, 23, 33)
headerBar.BorderSizePixel = 0
headerBar.Parent = mainWindow

-- Logo Icon
local logoImg = Instance.new("ImageLabel")
logoImg.Name = "Logo"
logoImg.Size = UDim2.new(0, 28, 0, 28)
logoImg.Position = UDim2.new(0, 12, 0.5, -14)
logoImg.BackgroundTransparency = 1
logoImg.Image = GetLogoImage()
logoImg.ScaleType = Enum.ScaleType.Fit
logoImg.Parent = headerBar

local logoCorner = Instance.new("UICorner")
logoCorner.CornerRadius = UDim.new(0, 6)
logoCorner.Parent = logoImg

-- Title Text
local titleLbl = Instance.new("TextLabel")
titleLbl.Name = "Title"
titleLbl.Size = UDim2.new(0, 160, 0, 18)
titleLbl.Position = UDim2.new(0, 48, 0, 8)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "Serenity Global Chat"
titleLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 13
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Parent = headerBar

-- Subtitle / Live Indicator
local statusIndicator = Instance.new("Frame")
statusIndicator.Name = "StatusDot"
statusIndicator.Size = UDim2.new(0, 6, 0, 6)
statusIndicator.Position = UDim2.new(0, 49, 0, 31)
statusIndicator.BackgroundColor3 = Color3.fromRGB(0, 230, 140)
statusIndicator.BorderSizePixel = 0
statusIndicator.Parent = headerBar

local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = statusIndicator

local statusLbl = Instance.new("TextLabel")
statusLbl.Name = "Status"
statusLbl.Size = UDim2.new(0, 140, 0, 14)
statusLbl.Position = UDim2.new(0, 60, 0, 26)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "Connected • Hub Wide"
statusLbl.TextColor3 = Color3.fromRGB(150, 160, 180)
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 10
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Parent = headerBar

-- Minimize Button ("-")
local minBtn = Instance.new("TextButton")
minBtn.Name = "MinBtn"
minBtn.Size = UDim2.new(0, 26, 0, 26)
minBtn.Position = UDim2.new(1, -60, 0.5, -13)
minBtn.BackgroundTransparency = 1
minBtn.Text = "—"
minBtn.TextColor3 = Color3.fromRGB(160, 165, 185)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 13
minBtn.Parent = headerBar

-- Close Button ("X")
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseBtn"
closeBtn.Size = UDim2.new(0, 26, 0, 26)
closeBtn.Position = UDim2.new(1, -32, 0.5, -13)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(160, 165, 185)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.Parent = headerBar

-- Messages Scroll Container
local scrollContainer = Instance.new("ScrollingFrame")
scrollContainer.Name = "MessagesScroll"
scrollContainer.Size = UDim2.new(1, -16, 1, -114)
scrollContainer.Position = UDim2.new(0, 8, 0, 56)
scrollContainer.BackgroundTransparency = 1
scrollContainer.BorderSizePixel = 0
scrollContainer.ScrollBarThickness = 4
scrollContainer.ScrollBarImageColor3 = Color3.fromRGB(45, 52, 75)
scrollContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollContainer.BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
scrollContainer.TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
scrollContainer.Parent = mainWindow

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 8)
listLayout.Parent = scrollContainer

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 4)
listPadding.PaddingBottom = UDim.new(0, 6)
listPadding.PaddingLeft = UDim.new(0, 2)
listPadding.PaddingRight = UDim.new(0, 6)
listPadding.Parent = scrollContainer

-- Input Bar Container
local inputContainer = Instance.new("Frame")
inputContainer.Name = "InputContainer"
inputContainer.Size = UDim2.new(1, -16, 0, 46)
inputContainer.Position = UDim2.new(0, 8, 1, -52)
inputContainer.BackgroundColor3 = Color3.fromRGB(22, 25, 36)
inputContainer.BorderSizePixel = 0
inputContainer.Parent = mainWindow

local inputCorner = Instance.new("UICorner")
inputCorner.CornerRadius = UDim.new(0, 8)
inputCorner.Parent = inputContainer

local inputStroke = Instance.new("UIStroke")
inputStroke.Color = Color3.fromRGB(38, 44, 62)
inputStroke.Thickness = 1
inputStroke.Parent = inputContainer

-- Text Input Box
local chatInput = Instance.new("TextBox")
chatInput.Name = "ChatInput"
chatInput.Size = UDim2.new(1, -54, 1, 0)
chatInput.Position = UDim2.new(0, 10, 0, 0)
chatInput.BackgroundTransparency = 1
chatInput.PlaceholderText = "Type message... (Enter to send)"
chatInput.PlaceholderColor3 = Color3.fromRGB(110, 115, 135)
chatInput.Text = ""
chatInput.TextColor3 = Color3.fromRGB(240, 245, 255)
chatInput.Font = Enum.Font.GothamMedium
chatInput.TextSize = 12
chatInput.TextXAlignment = Enum.TextXAlignment.Left
chatInput.ClearTextOnFocus = false
chatInput.Parent = inputContainer

-- Send Button
local sendBtn = Instance.new("TextButton")
sendBtn.Name = "SendBtn"
sendBtn.Size = UDim2.new(0, 36, 0, 34)
sendBtn.Position = UDim2.new(1, -40, 0.5, -17)
sendBtn.BackgroundColor3 = Color3.fromRGB(0, 210, 255)
sendBtn.BorderSizePixel = 0
sendBtn.Text = "➤"
sendBtn.TextColor3 = Color3.fromRGB(10, 12, 18)
sendBtn.Font = Enum.Font.GothamBold
sendBtn.TextSize = 14
sendBtn.Parent = inputContainer

local sendBtnCorner = Instance.new("UICorner")
sendBtnCorner.CornerRadius = UDim.new(0, 6)
sendBtnCorner.Parent = sendBtn

-- Cooldown / Char Count Pill
local cooldownLbl = Instance.new("TextLabel")
cooldownLbl.Name = "CooldownLbl"
cooldownLbl.Size = UDim2.new(0, 100, 0, 12)
cooldownLbl.Position = UDim2.new(1, -118, 0, -14)
cooldownLbl.BackgroundTransparency = 1
cooldownLbl.Text = "0/200"
cooldownLbl.TextColor3 = Color3.fromRGB(110, 115, 135)
cooldownLbl.Font = Enum.Font.Gotham
cooldownLbl.TextSize = 10
cooldownLbl.TextXAlignment = Enum.TextXAlignment.Right
cooldownLbl.Parent = inputContainer

-- Floating Mini-Pill (When minimized or toggled closed)
local floatingPill = Instance.new("TextButton")
floatingPill.Name = "FloatingChatPill"
floatingPill.Size = UDim2.new(0, 140, 0, 36)
floatingPill.Position = UDim2.new(1, -155, 1, -50)
floatingPill.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
floatingPill.BorderSizePixel = 0
floatingPill.Text = "  💬 Global Chat"
floatingPill.TextColor3 = Color3.fromRGB(240, 245, 255)
floatingPill.Font = Enum.Font.GothamBold
floatingPill.TextSize = 12
floatingPill.Visible = false
floatingPill.Parent = screenGui

local pillCorner = Instance.new("UICorner")
pillCorner.CornerRadius = UDim.new(0, 18)
pillCorner.Parent = floatingPill

local pillStroke = Instance.new("UIStroke")
pillStroke.Color = Color3.fromRGB(0, 210, 255)
pillStroke.Thickness = 1.2
pillStroke.Parent = floatingPill

-- Unread Badge on Pill
local unreadBadge = Instance.new("TextLabel")
unreadBadge.Name = "UnreadBadge"
unreadBadge.Size = UDim2.new(0, 18, 0, 18)
unreadBadge.Position = UDim2.new(1, -12, 0, -6)
unreadBadge.BackgroundColor3 = Color3.fromRGB(255, 75, 95)
unreadBadge.BorderSizePixel = 0
unreadBadge.Text = "0"
unreadBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
unreadBadge.Font = Enum.Font.GothamBold
unreadBadge.TextSize = 10
unreadBadge.Visible = false
unreadBadge.Parent = floatingPill

local badgeCorner = Instance.new("UICorner")
badgeCorner.CornerRadius = UDim.new(1, 0)
badgeCorner.Parent = unreadBadge

-- ==============================================================================
-- Draggable Window Helper
-- ==============================================================================
local function MakeDraggable(dragHandle, targetFrame)
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPos = nil

    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = targetFrame.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            targetFrame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
end

MakeDraggable(headerBar, mainWindow)
MakeDraggable(floatingPill, floatingPill)

-- ==============================================================================
-- Message Bubble Renderer
-- ==============================================================================
local function AddMessageBubble(msgData)
    local bubble = Instance.new("Frame")
    bubble.Name = "Msg_" .. tostring(msgData.id)
    bubble.Size = UDim2.new(1, 0, 0, 0) -- Automatic sizing
    bubble.AutomaticSize = Enum.AutomaticSize.Y
    bubble.BackgroundColor3 = Color3.fromRGB(20, 23, 33)
    bubble.BorderSizePixel = 0
    bubble.LayoutOrder = msgData.id or 0
    bubble.Parent = scrollContainer

    local bCorner = Instance.new("UICorner")
    bCorner.CornerRadius = UDim.new(0, 8)
    bCorner.Parent = bubble

    local bStroke = Instance.new("UIStroke")
    bStroke.Color = Color3.fromRGB(30, 35, 48)
    bStroke.Thickness = 0.8
    bStroke.Parent = bubble

    local isMe = tostring(msgData.userId) == tostring(localPlayer.UserId)
    local isSystem = msgData.system == true

    if isMe then
        bStroke.Color = Color3.fromRGB(0, 180, 230)
    elseif isSystem then
        bStroke.Color = Color3.fromRGB(255, 190, 40)
    end

    -- Avatar Headshot
    local avatar = Instance.new("ImageLabel")
    avatar.Name = "Avatar"
    avatar.Size = UDim2.new(0, 32, 0, 32)
    avatar.Position = UDim2.new(0, 8, 0, 8)
    avatar.BackgroundColor3 = Color3.fromRGB(15, 17, 24)
    avatar.BorderSizePixel = 0
    
    if isSystem then
        avatar.Image = GetLogoImage()
    else
        local uid = tonumber(msgData.userId) or 1
        avatar.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48", uid)
    end
    avatar.ScaleType = Enum.ScaleType.Fit
    avatar.Parent = bubble

    local avCorner = Instance.new("UICorner")
    avCorner.CornerRadius = UDim.new(0, 6)
    avCorner.Parent = avatar

    -- Author info row
    local authorLbl = Instance.new("TextLabel")
    authorLbl.Name = "Author"
    authorLbl.Size = UDim2.new(1, -50, 0, 16)
    authorLbl.Position = UDim2.new(0, 46, 0, 6)
    authorLbl.BackgroundTransparency = 1
    
    local dName = msgData.displayName or msgData.username or "Anonymous"
    local uName = msgData.username or ""
    local timeStr = msgData.time or ""

    if isSystem then
        authorLbl.Text = string.format("<b><font color=\"rgb(255,200,50)\">%s</font></b> • <font color=\"rgb(130,135,150)\">%s</font>", dName, timeStr)
    elseif isMe then
        authorLbl.Text = string.format("<b><font color=\"rgb(0,215,255)\">%s</font></b> <font color=\"rgb(120,125,145)\">(@%s)</font> • <font color=\"rgb(110,115,130)\">%s</font>", dName, uName, timeStr)
    else
        authorLbl.Text = string.format("<b><font color=\"rgb(255,255,255)\">%s</font></b> <font color=\"rgb(130,135,150)\">(@%s)</font> • <font color=\"rgb(110,115,130)\">%s</font>", dName, uName, timeStr)
    end

    authorLbl.RichText = true
    authorLbl.Font = Enum.Font.GothamMedium
    authorLbl.TextSize = 11
    authorLbl.TextXAlignment = Enum.TextXAlignment.Left
    authorLbl.Parent = bubble

    -- Message Body Text (Auto-wrapping)
    local bodyLbl = Instance.new("TextLabel")
    bodyLbl.Name = "Body"
    bodyLbl.Size = UDim2.new(1, -54, 0, 0)
    bodyLbl.Position = UDim2.new(0, 46, 0, 24)
    bodyLbl.AutomaticSize = Enum.AutomaticSize.Y
    bodyLbl.BackgroundTransparency = 1
    bodyLbl.Text = tostring(msgData.message or "")
    bodyLbl.TextColor3 = isSystem and Color3.fromRGB(240, 235, 200) or Color3.fromRGB(220, 225, 235)
    bodyLbl.Font = Enum.Font.Gotham
    bodyLbl.TextSize = 12
    bodyLbl.TextWrapped = true
    bodyLbl.TextXAlignment = Enum.TextXAlignment.Left
    bodyLbl.TextYAlignment = Enum.TextYAlignment.Top
    bodyLbl.Parent = bubble

    -- Extra bottom padding
    local pad = Instance.new("UIPadding")
    pad.PaddingBottom = UDim.new(0, 8)
    pad.Parent = bubble

    -- Trim old messages if container exceeds limit
    local children = scrollContainer:GetChildren()
    local messageCount = 0
    for _, child in ipairs(children) do
        if child:IsA("Frame") and child.Name:sub(1, 4) == "Msg_" then
            messageCount = messageCount + 1
        end
    end
    if messageCount > ChatConfig.MaxDisplayMessages then
        for _, child in ipairs(children) do
            if child:IsA("Frame") and child.Name:sub(1, 4) == "Msg_" then
                child:Destroy()
                break
            end
        end
    end

    -- Auto scroll to bottom
    task.defer(function()
        scrollContainer.CanvasPosition = Vector2.new(0, scrollContainer.AbsoluteCanvasSize.Y)
    end)
end

-- ==============================================================================
-- Polling & Message Synchronization
-- ==============================================================================
local function FetchNewMessages()
    local base = GetWorkingApiUrl()
    local url = string.format("%s/messages?after=%d&limit=50&_t=%d", base, lastMessageId, os.time())
    
    local raw = FetchRaw(url)
    if not raw then return end

    local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if ok and data and data.success and data.messages then
        local hasNew = false
        for _, msg in ipairs(data.messages) do
            local msgId = tonumber(msg.id) or 0
            if msgId > lastMessageId then
                lastMessageId = msgId
                AddMessageBubble(msg)
                hasNew = true
            end
        end

        if hasNew then
            if not isWindowVisible or isMinimized then
                unreadCount = unreadCount + 1
                unreadBadge.Text = tostring(unreadCount)
                unreadBadge.Visible = true
            end

            if ChatConfig.SoundEnabled and hasNew then
                pcall(function()
                    local snd = Instance.new("Sound")
                    snd.SoundId = "rbxassetid://9069609268" -- soft chat pop
                    snd.Volume = 0.4
                    snd.Parent = SoundService
                    snd:Play()
                    game:GetService("Debris"):AddItem(snd, 2)
                end)
            end
        end
    end
end

-- ==============================================================================
-- Send Message Action
-- ==============================================================================
local function SendChatMessage()
    local text = chatInput.Text
    if not text or text:match("^%s*$") then return end

    local now = tick()
    if now - lastSendTime < ChatConfig.CooldownSeconds then
        local waitLeft = string.format("%.1f", ChatConfig.CooldownSeconds - (now - lastSendTime))
        cooldownLbl.Text = "Wait " .. waitLeft .. "s"
        cooldownLbl.TextColor3 = Color3.fromRGB(255, 100, 100)
        task.delay(1, function()
            cooldownLbl.Text = string.format("%d/200", #chatInput.Text)
            cooldownLbl.TextColor3 = Color3.fromRGB(110, 115, 135)
        end)
        return
    end

    lastSendTime = now
    chatInput.Text = ""
    cooldownLbl.Text = "0/200"

    local base = GetWorkingApiUrl()
    local postUrl = string.format("%s/messages", base)

    local payload = {
        userId = tostring(localPlayer.UserId),
        username = tostring(localPlayer.Name),
        displayName = tostring(localPlayer.DisplayName),
        message = text:sub(1, 200)
    }

    task.spawn(function()
        local body, status = PostRaw(postUrl, HttpService:JSONEncode(payload))
        if status == 201 or status == 200 then
            FetchNewMessages()
        else
            -- If rate limited or failed, log feedback
            pcall(function()
                local errData = HttpService:JSONDecode(body)
                if errData and errData.error then
                    cooldownLbl.Text = errData.error:sub(1, 20)
                end
            end)
        end
    end)
end

-- ==============================================================================
-- Interactive Event Handlers
-- ==============================================================================
sendBtn.MouseButton1Click:Connect(SendChatMessage)

chatInput.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        SendChatMessage()
    end
end)

chatInput:GetPropertyChangedSignal("Text"):Connect(function()
    local len = #chatInput.Text
    if len > 200 then
        chatInput.Text = chatInput.Text:sub(1, 200)
        len = 200
    end
    cooldownLbl.Text = string.format("%d/200", len)
end)

-- Minimize action
local function ToggleMinimize()
    isMinimized = not isMinimized
    if isMinimized then
        mainWindow.Visible = false
        floatingPill.Visible = true
    else
        mainWindow.Visible = true
        floatingPill.Visible = false
        unreadCount = 0
        unreadBadge.Visible = false
    end
end

minBtn.MouseButton1Click:Connect(ToggleMinimize)
floatingPill.MouseButton1Click:Connect(ToggleMinimize)

-- Close action
local function ToggleClose()
    isWindowVisible = not isWindowVisible
    mainWindow.Visible = isWindowVisible
    floatingPill.Visible = not isWindowVisible
    if isWindowVisible then
        unreadCount = 0
        unreadBadge.Visible = false
    end
end

closeBtn.MouseButton1Click:Connect(ToggleClose)

-- Toggle hotkey (RightShift)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == ChatConfig.ToggleKey then
        ToggleClose()
    end
end)

-- Button Hover Tweens
local function AddHoverEffect(btn, normalColor, hoverColor)
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), { TextColor3 = hoverColor }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), { TextColor3 = normalColor }):Play()
    end)
end

AddHoverEffect(closeBtn, Color3.fromRGB(160, 165, 185), Color3.fromRGB(255, 255, 255))
AddHoverEffect(minBtn, Color3.fromRGB(160, 165, 185), Color3.fromRGB(255, 255, 255))

-- ==============================================================================
-- Background Polling Loop
-- ==============================================================================
task.spawn(function()
    -- Immediate initial fetch
    FetchNewMessages()

    while screenGui and screenGui.Parent do
        task.wait(ChatConfig.PollInterval)
        pcall(FetchNewMessages)
    end
end)

print("[Serenity Hub] 💬 Global Chat loaded successfully! Press RightShift to toggle.")
