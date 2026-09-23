-- ==============================================================================
-- 💬 SERENITY HUB - GLOBAL CHAT SYSTEM (CUSTOM DISCORD / SENA STYLE GUI)
-- ==============================================================================
-- Matches the exact dark Discord-style theme:
-- - Channels & Rooms bar (General, Indonesian, Philippines, Vietnam, Brazilian)
-- - Live Network status + real-time online counter (🟢 [count] online)
-- - Circular player headshots, username, current Roblox Game tag & timestamp
-- - Auto-highlighted @mentions
-- - Search filter bar + minimize / close controls
-- - Clean white 'Send' pill button & @ mention insert helper
-- ==============================================================================

local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

-- Prevent duplicate instances
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
    StatsUrls = {
        "https://serenityhub.site/api/stats",
        "https://serenity-admin-5pra.onrender.com/api/stats",
        "http://localhost:3000/api/stats"
    },
    PollInterval = 2.5,
    CooldownSeconds = 1.5,
    DefaultRoom = "general",
    ToggleKey = Enum.KeyCode.RightShift
}

-- Rooms list from reference UI
local RoomsList = {
    { id = "general", name = "General", hasDot = false },
    { id = "indonesian", name = "Indonesian", hasDot = true },
    { id = "philippines", name = "Philippines", hasDot = true },
    { id = "vietnam", name = "Vietnam", hasDot = true },
    { id = "brazilian", name = "Brazilian", hasDot = true }
}

-- State
local currentRoom = "general"
local lastMessageId = 0
local activeBaseUrl = nil
local lastSendTime = 0
local isWindowVisible = true
local isMinimized = false
local unreadCount = 0
local currentGameName = "Serenity Game"
local searchQuery = ""
local allLoadedMessages = {} -- Cache for searching & filtering

-- Cache current Roblox Game Name
task.spawn(function()
    local ok, info = pcall(function()
        return MarketplaceService:GetProductInfo(game.PlaceId)
    end)
    if ok and info and info.Name and info.Name ~= "" then
        currentGameName = info.Name
    end
end)

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
    activeBaseUrl = ChatConfig.ApiUrls[1]
    return activeBaseUrl
end

-- ==============================================================================
-- GUI Construction (Sena / Discord Exact Style)
-- ==============================================================================
local targetParent = GetGuiParent()
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SerenityGlobalChatGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = targetParent
_G.SerenityGlobalChatGui = screenGui

-- Main Chat Window Frame
local mainWindow = Instance.new("Frame")
mainWindow.Name = "MainWindow"
mainWindow.Size = UDim2.new(0, 560, 0, 480)
mainWindow.Position = UDim2.new(0.5, -280, 0.5, -240)
mainWindow.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
mainWindow.BorderSizePixel = 0
mainWindow.ClipsDescendants = true
mainWindow.Parent = screenGui

local winCorner = Instance.new("UICorner")
winCorner.CornerRadius = UDim.new(0, 10)
winCorner.Parent = mainWindow

local winStroke = Instance.new("UIStroke")
winStroke.Color = Color3.fromRGB(32, 36, 46)
winStroke.Thickness = 1
winStroke.Parent = mainWindow

-- ==============================================================================
-- 1. Top Header Bar (Global Chat | Search | Controls)
-- ==============================================================================
local headerBar = Instance.new("Frame")
headerBar.Name = "HeaderBar"
headerBar.Size = UDim2.new(1, 0, 0, 54)
headerBar.Position = UDim2.new(0, 0, 0, 0)
headerBar.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
headerBar.BorderSizePixel = 0
headerBar.Parent = mainWindow

-- Title Text
local titleLbl = Instance.new("TextLabel")
titleLbl.Name = "TitleLbl"
titleLbl.Size = UDim2.new(0, 220, 0, 20)
titleLbl.Position = UDim2.new(0, 16, 0, 10)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "Global Chat"
titleLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 15
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Parent = headerBar

-- Subtitle Text
local subtitleLbl = Instance.new("TextLabel")
subtitleLbl.Name = "SubtitleLbl"
subtitleLbl.Size = UDim2.new(0, 260, 0, 14)
subtitleLbl.Position = UDim2.new(0, 16, 0, 30)
subtitleLbl.BackgroundTransparency = 1
subtitleLbl.Text = "Talk with every Serenity user across servers"
subtitleLbl.TextColor3 = Color3.fromRGB(120, 125, 140)
subtitleLbl.Font = Enum.Font.Gotham
subtitleLbl.TextSize = 11
subtitleLbl.TextXAlignment = Enum.TextXAlignment.Left
subtitleLbl.Parent = headerBar

-- Right Controls Container (Search + - + X)
local rightControls = Instance.new("Frame")
rightControls.Name = "RightControls"
rightControls.Size = UDim2.new(0, 240, 0, 36)
rightControls.Position = UDim2.new(1, -246, 0, 10)
rightControls.BackgroundTransparency = 1
rightControls.Parent = headerBar

-- Search Input Bar
local searchBoxFrame = Instance.new("Frame")
searchBoxFrame.Name = "SearchBoxFrame"
searchBoxFrame.Size = UDim2.new(0, 160, 0, 32)
searchBoxFrame.Position = UDim2.new(0, 0, 0, 2)
searchBoxFrame.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
searchBoxFrame.BorderSizePixel = 0
searchBoxFrame.Parent = rightControls

local searchCorner = Instance.new("UICorner")
searchCorner.CornerRadius = UDim.new(0, 6)
searchCorner.Parent = searchBoxFrame

local searchStroke = Instance.new("UIStroke")
searchStroke.Color = Color3.fromRGB(38, 42, 54)
searchStroke.Thickness = 0.8
searchStroke.Parent = searchBoxFrame

local searchIcon = Instance.new("TextLabel")
searchIcon.Name = "SearchIcon"
searchIcon.Size = UDim2.new(0, 20, 1, 0)
searchIcon.Position = UDim2.new(0, 8, 0, 0)
searchIcon.BackgroundTransparency = 1
searchIcon.Text = "🔍"
searchIcon.TextColor3 = Color3.fromRGB(130, 135, 150)
searchIcon.Font = Enum.Font.Gotham
searchIcon.TextSize = 11
searchIcon.Parent = searchBoxFrame

local searchInput = Instance.new("TextBox")
searchInput.Name = "SearchInput"
searchInput.Size = UDim2.new(1, -34, 1, 0)
searchInput.Position = UDim2.new(0, 28, 0, 0)
searchInput.BackgroundTransparency = 1
searchInput.PlaceholderText = "Search"
searchInput.PlaceholderColor3 = Color3.fromRGB(130, 135, 150)
searchInput.Text = ""
searchInput.TextColor3 = Color3.fromRGB(230, 235, 245)
searchInput.Font = Enum.Font.GothamMedium
searchInput.TextSize = 12
searchInput.TextXAlignment = Enum.TextXAlignment.Left
searchInput.ClearTextOnFocus = false
searchInput.Parent = searchBoxFrame

-- Window Minimize Button ("—")
local minBtn = Instance.new("TextButton")
minBtn.Name = "MinBtn"
minBtn.Size = UDim2.new(0, 28, 0, 28)
minBtn.Position = UDim2.new(1, -66, 0, 4)
minBtn.BackgroundTransparency = 1
minBtn.Text = "—"
minBtn.TextColor3 = Color3.fromRGB(150, 155, 170)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 13
minBtn.Parent = rightControls

-- Window Close Button ("X")
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseBtn"
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -34, 0, 4)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(150, 155, 170)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.Parent = rightControls

-- ==============================================================================
-- 2. Sub-Header ("Live Network" | Rooms | 🟢 [count] online)
-- ==============================================================================
local subHeader = Instance.new("Frame")
subHeader.Name = "SubHeader"
subHeader.Size = UDim2.new(1, -32, 0, 26)
subHeader.Position = UDim2.new(0, 16, 0, 58)
subHeader.BackgroundTransparency = 1
subHeader.Parent = mainWindow

local liveNetLbl = Instance.new("TextLabel")
liveNetLbl.Name = "LiveNetLbl"
liveNetLbl.Size = UDim2.new(0, 95, 1, 0)
liveNetLbl.Position = UDim2.new(0, 0, 0, 0)
liveNetLbl.BackgroundTransparency = 1
liveNetLbl.Text = "Live Network"
liveNetLbl.TextColor3 = Color3.fromRGB(240, 242, 248)
liveNetLbl.Font = Enum.Font.GothamBold
liveNetLbl.TextSize = 12
liveNetLbl.TextXAlignment = Enum.TextXAlignment.Left
liveNetLbl.Parent = subHeader

-- "Rooms" Pill
local roomsPill = Instance.new("Frame")
roomsPill.Name = "RoomsPill"
roomsPill.Size = UDim2.new(0, 68, 0, 24)
roomsPill.Position = UDim2.new(0, 108, 0, 1)
roomsPill.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
roomsPill.BorderSizePixel = 0
roomsPill.Parent = subHeader

local rCorner = Instance.new("UICorner")
rCorner.CornerRadius = UDim.new(0, 6)
rCorner.Parent = roomsPill

local rStroke = Instance.new("UIStroke")
rStroke.Color = Color3.fromRGB(40, 44, 58)
rStroke.Thickness = 0.8
rStroke.Parent = roomsPill

local rText = Instance.new("TextLabel")
rText.Name = "Label"
rText.Size = UDim2.new(1, 0, 1, 0)
rText.BackgroundTransparency = 1
rText.Text = "Rooms"
rText.TextColor3 = Color3.fromRGB(220, 225, 235)
rText.Font = Enum.Font.GothamMedium
rText.TextSize = 11
rText.Parent = roomsPill

-- "🔴 Hidden" Pill
local hiddenPill = Instance.new("TextButton")
hiddenPill.Name = "HiddenPill"
hiddenPill.Size = UDim2.new(0, 74, 0, 24)
hiddenPill.Position = UDim2.new(0, 184, 0, 1)
hiddenPill.BackgroundColor3 = Color3.fromRGB(20, 23, 31)
hiddenPill.BorderSizePixel = 0
hiddenPill.Text = "• Hidden"
hiddenPill.TextColor3 = Color3.fromRGB(150, 155, 170)
hiddenPill.Font = Enum.Font.GothamMedium
hiddenPill.TextSize = 11
hiddenPill.Parent = subHeader

local hCorner = Instance.new("UICorner")
hCorner.CornerRadius = UDim.new(0, 6)
hCorner.Parent = hiddenPill

local hStroke = Instance.new("UIStroke")
hStroke.Color = Color3.fromRGB(36, 40, 52)
hStroke.Thickness = 0.8
hStroke.Parent = hiddenPill

local hDot = Instance.new("Frame")
hDot.Name = "Dot"
hDot.Size = UDim2.new(0, 6, 0, 6)
hDot.Position = UDim2.new(0, 9, 0.5, -3)
hDot.BackgroundColor3 = Color3.fromRGB(235, 75, 75)
hDot.BorderSizePixel = 0
hDot.Parent = hiddenPill

local hdCorner = Instance.new("UICorner")
hdCorner.CornerRadius = UDim.new(1, 0)
hdCorner.Parent = hDot

-- Right: "🟢 8052 online"
local onlineStatusFrame = Instance.new("Frame")
onlineStatusFrame.Name = "OnlineStatusFrame"
onlineStatusFrame.Size = UDim2.new(0, 110, 1, 0)
onlineStatusFrame.Position = UDim2.new(1, -110, 0, 0)
onlineStatusFrame.BackgroundTransparency = 1
onlineStatusFrame.Parent = subHeader

local onlineDot = Instance.new("Frame")
onlineDot.Name = "OnlineDot"
onlineDot.Size = UDim2.new(0, 6, 0, 6)
onlineDot.Position = UDim2.new(1, -86, 0.5, -3)
onlineDot.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
onlineDot.BorderSizePixel = 0
onlineDot.Parent = onlineStatusFrame

local odCorner = Instance.new("UICorner")
odCorner.CornerRadius = UDim.new(1, 0)
odCorner.Parent = onlineDot

local onlineLbl = Instance.new("TextLabel")
onlineLbl.Name = "OnlineLbl"
onlineLbl.Size = UDim2.new(1, -16, 1, 0)
onlineLbl.Position = UDim2.new(0, 14, 0, 0)
onlineLbl.BackgroundTransparency = 1
onlineLbl.Text = "8052 online"
onlineLbl.TextColor3 = Color3.fromRGB(160, 168, 185)
onlineLbl.Font = Enum.Font.GothamMedium
onlineLbl.TextSize = 11
onlineLbl.TextXAlignment = Enum.TextXAlignment.Right
onlineLbl.Parent = onlineStatusFrame

-- ==============================================================================
-- 3. Room Buttons Navigation Row (< [General] [Indonesian] ... >)
-- ==============================================================================
local roomsContainer = Instance.new("Frame")
roomsContainer.Name = "RoomsContainer"
roomsContainer.Size = UDim2.new(1, -32, 0, 36)
roomsContainer.Position = UDim2.new(0, 16, 0, 90)
roomsContainer.BackgroundTransparency = 1
roomsContainer.Parent = mainWindow

-- Left arrow button
local leftArrowBtn = Instance.new("TextButton")
leftArrowBtn.Name = "LeftArrow"
leftArrowBtn.Size = UDim2.new(0, 24, 0, 30)
leftArrowBtn.Position = UDim2.new(0, 0, 0, 3)
leftArrowBtn.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
leftArrowBtn.BorderSizePixel = 0
leftArrowBtn.Text = "‹"
leftArrowBtn.TextColor3 = Color3.fromRGB(160, 165, 180)
leftArrowBtn.Font = Enum.Font.GothamBold
leftArrowBtn.TextSize = 14
leftArrowBtn.Parent = roomsContainer

local laCorner = Instance.new("UICorner")
laCorner.CornerRadius = UDim.new(0, 6)
laCorner.Parent = leftArrowBtn

-- Right arrow button
local rightArrowBtn = Instance.new("TextButton")
rightArrowBtn.Name = "RightArrow"
rightArrowBtn.Size = UDim2.new(0, 24, 0, 30)
rightArrowBtn.Position = UDim2.new(1, -24, 0, 3)
rightArrowBtn.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
rightArrowBtn.BorderSizePixel = 0
rightArrowBtn.Text = "›"
rightArrowBtn.TextColor3 = Color3.fromRGB(160, 165, 180)
rightArrowBtn.Font = Enum.Font.GothamBold
rightArrowBtn.TextSize = 14
rightArrowBtn.Parent = roomsContainer

local raCorner = Instance.new("UICorner")
raCorner.CornerRadius = UDim.new(0, 6)
raCorner.Parent = rightArrowBtn

-- Scrollable room pills frame
local roomScroll = Instance.new("ScrollingFrame")
roomScroll.Name = "RoomScroll"
roomScroll.Size = UDim2.new(1, -60, 1, 0)
roomScroll.Position = UDim2.new(0, 30, 0, 0)
roomScroll.BackgroundTransparency = 1
roomScroll.BorderSizePixel = 0
roomScroll.ScrollBarThickness = 0
roomScroll.CanvasSize = UDim2.new(0, 480, 0, 0)
roomScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
roomScroll.ScrollingDirection = Enum.ScrollingDirection.X
roomScroll.Parent = roomsContainer

local roomListLayout = Instance.new("UIListLayout")
roomListLayout.FillDirection = Enum.FillDirection.Horizontal
roomListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
roomListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
roomListLayout.Padding = UDim.new(0, 8)
roomListLayout.Parent = roomScroll

-- Arrow scroll handlers
leftArrowBtn.MouseButton1Click:Connect(function()
    roomScroll.CanvasPosition = Vector2.new(math.max(0, roomScroll.CanvasPosition.X - 100), 0)
end)
rightArrowBtn.MouseButton1Click:Connect(function()
    roomScroll.CanvasPosition = Vector2.new(roomScroll.CanvasPosition.X + 100, 0)
end)

local roomButtons = {}

local function UpdateRoomStyles()
    for _, item in ipairs(roomButtons) do
        local isSelected = item.id == currentRoom
        if isSelected then
            item.btn.BackgroundColor3 = Color3.fromRGB(38, 42, 54)
            item.label.TextColor3 = Color3.fromRGB(255, 255, 255)
            item.stroke.Color = Color3.fromRGB(56, 62, 80)
        else
            item.btn.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
            item.label.TextColor3 = Color3.fromRGB(160, 165, 180)
            item.stroke.Color = Color3.fromRGB(32, 36, 48)
        end
    end
end

-- ==============================================================================
-- 4. Messages Feed ScrollingFrame
-- ==============================================================================
local messagesScroll = Instance.new("ScrollingFrame")
messagesScroll.Name = "MessagesScroll"
messagesScroll.Size = UDim2.new(1, -32, 1, -196)
messagesScroll.Position = UDim2.new(0, 16, 0, 134)
messagesScroll.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
messagesScroll.BorderSizePixel = 0
messagesScroll.ScrollBarThickness = 4
messagesScroll.ScrollBarImageColor3 = Color3.fromRGB(35, 40, 54)
messagesScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
messagesScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
messagesScroll.BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
messagesScroll.TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
messagesScroll.Parent = mainWindow

local msgListLayout = Instance.new("UIListLayout")
msgListLayout.SortOrder = Enum.SortOrder.LayoutOrder
msgListLayout.Padding = UDim.new(0, 14)
msgListLayout.Parent = messagesScroll

local msgPadding = Instance.new("UIPadding")
msgPadding.PaddingTop = UDim.new(0, 6)
msgPadding.PaddingBottom = UDim.new(0, 10)
msgPadding.PaddingLeft = UDim.new(0, 4)
msgPadding.PaddingRight = UDim.new(0, 6)
msgPadding.Parent = messagesScroll

-- ==============================================================================
-- 5. Bottom Input Bar Row (TextBox | @ Button | Send Button)
-- ==============================================================================
local bottomContainer = Instance.new("Frame")
bottomContainer.Name = "BottomContainer"
bottomContainer.Size = UDim2.new(1, -32, 0, 44)
bottomContainer.Position = UDim2.new(0, 16, 1, -54)
bottomContainer.BackgroundTransparency = 1
bottomContainer.Parent = mainWindow

-- Text Input Box
local chatInput = Instance.new("TextBox")
chatInput.Name = "ChatInput"
chatInput.Size = UDim2.new(1, -125, 0, 38)
chatInput.Position = UDim2.new(0, 0, 0, 3)
chatInput.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
chatInput.BorderSizePixel = 0
chatInput.PlaceholderText = "Type a message..."
chatInput.PlaceholderColor3 = Color3.fromRGB(100, 108, 125)
chatInput.Text = ""
chatInput.TextColor3 = Color3.fromRGB(240, 245, 255)
chatInput.Font = Enum.Font.GothamMedium
chatInput.TextSize = 12
chatInput.TextXAlignment = Enum.TextXAlignment.Left
chatInput.ClearTextOnFocus = false
chatInput.Parent = bottomContainer

local inputCorner = Instance.new("UICorner")
inputCorner.CornerRadius = UDim.new(0, 8)
inputCorner.Parent = chatInput

local inputStroke = Instance.new("UIStroke")
inputStroke.Color = Color3.fromRGB(36, 40, 54)
inputStroke.Thickness = 0.8
inputStroke.Parent = chatInput

local inputPadding = Instance.new("UIPadding")
inputPadding.PaddingLeft = UDim.new(0, 14)
inputPadding.PaddingRight = UDim.new(0, 10)
inputPadding.Parent = chatInput

-- Mention "@" Button
local mentionBtn = Instance.new("TextButton")
mentionBtn.Name = "MentionBtn"
mentionBtn.Size = UDim2.new(0, 36, 0, 38)
mentionBtn.Position = UDim2.new(1, -115, 0, 3)
mentionBtn.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
mentionBtn.BorderSizePixel = 0
mentionBtn.Text = "@"
mentionBtn.TextColor3 = Color3.fromRGB(170, 175, 190)
mentionBtn.Font = Enum.Font.GothamBold
mentionBtn.TextSize = 14
mentionBtn.Parent = bottomContainer

local mCorner = Instance.new("UICorner")
mCorner.CornerRadius = UDim.new(0, 8)
mCorner.Parent = mentionBtn

local mStroke = Instance.new("UIStroke")
mStroke.Color = Color3.fromRGB(36, 40, 54)
mStroke.Thickness = 0.8
mStroke.Parent = mentionBtn

mentionBtn.MouseButton1Click:Connect(function()
    chatInput.Text = chatInput.Text .. "@"
    chatInput:CaptureFocus()
end)

-- Send Button (Pure White Pill with Dark Text)
local sendBtn = Instance.new("TextButton")
sendBtn.Name = "SendBtn"
sendBtn.Size = UDim2.new(0, 68, 0, 38)
sendBtn.Position = UDim2.new(1, -70, 0, 3)
sendBtn.BackgroundColor3 = Color3.fromRGB(246, 248, 252)
sendBtn.BorderSizePixel = 0
sendBtn.Text = "Send"
sendBtn.TextColor3 = Color3.fromRGB(15, 17, 24)
sendBtn.Font = Enum.Font.GothamBold
sendBtn.TextSize = 12
sendBtn.Parent = bottomContainer

local sendCorner = Instance.new("UICorner")
sendCorner.CornerRadius = UDim.new(0, 8)
sendCorner.Parent = sendBtn

-- ==============================================================================
-- Floating Mini-Pill (When minimized or closed)
-- ==============================================================================
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

local fpCorner = Instance.new("UICorner")
fpCorner.CornerRadius = UDim.new(0, 18)
fpCorner.Parent = floatingPill

local fpStroke = Instance.new("UIStroke")
fpStroke.Color = Color3.fromRGB(0, 210, 255)
fpStroke.Thickness = 1.2
fpStroke.Parent = floatingPill

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

local ubCorner = Instance.new("UICorner")
ubCorner.CornerRadius = UDim.new(1, 0)
ubCorner.Parent = unreadBadge

-- ==============================================================================
-- Populate Room Pills
-- ==============================================================================
local function RenderRoomPills()
    for _, child in ipairs(roomScroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    roomButtons = {}

    for _, rData in ipairs(RoomsList) do
        local rBtn = Instance.new("TextButton")
        rBtn.Name = "Room_" .. rData.id
        rBtn.Size = UDim2.new(0, 0, 0, 30)
        rBtn.AutomaticSize = Enum.AutomaticSize.X
        rBtn.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
        rBtn.BorderSizePixel = 0
        rBtn.Text = ""
        rBtn.AutoButtonColor = false
        rBtn.Parent = roomScroll

        local rbCorner = Instance.new("UICorner")
        rbCorner.CornerRadius = UDim.new(0, 6)
        rbCorner.Parent = rBtn

        local rbStroke = Instance.new("UIStroke")
        rbStroke.Color = Color3.fromRGB(32, 36, 48)
        rbStroke.Thickness = 0.8
        rbStroke.Parent = rBtn

        local rbPad = Instance.new("UIPadding")
        rbPad.PaddingLeft = UDim.new(0, 14)
        rbPad.PaddingRight = UDim.new(0, rData.hasDot and 20 or 14)
        rbPad.Parent = rBtn

        local rbLbl = Instance.new("TextLabel")
        rbLbl.Name = "Text"
        rbLbl.Size = UDim2.new(0, 0, 1, 0)
        rbLbl.AutomaticSize = Enum.AutomaticSize.X
        rbLbl.BackgroundTransparency = 1
        rbLbl.Text = rData.name
        rbLbl.TextColor3 = Color3.fromRGB(160, 165, 180)
        rbLbl.Font = Enum.Font.GothamMedium
        rbLbl.TextSize = 11
        rbLbl.Parent = rBtn

        if rData.hasDot then
            local rDot = Instance.new("Frame")
            rDot.Name = "Dot"
            rDot.Size = UDim2.new(0, 6, 0, 6)
            rDot.Position = UDim2.new(1, 8, 0.5, -3)
            rDot.BackgroundColor3 = Color3.fromRGB(235, 75, 75)
            rDot.BorderSizePixel = 0
            rDot.Parent = rbLbl

            local rdCorner = Instance.new("UICorner")
            rdCorner.CornerRadius = UDim.new(1, 0)
            rdCorner.Parent = rDot
        end

        rBtn.MouseButton1Click:Connect(function()
            if currentRoom ~= rData.id then
                currentRoom = rData.id
                UpdateRoomStyles()
                FilterAndRenderMessages()
            end
        end)

        table.insert(roomButtons, {
            id = rData.id,
            btn = rBtn,
            label = rbLbl,
            stroke = rbStroke
        })
    end

    UpdateRoomStyles()
end

RenderRoomPills()

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
-- Format Mentions (@username) in Vibrant Cyan/Blue
-- ==============================================================================
local function FormatMentions(rawText)
    if not rawText then return "" end
    -- Escape XML special characters first
    local safe = rawText:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    -- Format @mentions
    safe = safe:gsub("(@[%w_]+)", "<font color=\"rgb(75,160,255)\">%1</font>")
    return safe
end

-- ==============================================================================
-- Render Individual Message Item (Exact Sena Style)
-- ==============================================================================
local function CreateMessageRow(msg)
    local row = Instance.new("Frame")
    row.Name = "MsgRow_" .. tostring(msg.id)
    row.Size = UDim2.new(1, 0, 0, 0)
    row.AutomaticSize = Enum.AutomaticSize.Y
    row.BackgroundTransparency = 1
    row.BorderSizePixel = 0
    row.LayoutOrder = msg.id or 0
    row.Parent = messagesScroll

    -- 1. Circular Avatar
    local avatar = Instance.new("ImageLabel")
    avatar.Name = "Avatar"
    avatar.Size = UDim2.new(0, 36, 0, 36)
    avatar.Position = UDim2.new(0, 0, 0, 2)
    avatar.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
    avatar.BorderSizePixel = 0
    
    local uid = tonumber(msg.userId) or 1
    avatar.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48", uid)
    avatar.ScaleType = Enum.ScaleType.Fit
    avatar.Parent = row

    local avCorner = Instance.new("UICorner")
    avCorner.CornerRadius = UDim.new(1, 0) -- Pure circle
    avCorner.Parent = avatar

    -- 2. Header Line (Username | Game Name · Time)
    local headerLine = Instance.new("TextLabel")
    headerLine.Name = "HeaderLine"
    headerLine.Size = UDim2.new(1, -50, 0, 16)
    headerLine.Position = UDim2.new(0, 48, 0, 0)
    headerLine.BackgroundTransparency = 1
    
    local uName = tostring(msg.username or "Anonymous")
    -- Subtle censor if desired or show real username
    local gameTag = tostring(msg.gameName or "Steal An Egg")
    local timeStr = tostring(msg.time or "11:01")

    -- Assign aesthetic pastel colors to different users
    local nameColors = {
        Color3.fromRGB(115, 235, 175), -- mint green
        Color3.fromRGB(255, 155, 195), -- soft pink
        Color3.fromRGB(145, 215, 255), -- light cyan
        Color3.fromRGB(255, 215, 125), -- soft amber
        Color3.fromRGB(195, 165, 255)  -- soft violet
    }
    local colorIdx = ((tonumber(msg.userId) or #uName) % #nameColors) + 1
    local nameColor = nameColors[colorIdx]

    headerLine.RichText = true
    headerLine.Text = string.format(
        "<font color=\"rgb(%d,%d,%d)\"><b>%s</b></font>  <font color=\"rgb(130,138,155)\">%s  ·  %s</font>",
        nameColor.R * 255, nameColor.G * 255, nameColor.B * 255,
        uName,
        gameTag,
        timeStr
    )
    headerLine.Font = Enum.Font.GothamMedium
    headerLine.TextSize = 12
    headerLine.TextXAlignment = Enum.TextXAlignment.Left
    headerLine.Parent = row

    -- 3. Message Body
    local msgBody = Instance.new("TextLabel")
    msgBody.Name = "MsgBody"
    msgBody.Size = UDim2.new(1, -50, 0, 0)
    msgBody.Position = UDim2.new(0, 48, 0, 18)
    msgBody.AutomaticSize = Enum.AutomaticSize.Y
    msgBody.BackgroundTransparency = 1
    msgBody.RichText = true
    msgBody.Text = FormatMentions(tostring(msg.message or ""))
    msgBody.TextColor3 = Color3.fromRGB(225, 230, 240)
    msgBody.Font = Enum.Font.GothamMedium
    msgBody.TextSize = 12
    msgBody.TextWrapped = true
    msgBody.TextXAlignment = Enum.TextXAlignment.Left
    msgBody.TextYAlignment = Enum.TextYAlignment.Top
    msgBody.Parent = row

    local pad = Instance.new("UIPadding")
    pad.PaddingBottom = UDim.new(0, 4)
    pad.Parent = row
end

-- ==============================================================================
-- Filter & Render Message Feed
-- ==============================================================================
function FilterAndRenderMessages()
    for _, child in ipairs(messagesScroll:GetChildren()) do
        if child:IsA("Frame") and child.Name:sub(1, 7) == "MsgRow_" then
            child:Destroy()
        end
    end

    local qLower = searchQuery:lower()

    for _, msg in ipairs(allLoadedMessages) do
        local roomMatch = (currentRoom == "all") or (not msg.room or msg.room:lower() == currentRoom:lower())
        local searchMatch = (qLower == "") 
            or (msg.message and msg.message:lower():find(qLower, 1, true))
            or (msg.username and msg.username:lower():find(qLower, 1, true))
            or (msg.gameName and msg.gameName:lower():find(qLower, 1, true))

        if roomMatch and searchMatch then
            CreateMessageRow(msg)
        end
    end

    task.defer(function()
        messagesScroll.CanvasPosition = Vector2.new(0, messagesScroll.AbsoluteCanvasSize.Y)
    end)
end

-- Search input listener
searchInput:GetPropertyChangedSignal("Text"):Connect(function()
    searchQuery = searchInput.Text
    FilterAndRenderMessages()
end)

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
                table.insert(allLoadedMessages, msg)
                hasNew = true
            end
        end

        if hasNew then
            FilterAndRenderMessages()

            if not isWindowVisible or isMinimized then
                unreadCount = unreadCount + 1
                unreadBadge.Text = tostring(unreadCount)
                unreadBadge.Visible = true
            end

            pcall(function()
                local snd = Instance.new("Sound")
                snd.SoundId = "rbxassetid://9069609268" -- clean pop
                snd.Volume = 0.35
                snd.Parent = SoundService
                snd:Play()
                game:GetService("Debris"):AddItem(snd, 2)
            end)
        end
    end
end

-- Fetch live online user count
local function FetchOnlineCounter()
    for _, statsUrl in ipairs(ChatConfig.StatsUrls) do
        local raw = FetchRaw(statsUrl .. "?_t=" .. os.time())
        if raw then
            local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
            if ok and data and data.activeNow ~= nil then
                local num = tonumber(data.activeNow) or 0
                onlineLbl.Text = string.format("%d online", num)
                return
            end
        end
    end
end

-- ==============================================================================
-- Send Chat Message
-- ==============================================================================
local function SendChatMessage()
    local text = chatInput.Text
    if not text or text:match("^%s*$") then return end

    local now = tick()
    if now - lastSendTime < ChatConfig.CooldownSeconds then
        return
    end

    lastSendTime = now
    chatInput.Text = ""

    local base = GetWorkingApiUrl()
    local postUrl = string.format("%s/messages", base)

    local payload = {
        userId = tostring(localPlayer.UserId),
        username = tostring(localPlayer.Name),
        displayName = tostring(localPlayer.DisplayName),
        gameName = currentGameName,
        room = currentRoom,
        message = text:sub(1, 200)
    }

    task.spawn(function()
        local body, status = PostRaw(postUrl, HttpService:JSONEncode(payload))
        if status == 201 or status == 200 then
            FetchNewMessages()
        end
    end)
end

sendBtn.MouseButton1Click:Connect(SendChatMessage)

chatInput.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        SendChatMessage()
    end
end)

-- Minimize & Close Handlers
local function ToggleMinimize()
    isMinimized = not isMinimized
    mainWindow.Visible = not isMinimized
    floatingPill.Visible = isMinimized
    if not isMinimized then
        unreadCount = 0
        unreadBadge.Visible = false
    end
end

minBtn.MouseButton1Click:Connect(ToggleMinimize)
floatingPill.MouseButton1Click:Connect(ToggleMinimize)

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

AddHoverEffect(closeBtn, Color3.fromRGB(150, 155, 170), Color3.fromRGB(255, 255, 255))
AddHoverEffect(minBtn, Color3.fromRGB(150, 155, 170), Color3.fromRGB(255, 255, 255))

-- ==============================================================================
-- Background Loops
-- ==============================================================================
task.spawn(function()
    FetchOnlineCounter()
    FetchNewMessages()

    while screenGui and screenGui.Parent do
        task.wait(ChatConfig.PollInterval)
        pcall(FetchNewMessages)
    end
end)

task.spawn(function()
    while screenGui and screenGui.Parent do
        task.wait(15)
        pcall(FetchOnlineCounter)
    end
end)

print("[Serenity Hub] 💬 Custom Discord-style Global Chat loaded successfully! Press RightShift to toggle.")
