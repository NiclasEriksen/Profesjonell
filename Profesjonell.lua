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

local function Debug(msg)
    if ProfesjonellConfig and ProfesjonellConfig.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaaProfesjonell Debug:|r " .. (msg or "nil"))
    end
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

local function IsInGuild(name)
    if not GetGuildName() then return false end
    for i = 1, GetNumGuildMembers() do
        local gName = GetGuildRosterInfo(i)
        if gName == name then
            return true
        end
    end
    return false
end

local function IsOfficer(name)
    if not GetGuildName() then return false end
    for i = 1, GetNumGuildMembers() do
        local gName, rank, rankIndex = GetGuildRosterInfo(i)
        if gName == name then
            -- Usually rankIndex 0 or 1 are officers/guild master in WoW 1.12
            -- We'll assume rankIndex <= 1 or rank contains "Officer" or "Master"
            if rankIndex <= 1 or string.find(string.lower(rank), "officer") or string.find(string.lower(rank), "master") then
                return true
            end
        end
    end
    return false
end

local function GenerateDatabaseHash()
    -- Create a sorted list of all char:recipe pairs to ensure deterministic hash
    local entries = {}
    for charName, recipes in pairs(ProfesjonellDB or {}) do
        if IsInGuild(charName) then
            for recipeName, _ in pairs(recipes) do
                table.insert(entries, charName .. ":" .. recipeName)
            end
        end
    end
    table.sort(entries)
    
    local hash = 0
    for _, entry in ipairs(entries) do
        for i = 1, string.len(entry) do
            -- Simple DJB2-like hash that works within Lua 5.0 constraints
            hash = math.mod(hash * 33 + string.byte(entry, i), 4294967296)
        end
    end
    return string.format("%x", hash)
end

local function ShareRecipe(recipeName, targetChar)
    if GetGuildName() then
        -- Only share if the target character is actually in the guild
        if not IsInGuild(targetChar) then return end

        local msg = "ADD:" .. recipeName
        -- Only use ADD_EXT if we are sharing for a character that is NOT the currently logged in one
        if targetChar and targetChar ~= GetPlayerName() then
            msg = "ADD_EXT:" .. targetChar .. ":" .. recipeName
        end
        Debug("Sending addon message: " .. msg)
        SendAddonMessage("Profesjonell", msg, "GUILD")
    end
end

local function RequestSync()
    if GetGuildName() then
        Debug("Sending sync request")
        SendAddonMessage("Profesjonell", "REQ_SYNC", "GUILD")
    end
end

local function BroadcastHash()
    if GetGuildName() then
        local hash = GenerateDatabaseHash()
        Debug("Broadcasting database hash: " .. hash)
        SendAddonMessage("Profesjonell", "HASH:" .. hash, "GUILD")
    end
end

local function ShareAllRecipes()
    -- Share all recipes from all characters in our DB
    -- We use a simple throttle to avoid overloading the addon channel
    -- Sending many messages at once can cause issues.
    local recipesToShare = {}
    for charName, recipes in pairs(ProfesjonellDB or {}) do
        if IsInGuild(charName) then
            for recipeName, _ in pairs(recipes) do
                table.insert(recipesToShare, {char = charName, recipe = recipeName})
            end
        end
    end

    -- Process in chunks or just send all if not too many.
    -- For now, we'll send them all but it's something to watch.
    for _, item in ipairs(recipesToShare) do
        ShareRecipe(item.recipe, item.char)
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
    if frame.broadcastHashTime and now >= frame.broadcastHashTime then
        BroadcastHash()
        frame.broadcastHashTime = nil
    end

    if frame.syncTimer and now >= frame.syncTimer then
        RequestSync()
        frame.syncTimer = nil
    end

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
            Debug("Sent reply: " .. replyMsg)
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
            -- Guild roster might not be immediately available, so we wait a few seconds
            frame.broadcastHashTime = now + 5
            lastSyncRequest = now
        end
    elseif event == "CHAT_MSG_GUILD" then
        local msg = arg1
        local sender = arg2
        
        -- Detect query
        if string.find(msg, "^%?prof ") then
            local recipe = string.sub(msg, 7)
            if recipe and recipe ~= "" then
                Debug("Query detected from " .. sender .. ": " .. recipe)
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
                    
                    local delay = 0.5 + playerOffset + math.random() * 1.5
                    Debug("Scheduling reply for " .. cleanName .. " in " .. string.format("%.2f", delay) .. "s")
                    pendingReplies[cleanName] = {
                        time = GetTime() + delay,
                        originalQuery = recipe
                    }
                else
                    Debug("Reply already pending for " .. cleanName)
                end
            end
        -- Detect other addon's reply to prevent spam
        elseif string.find(msg, "^Profesjonell: ") then
            -- If someone else replied about a recipe, cancel our pending reply for it
            for cleanName, data in pairs(pendingReplies) do
                -- Simple check if the reply contains the recipe name
                if string.find(msg, cleanName, 1, true) then
                    Debug("Detected other player's reply for " .. cleanName .. ". Cancelling pending reply.")
                    pendingReplies[cleanName] = nil
                end
            end
        end
    elseif event == "CHAT_MSG_ADDON" and arg1 == "Profesjonell" then
        local prefix, message = arg1, arg2
        local sender = arg4
        if sender == GetPlayerName() then return end
        
        Debug("Received addon message from " .. sender .. ": " .. message)
        if string.find(message, "^ADD:") then
            local recipeName = string.sub(message, 5)
            if IsInGuild(sender) then
                if not ProfesjonellDB[sender] then
                    ProfesjonellDB[sender] = {}
                end
                ProfesjonellDB[sender][recipeName] = true
            end
        elseif string.find(message, "^ADD_EXT:") then
            -- Format: ADD_EXT:CharacterName:RecipeName
            local _, _, charName, recipeName = string.find(message, "^ADD_EXT:([^:]+):(.+)$")
            if charName and recipeName and IsInGuild(charName) then
                if not ProfesjonellDB[charName] then
                    ProfesjonellDB[charName] = {}
                end
                ProfesjonellDB[charName][recipeName] = true
            end
        elseif message == "REQ_SYNC" then
            ShareAllRecipes()
        elseif string.find(message, "^HASH:") then
            local remoteHash = string.sub(message, 6)
            local localHash = GenerateDatabaseHash()
            if remoteHash ~= localHash then
                Debug("Hash mismatch! Remote: " .. remoteHash .. ", Local: " .. localHash)
                -- Delay request to avoid multiple people requesting at once
                local delay = 2 + math.random() * 5
                if not frame.syncTimer or GetTime() > frame.syncTimer then
                    frame.syncTimer = GetTime() + delay
                    -- We'll just use a simple timer here via OnUpdate if we really wanted to be precise,
                    -- but for simplicity let's just trigger it if it's the first one we see in a window
                    RequestSync()
                end
            end
        elseif string.find(message, "^REMOVE_CHAR:") then
            local charToRemove = string.sub(message, 13)
            if IsOfficer(sender) then
                if ProfesjonellDB[charToRemove] then
                    ProfesjonellDB[charToRemove] = nil
                    Print("Removed " .. charToRemove .. " from database as requested by " .. sender)
                end
            else
                Debug("Unauthorized removal request for " .. charToRemove .. " from " .. sender)
            end
        end
    end
end)

-- Slash Command
SLASH_PROFESJONELL1 = "/prof"
SLASH_PROFESJONELL2 = "/profesjonell"
SlashCmdList["PROFESJONELL"] = function(msg)

    if string.find(msg, "^remove ") then
        local charName = string.sub(msg, 8)
        if charName and charName ~= "" then
            if IsOfficer(GetPlayerName()) then
                if ProfesjonellDB[charName] then
                    ProfesjonellDB[charName] = nil
                    Print("Removed " .. charName .. " from local database and broadcasting removal.")
                    SendAddonMessage("Profesjonell", "REMOVE_CHAR:" .. charName, "GUILD")
                else
                    Print("Character " .. charName .. " not found in database.")
                end
            else
                Print("Only officers can remove characters from the guild database.")
            end
        else
            Print("Usage: /prof remove [character name]")
        end
        return
    end

    if not msg or msg == "" then
        Print("Usage: /prof [item link] or ?prof [item link] in guild chat")
        Print("Remove character: /prof remove [name] (Officers only)")
        Print("Toggle debug: /prof debug")
        return
    end

    local found, cleanName = FindRecipeHolders(msg)
    
    if table.getn(found) > 0 then
        Print("Characters with " .. cleanName .. ": " .. table.concat(found, ", "))
    else
        Print("No characters found with " .. cleanName)
    end
end