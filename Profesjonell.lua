-- Profesjonell: Guild recipe tracker for WoW 1.12

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("CRAFT_SHOW")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_GUILD")

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Profesjonell:|r " .. (msg or "nil"))
end

local function GetPlayerName()
    return UnitName("player")
end

local function GetGuildName()
    return GetGuildInfo("player")
end

local function StripPrefix(s)
    local prefixes = {"Recipe: ", "Pattern: ", "Plans: ", "Schematic: ", "Manual: ", "Formula: "}
    local lowerS = string.lower(s)
    for _, p in ipairs(prefixes) do
        if string.find(lowerS, "^" .. string.lower(p)) then
            return string.sub(s, string.len(p) + 1)
        end
    end
    return s
end

local function FindRecipeHolders(name)
    -- Extract name from item link if possible
    local _, _, cleanName = string.find(name, "%[(.+)%]")
    cleanName = cleanName or name
    local searchName = string.lower(StripPrefix(cleanName))
    
    local found = {}
    for charName, recipes in pairs(ProfesjonellDB or {}) do
        local charHasIt = false
        for rName, _ in pairs(recipes) do
            if string.lower(StripPrefix(rName)) == searchName then
                charHasIt = true
                break
            end
        end
        
        if charHasIt then
            table.insert(found, charName)
        end
    end
    return found, cleanName
end

local function ShareRecipe(recipeName)
    if GetGuildName() then
        SendAddonMessage("Profesjonell", "ADD:" .. recipeName, "GUILD")
    end
end

local function RequestSync()
    if GetGuildName() then
        SendAddonMessage("Profesjonell", "REQ_SYNC", "GUILD")
    end
end

local function ShareAllRecipes()
    local playerName = GetPlayerName()
    if ProfesjonellDB[playerName] then
        for recipeName, _ in pairs(ProfesjonellDB[playerName]) do
            ShareRecipe(recipeName)
        end
    end
end

local function ScanRecipes(isCraft)
    local numSkills
    local getSkillInfo
    
    if isCraft then
        numSkills = GetNumCrafts()
        getSkillInfo = GetCraftInfo
    else
        numSkills = GetNumTradeSkills()
        getSkillInfo = GetTradeSkillInfo
    end

    local playerName = GetPlayerName()
    if not ProfesjonellDB[playerName] then
        ProfesjonellDB[playerName] = {}
    end

    local newCount = 0
    for i = 1, numSkills do
        local name, type = getSkillInfo(i)
        if name and type ~= "header" then
            if not ProfesjonellDB[playerName][name] then
                ProfesjonellDB[playerName][name] = true
                newCount = newCount + 1
                ShareRecipe(name)
            end
        end
    end

    if newCount > 0 then
        Print("Found " .. newCount .. " new recipes!")
    end
end

local lastSyncRequest = 0
local pendingReplies = {}

frame:SetScript("OnUpdate", function()
    local now = GetTime()
    for cleanName, data in pairs(pendingReplies) do
        if now >= data.time then
            local found, _ = FindRecipeHolders(data.originalQuery)
            local replyMsg
            if table.getn(found) > 0 then
                replyMsg = "Profesjonell: " .. cleanName .. " is known by: " .. table.concat(found, ", ")
            else
                replyMsg = "Profesjonell: No one knows " .. cleanName
            end
            SendChatMessage(replyMsg, "GUILD")
            pendingReplies[cleanName] = nil
        end
    end
end)

frame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "Profesjonell" then
        if not ProfesjonellDB then
            ProfesjonellDB = {}
        end
        Print("Loaded.")
    elseif event == "TRADE_SKILL_SHOW" then
        ScanRecipes(false)
    elseif event == "CRAFT_SHOW" then
        ScanRecipes(true)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Request sync when entering world (guild info should be available)
        -- Add a simple throttle to avoid spamming on reload
        local now = GetTime()
        if now - lastSyncRequest > 30 then
            RequestSync()
            lastSyncRequest = now
        end
    elseif event == "CHAT_MSG_GUILD" then
        local msg = arg1
        local sender = arg2
        
        -- Detect query
        if string.find(msg, "^%?prof ") then
            local recipe = string.sub(msg, 7)
            if recipe and recipe ~= "" then
                local _, cleanName = FindRecipeHolders(recipe)
                -- Schedule a reply with a random delay to prevent multiple people from replying at once
                if not pendingReplies[cleanName] then
                    -- Use player name to create a consistent but different base delay for each player
                    local playerName = GetPlayerName()
                    local playerOffset = 0
                    if playerName then
                        -- Simple hash of player name to get an offset 0-0.5s
                        for i=1, string.len(playerName) do
                            playerOffset = math.mod(playerOffset + string.byte(playerName, i), 50)
                        end
                        playerOffset = playerOffset / 100
                    end
                    
                    pendingReplies[cleanName] = {
                        time = GetTime() + 0.5 + playerOffset + math.random() * 1.5,
                        originalQuery = recipe
                    }
                end
            end
        -- Detect other addon's reply to prevent spam
        elseif string.find(msg, "^Profesjonell: ") then
            -- If someone else replied about a recipe, cancel our pending reply for it
            for cleanName, data in pairs(pendingReplies) do
                -- Simple check if the reply contains the recipe name
                if string.find(msg, cleanName, 1, true) then
                    pendingReplies[cleanName] = nil
                end
            end
        end
    elseif event == "CHAT_MSG_ADDON" and arg1 == "Profesjonell" then
        local prefix, message = arg1, arg2
        local sender = arg4
        if sender == GetPlayerName() then return end
        
        if string.find(message, "^ADD:") then
            local recipeName = string.sub(message, 5)
            if not ProfesjonellDB[sender] then
                ProfesjonellDB[sender] = {}
            end
            ProfesjonellDB[sender][recipeName] = true
        elseif message == "REQ_SYNC" then
            ShareAllRecipes()
        end
    end
end)

-- Slash Command
SLASH_PROFESJONELL1 = "/prof"
SLASH_PROFESJONELL2 = "/profesjonell"
SlashCmdList["PROFESJONELL"] = function(msg)
    if not msg or msg == "" then
        Print("Usage: /prof [item link] or ?prof [item link] in guild chat")
        return
    end

    local found, cleanName = FindRecipeHolders(msg)
    
    if table.getn(found) > 0 then
        Print("Characters with " .. cleanName .. ": " .. table.concat(found, ", "))
    else
        Print("No characters found with " .. cleanName)
    end
end