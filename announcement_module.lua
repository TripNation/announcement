-- ==============================================================================
-- 📢 LIVE ANNOUNCEMENT SYSTEM FOR ROBLOX HUBS
-- ==============================================================================
-- Works with any script executor (Synapse, Wave, KRNL, Fluxus, Delta, Solara, etc.)
-- Polls your announcement API and displays an animated card banner when active.
-- Automatically prevents duplicate popups and handles clean dismiss animations.
-- ==============================================================================

local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local AnnouncementConfig = {
    -- Change or add your website/API domain:
    ApiUrls = {
        "https://serenityhub.site/api/announcements/latest",
        "https://www.serenityhub.site/api/announcements/latest",
        "https://serenity-admin-5pra.onrender.com/api/announcements/latest",
        "http://localhost:3000/api/announcements/latest"
    },
    HubName = "Serenity",            -- Shown in the popup header (e.g. "Serenity Announcement")
    PollInterval = 2,                 -- ⚡ Checks every 2 seconds for near-instant delivery!
    DebugMode = false                 -- Set to true to see console logs in executor
}

-- Global cache to prevent showing the same announcement multiple times in a game session
_G.HubSeenAnnouncements = _G.HubSeenAnnouncements or {}
local activePopup = nil

-- Universal HTTP GET helper across all major Roblox executors
local function FetchRaw(url)
    local reqFn = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    
    -- 1. Try executor custom request API
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

    -- 2. Try standard game:HttpGet
    if game.HttpGet then
        local ok, body = pcall(function()
            return game:HttpGet(url)
        end)
        if ok and body and body ~= "" and body ~= "null" then
            return body
        end
    end

    -- 3. Try HttpService:GetAsync
    if HttpService and HttpService.GetAsync then
        local ok, body = pcall(function()
            return HttpService:GetAsync(url)
        end)
        if ok and body and body ~= "" and body ~= "null" then
            return body
        end
    end

    return nil
end

-- Fetch latest announcement from your API endpoints with cache buster
local function FetchLatestAnnouncement()
    local timestamp = tostring(math.floor(tick() * 1000))
    for _, baseUrl in ipairs(AnnouncementConfig.ApiUrls) do
        local url = baseUrl .. "?_t=" .. timestamp
        local raw = FetchRaw(url)
        if raw then
            local decodeOk, data = pcall(function()
                return HttpService:JSONDecode(raw)
            end)
            if decodeOk and type(data) == "table" and data.id and data.active then
                return data
            end
        end
    end
    return nil
end

-- Custom Serenity SH Logo loader (supports getcustomasset from github / localhost / domain)
local cachedLogoAsset = nil
local function GetLogoImage()
    if cachedLogoAsset then return cachedLogoAsset end

    -- Check if executor supports custom assets
    local getAsset = (syn and syn.custom_asset) or getcustomasset or getsynasset
    if getAsset and writefile and isfile then
        local ok, asset = pcall(function()
            if not isfile("serenity_logo_v2.png") then
                local imgData = FetchRaw("http://localhost:3000/serenity_logo_v2.png")
                    or FetchRaw("https://raw.githubusercontent.com/TripNation/Serenity-hub-main-COPY/main/serenity_logo_v2.png")
                    or FetchRaw("https://serenityhub.site/serenity_logo_v2.png")
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

    -- Clean fallback if executor does not support custom assets
    return "rbxassetid://10709790644"
end

-- Animated UI Banner Popup
local function ShowAnnouncement(announcement)
    -- Target GUI container
    local targetParent = nil
    pcall(function()
        targetParent = (gethui and gethui()) or game:GetService("CoreGui")
    end)
    if not targetParent and localPlayer and localPlayer:FindFirstChild("PlayerGui") then
        targetParent = localPlayer.PlayerGui
    end
    if not targetParent then
        targetParent = game:GetService("CoreGui")
    end

    -- If a previous banner is already on screen, remove it cleanly
    if activePopup and activePopup.Parent then
        activePopup:Destroy()
        activePopup = nil
    end

    -- Create ScreenGui if needed
    local screenGui = targetParent:FindFirstChild("HubAnnouncementGui")
    if not screenGui then
        screenGui = Instance.new("ScreenGui")
        screenGui.Name = "HubAnnouncementGui"
        screenGui.ResetOnSpawn = false
        screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        screenGui.Parent = targetParent
    end

    -- Main Card Container
    local card = Instance.new("Frame")
    card.Name = "AnnouncementCard"
    card.AnchorPoint = Vector2.new(0.5, 0)
    card.Size = UDim2.new(0, 420, 0, 68)
    card.Position = UDim2.new(0.5, 0, 0, -90) -- starts above screen
    card.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
    card.BorderSizePixel = 0
    card.ZIndex = 9999
    card.Parent = screenGui
    activePopup = card

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 10)
    cardCorner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1.2
    stroke.Color = Color3.fromRGB(55, 60, 75)
    stroke.Parent = card

    -- Left Logo Holder (with neon blue border and Serenity SH logo)
    local iconHolder = Instance.new("Frame")
    iconHolder.Name = "IconHolder"
    iconHolder.Size = UDim2.new(0, 42, 0, 42)
    iconHolder.Position = UDim2.new(0, 12, 0, 13)
    iconHolder.BackgroundColor3 = Color3.fromRGB(10, 11, 16)
    iconHolder.BorderSizePixel = 0
    iconHolder.ZIndex = 10000
    iconHolder.Parent = card

    local holderCorner = Instance.new("UICorner")
    holderCorner.CornerRadius = UDim.new(0, 8)
    holderCorner.Parent = iconHolder

    local holderStroke = Instance.new("UIStroke")
    holderStroke.Thickness = 1.2
    holderStroke.Color = Color3.fromRGB(0, 140, 255)
    holderStroke.Parent = iconHolder

    -- Serenity SH Logo Image
    local logoImg = Instance.new("ImageLabel")
    logoImg.Name = "LogoImage"
    logoImg.Size = UDim2.new(1, 0, 1, 0)
    logoImg.Position = UDim2.new(0.5, 0, 0.5, 0)
    logoImg.AnchorPoint = Vector2.new(0.5, 0.5)
    logoImg.BackgroundTransparency = 1
    logoImg.Image = GetLogoImage()
    logoImg.ScaleType = Enum.ScaleType.Fit
    logoImg.ZIndex = 10001
    logoImg.Parent = iconHolder

    local logoCorner = Instance.new("UICorner")
    logoCorner.CornerRadius = UDim.new(0, 8)
    logoCorner.Parent = logoImg

    -- Dismiss Button 'X'
    local dismissBtn = Instance.new("TextButton")
    dismissBtn.Name = "DismissBtn"
    dismissBtn.Size = UDim2.new(0, 24, 0, 24)
    dismissBtn.Position = UDim2.new(1, -30, 0, 8)
    dismissBtn.BackgroundTransparency = 1
    dismissBtn.Text = "✕"
    dismissBtn.TextColor3 = Color3.fromRGB(150, 155, 170)
    dismissBtn.Font = Enum.Font.GothamBold
    dismissBtn.TextSize = 13
    dismissBtn.ZIndex = 10002
    dismissBtn.Parent = card

    dismissBtn.MouseEnter:Connect(function()
        dismissBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    end)
    dismissBtn.MouseLeave:Connect(function()
        dismissBtn.TextColor3 = Color3.fromRGB(150, 155, 170)
    end)

    -- Header Title
    local rawType = tostring(announcement.type or "Announcement")
    local typeTitle = rawType:gsub("(%a)([%w_']*)", function(f, r) return f:upper() .. r:lower() end)
    local headerTitle = (announcement.title and announcement.title ~= "") and announcement.title or (AnnouncementConfig.HubName .. " " .. typeTitle)

    local headerLbl = Instance.new("TextLabel")
    headerLbl.Name = "Header"
    headerLbl.Size = UDim2.new(1, -95, 0, 18)
    headerLbl.Position = UDim2.new(0, 62, 0, 12)
    headerLbl.BackgroundTransparency = 1
    headerLbl.Text = headerTitle
    headerLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    headerLbl.Font = Enum.Font.GothamBold
    headerLbl.TextSize = 13
    headerLbl.TextXAlignment = Enum.TextXAlignment.Left
    headerLbl.ZIndex = 10000
    headerLbl.Parent = card

    -- Message Body
    local msgLbl = Instance.new("TextLabel")
    msgLbl.Name = "Message"
    msgLbl.Size = UDim2.new(1, -95, 0, 20)
    msgLbl.Position = UDim2.new(0, 62, 0, 32)
    msgLbl.BackgroundTransparency = 1
    msgLbl.Text = tostring(announcement.message or "")
    msgLbl.TextColor3 = Color3.fromRGB(190, 195, 205)
    msgLbl.Font = Enum.Font.GothamMedium
    msgLbl.TextSize = 11
    msgLbl.TextTruncate = Enum.TextTruncate.AtEnd
    msgLbl.TextXAlignment = Enum.TextXAlignment.Left
    msgLbl.ZIndex = 10000
    msgLbl.Parent = card

    -- Progress Bar Track
    local progressTrack = Instance.new("Frame")
    progressTrack.Name = "ProgressTrack"
    progressTrack.Size = UDim2.new(1, -24, 0, 3)
    progressTrack.Position = UDim2.new(0, 12, 1, -7)
    progressTrack.BackgroundColor3 = Color3.fromRGB(35, 38, 48)
    progressTrack.BorderSizePixel = 0
    progressTrack.ZIndex = 10000
    progressTrack.Parent = card

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(0, 2)
    trackCorner.Parent = progressTrack

    -- Animated Progress Fill
    local progressFill = Instance.new("Frame")
    progressFill.Name = "ProgressFill"
    progressFill.Size = UDim2.new(1, 0, 1, 0)
    progressFill.BackgroundColor3 = Color3.fromRGB(120, 135, 255)
    progressFill.BorderSizePixel = 0
    progressFill.ZIndex = 10001
    progressFill.Parent = progressTrack

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 2)
    fillCorner.Parent = progressFill

    -- Play notification sound if available
    pcall(function()
        local sound = Instance.new("Sound")
        sound.SoundId = "rbxassetid://4590662766" -- clean chime sound
        sound.Volume = 0.5
        sound.Parent = card
        sound:Play()
    end)

    -- Slide DOWN animation
    TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 0, 20)
    }):Play()

    -- Slide UP dismiss helper
    local isDismissed = false
    local function Dismiss()
        if isDismissed then return end
        isDismissed = true
        local outTween = TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = UDim2.new(0.5, 0, 0, -90)
        })
        outTween:Play()
        outTween.Completed:Connect(function()
            if card and card.Parent then card:Destroy() end
        end)
    end

    dismissBtn.MouseButton1Click:Connect(Dismiss)

    -- Duration timer with shrinking progress bar
    local durSecs = tonumber(announcement.duration) or 10
    if durSecs > 0 then
        TweenService:Create(progressFill, TweenInfo.new(durSecs, Enum.EasingStyle.Linear), {
            Size = UDim2.new(0, 0, 1, 0)
        }):Play()
        task.delay(durSecs, Dismiss)
    end
end

-- ==============================================================================
-- 21 Supported Games Catalog & Place ID Mapping
-- ==============================================================================
local SupportedGames = {
    ["103883942725157"] = "+1 Drain Water Per Click",
    ["74102906764176"]  = "Greedy Growers",
    ["91701030914075"]  = "+1 Monkey Evolution",
    ["97824450589417"]  = "+1 Superhero Evolution",
    ["103138601755519"] = "+1 Dino Evolution",
    ["104809044319701"] = "+1 Phonk Evolution",
    ["137233438285284"] = "Chicken Farm",
    ["90086669327265"]  = "+1 Cut Grass Adventure",
    ["122572082932179"] = "Sell Ores",
    ["108307565942574"] = "Heroes RNG",
    ["98894876188248"]  = "Cheating During Testing [BETA]",
    ["107653945083776"] = "Roll Anime to Fight!",
    ["122951224417794"] = "Unscathed RNG",
    ["109530157755211"] = "Lift A Cube",
    ["122245938604556"] = "+1 Tongue Escape",
    ["122216176958450"] = "Steal A Seed!",
    ["125927821145949"] = "Mine a Mountain",
    ["76377501906469"]  = "Steal And Hatch Anime Egg!",
    ["124216119978534"] = "Ride A Pet",
    ["86259628805375"]  = "+1 Strength to Grow your arm!",
    ["113290951185459"] = "Anime Dice"
}

-- Checks whether the current game matches the broadcast targeting
local function ShouldShowAnnouncement(announcement)
    if not announcement or not announcement.active then
        return false
    end

    local target = string.lower(announcement.target or "everyone")
    local targetMod = string.lower(announcement.targetModule or "")
    local targetPlaceId = tostring(announcement.targetPlaceId or "")

    -- 1. Broadcast to Everyone / All Supported Games
    if target == "everyone" or targetMod == "" or targetMod == "all" or targetMod == "everyone" then
        return true
    end

    -- 2. Game-Specific Targeting
    local currentPlaceId = tostring(game.PlaceId)
    local currentGameName = string.lower(SupportedGames[currentPlaceId] or "")

    -- Match by exact PlaceId
    if targetPlaceId ~= "" and targetPlaceId ~= "all" then
        if targetPlaceId == currentPlaceId then
            return true
        end
    end

    -- Match by targetModule (which may be the PlaceId or game name)
    if targetMod ~= "" and targetMod ~= "all" then
        if targetMod == currentPlaceId then
            return true
        end
        if currentGameName ~= "" and (targetMod == currentGameName or string.find(currentGameName, targetMod, 1, true) or string.find(targetMod, currentGameName, 1, true)) then
            return true
        end
    end

    return false
end

-- ==============================================================================
-- Background Polling Service
-- ==============================================================================
local function StartAnnouncementListener()
    task.spawn(function()
        if AnnouncementConfig.DebugMode then
            local pId = tostring(game.PlaceId)
            local gName = SupportedGames[pId] or "Unknown Game"
            print(string.format("[%s] 📢 Announcement listener active on '%s' (Place ID: %s)", AnnouncementConfig.HubName, gName, pId))
        end

        while true do
            pcall(function()
                local announcement = FetchLatestAnnouncement()
                if announcement and announcement.id and announcement.active then
                    local idStr = tostring(announcement.id)
                    -- Check if not displayed in this session
                    if not _G.HubSeenAnnouncements[idStr] then
                        _G.HubSeenAnnouncements[idStr] = true
                        if ShouldShowAnnouncement(announcement) then
                            ShowAnnouncement(announcement)
                        end
                    end
                end
            end)
            task.wait(AnnouncementConfig.PollInterval or 2)
        end
    end)
end

-- Auto-start when script runs
StartAnnouncementListener()

return {
    ShowAnnouncement = ShowAnnouncement,
    FetchLatestAnnouncement = FetchLatestAnnouncement,
    Start = StartAnnouncementListener
}
