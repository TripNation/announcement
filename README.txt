================================================================================
ROBLOX HUB ANNOUNCEMENT SYSTEM - STEP-BY-STEP SETUP GUIDE
================================================================================

This folder contains everything you need to add live in-game announcements 
to ANY Roblox hub script (including your buddy's hub).

--------------------------------------------------------------------------------
WHAT'S IN THIS FOLDER:
--------------------------------------------------------------------------------
1. announcement_module.lua
   - The complete announcement listener and UI popup banner.
   - Works with all executors (Synapse, Wave, KRNL, Fluxus, Delta, Solara, etc.).
   - Drops down from top of screen with smooth animations, chime sound, progress bar, 
     and dismiss button (X).
   - Automatically prevents duplicate spamming: each announcement only shows ONCE per session.
   - Polls your announcement API every 8 seconds.

2. README.txt
   - This setup guide.

================================================================================
HOW TO ADD THIS TO YOUR BUDDY'S HUB SCRIPT
================================================================================

You have TWO easy ways to add this to your buddy's script:

--------------------------------------------------------------------------------
METHOD 1: Load it via GitHub (RECOMMENDED - 1 Line of Code)
--------------------------------------------------------------------------------
Once you upload announcement_module.lua to a GitHub repository, you can simply 
paste this ONE line into the top of your buddy's hub script (e.g. loader.lua):

loadstring(game:HttpGet("https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/announcement_module.lua"))()

That's it! Whenever you change or update the announcement module on GitHub, 
it automatically updates in their game without needing to edit their script again!


--------------------------------------------------------------------------------
METHOD 2: Direct Paste (No GitHub needed for the Lua file)
--------------------------------------------------------------------------------
1. Open your buddy's hub script (or loader.lua).
2. Open announcement_module.lua from this folder.
3. Copy the entire contents of announcement_module.lua.
4. Paste it at the very TOP or very BOTTOM of your buddy's script.
5. Save the file.

================================================================================
CONFIGURATION & CUSTOMIZATION
================================================================================

Inside announcement_module.lua (around line 17), you will find:

local AnnouncementConfig = {
    ApiUrls = {
        "https://serenityhub.site/api/announcements/latest",
        "https://www.serenityhub.site/api/announcements/latest",
        "http://localhost:3000/api/announcements/latest"
    },
    HubName = "Serenity",            -- Shown in popup title (e.g. "Serenity Announcement")
    PollInterval = 8,                 -- Check every 8 seconds
    DebugMode = false
}

- ApiUrls:
  Replace "https://serenityhub.site" with your website's domain once your website 
  is live on Render. You can leave localhost:3000 for local testing.

- HubName:
  Change "Serenity" to whatever your buddy's hub is called (e.g. "Quantum Hub").

================================================================================
HOW TO TEST IT
================================================================================
1. Start your announcement website (locally with npm start, or on Render).
2. Go to your admin dashboard and click "SEND ANNOUNCEMENT" (or "SEND TEST").
3. Execute announcement_module.lua in Roblox.
4. You will see the sleek banner slide down from the top of the screen with a chime, 
   the progress bar will count down, and it will slide away cleanly!
