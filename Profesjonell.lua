-- Profesjonell: Guild recipe tracker for WoW 1.12

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("TRADE_SKILL_UPDATE")
frame:RegisterEvent("CRAFT_SHOW")
frame:RegisterEvent("CRAFT_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_GUILD")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")

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

local guildRosterCache = {}
local lastRosterUpdate = 0

local function UpdateGuildRosterCache()
    local now = GetTime()
    -- Request a roster update from the server if it's been a while
    if now - lastRosterUpdate > 60 then
        GuildRoster()
    end
    
    if now - lastRosterUpdate < 10 then return end
    
    guildRosterCache = {}
    local num = GetNumGuildMembers()
    for i = 1, num do
        local name = GetGuildRosterInfo(i)
        if name then
            guildRosterCache[name] = true
        end
    end
    lastRosterUpdate = now
end

local function FindRecipeHolders(name)
    -- Extract name from item link if possible
    local _, _, cleanName = string.find(name, "%[(.+)%]")
    cleanName = cleanName or name
    
    -- IMPORTANT: Strip prefixes before returning cleanName to ensure consistency
    cleanName = StripPrefix(cleanName)
    local searchName = string.lower(cleanName)
    
    UpdateGuildRosterCache()
    local found = {}
    local partialMatches = {}
    
    for charName, recipes in pairs(ProfesjonellDB or {}) do
        -- Only show members who are still in the guild
        if guildRosterCache[charName] then
            for rName, _ in pairs(recipes) do
                local cleanRName = StripPrefix(rName)
                local lowerRName = string.lower(cleanRName)
                
                if lowerRName == searchName then
                    table.insert(found, charName)
                    break
                elseif string.find(lowerRName, searchName, 1, true) then
                    if not partialMatches[cleanRName] then partialMatches[cleanRName] = {} end
                    table.insert(partialMatches[cleanRName], charName)
                end
            end
        end
    end
    table.sort(found)
    return found, cleanName, partialMatches
end

local function IsInGuild(name)
    if not GetGuildName() then return false end
    UpdateGuildRosterCache()
    return guildRosterCache[name] == true
end

local function IsOfficer(name)
    if not GetGuildName() then return false end
    -- We can't easily cache rank without making the cache more complex, 
    -- but we can at least avoid calling it for every single message.
    for i = 1, GetNumGuildMembers() do
        local gName, rank, rankIndex = GetGuildRosterInfo(i)
        if gName == name then
            if rankIndex <= 1 or (rank and (string.find(string.lower(rank), "officer") or string.find(string.lower(rank), "master"))) then
                return true
            end
        end
    end
    return false
end

local function WipeDatabaseIfNoGuild()
    if not GetGuildName() then
        if ProfesjonellDB and next(ProfesjonellDB) then
            ProfesjonellDB = {}
            Print("You are no longer in a guild. The database has been wiped for security/privacy.")
        end
    end
end

local function GenerateDatabaseHash()
    UpdateGuildRosterCache()
    -- Create a sorted list of all char:recipe pairs to ensure deterministic hash
    local entries = {}
    for charName, recipes in pairs(ProfesjonellDB or {}) do
        if guildRosterCache[charName] then
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
        local version = GetAddOnMetadata("Profesjonell", "Version") or "0"
        Debug("Broadcasting database hash: " .. hash .. " (v" .. version .. ")")
        SendAddonMessage("Profesjonell", "HASH:" .. hash .. ":" .. version, "GUILD")
    end
end

local recipesToShare = {}
local sharingInProgress = false
local function ShareAllRecipes()
    if sharingInProgress then 
        Debug("Sharing already in progress, skipping.")
        return 
    end
    
    UpdateGuildRosterCache()
    -- Share all recipes from all characters in our DB
    -- We use a throttle to avoid overloading the addon channel
    recipesToShare = {}
    for charName, recipes in pairs(ProfesjonellDB or {}) do
        if guildRosterCache[charName] then
            for recipeName, _ in pairs(recipes) do
                table.insert(recipesToShare, {char = charName, recipe = recipeName})
            end
        end
    end

    if table.getn(recipesToShare) == 0 then return end

    sharingInProgress = true
    -- Process in chunks to avoid disconnects/throttling
    -- WoW 1.12 addon channel has limits.
    local index = 1
    local chunkTimer = CreateFrame("Frame")
    chunkTimer:SetScript("OnUpdate", function()
        local count = 0
        -- Send up to 5 recipes per frame (or some other reasonable limit)
        while index <= table.getn(recipesToShare) and count < 5 do
            local item = recipesToShare[index]
            ShareRecipe(item.recipe, item.char)
            index = index + 1
            count = count + 1
        end
        
        if index > table.getn(recipesToShare) then
            chunkTimer:SetScript("OnUpdate", nil)
            chunkTimer:Hide() -- Hide the frame since we're done
            sharingInProgress = false
            Debug("Finished sharing all recipes.")
        end
    end)
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
        BroadcastHash()
    end
end

local lastSyncRequest = 0
local pendingReplies = {}
local versionWarned = false

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

    for queryKey, data in pairs(pendingReplies) do
        if now >= data.time then
            local found, cleanName, partialMatches = FindRecipeHolders(data.originalQuery)
            local replyMsg
            if table.getn(found) > 0 then
                replyMsg = "Profesjonell: " .. cleanName .. " is known by: " .. table.concat(found, ", ")
            else
                -- Check if there's exactly one partial match to avoid spamming guild chat
                local matchCount = 0
                local pName, pHolders
                for name, holders in pairs(partialMatches) do
                    matchCount = matchCount + 1
                    pName = name
                    pHolders = holders
                end
                
                if matchCount == 1 then
                    table.sort(pHolders)
                    replyMsg = "Profesjonell: " .. pName .. " is known by: " .. table.concat(pHolders, ", ")
                elseif matchCount > 1 then
                    replyMsg = "Profesjonell: Multiple matches found for '" .. cleanName .. "'. Please be more specific."
                else
                    replyMsg = "Profesjonell: No one knows " .. cleanName
                end
            end
            SendChatMessage(replyMsg, "GUILD")
            Debug("Sent reply: " .. replyMsg)
            pendingReplies[queryKey] = nil
        end
    end
end)

frame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "Profesjonell" then
        if not ProfesjonellDB then
            ProfesjonellDB = {}
        end
        if not ProfesjonellConfig then
            ProfesjonellConfig = {}
        end
        Print("Loaded.")
        WipeDatabaseIfNoGuild()
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
        ScanRecipes(false)
    elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
        ScanRecipes(true)
    elseif event == "PLAYER_ENTERING_WORLD" then
        WipeDatabaseIfNoGuild()
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
                local queryKey = string.lower(cleanName)
                if not pendingReplies[queryKey] then
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
                    
                    local delay = 1.0 + playerOffset + math.random() * 2.5
                    Debug("Scheduling reply for " .. cleanName .. " in " .. string.format("%.2f", delay) .. "s")
                    pendingReplies[queryKey] = {
                        time = GetTime() + delay,
                        originalQuery = recipe,
                        cleanName = cleanName
                    }
                else
                    Debug("Reply already pending for " .. cleanName)
                end
            end
        -- Detect other addon's reply to prevent spam
        elseif string.find(msg, "^Profesjonell: ") then
            -- If someone else replied about a recipe, cancel our pending reply for it
            local lowerMsg = string.lower(msg)
            for queryKey, data in pairs(pendingReplies) do
                -- Simple check if the reply contains the recipe name (case-insensitive)
                -- queryKey is already lowercase
                if string.find(lowerMsg, queryKey, 1, true) then
                    Debug("Detected other player's reply for " .. queryKey .. ". Cancelling pending reply.")
                    pendingReplies[queryKey] = nil
                end
            end
        end
    elseif event == "PLAYER_GUILD_UPDATE" then
        WipeDatabaseIfNoGuild()
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
            local _, _, remoteHash, remoteVersion = string.find(message, "^HASH:([^:]+):(.+)$")
            
            -- Fallback for older versions that only sent HASH:hash
            if not remoteHash then
                remoteHash = string.sub(message, 6)
                remoteVersion = "0"
            end

            -- Version check
            if not versionWarned then
                local localVersion = GetAddOnMetadata("Profesjonell", "Version") or "0"
                if remoteVersion > localVersion then
                    Print("|cffff0000Warning:|r A newer version of Profesjonell (v" .. remoteVersion .. ") is available! Please update.")
                    versionWarned = true
                elseif remoteVersion < localVersion and remoteVersion ~= "0" then
                    -- If we have a newer version, broadcast it back once so they get the warning
                    frame.broadcastHashTime = GetTime() + 1
                    versionWarned = true -- Set to true so we don't keep doing this
                end
            end

            local localHash = GenerateDatabaseHash()
            if remoteHash ~= localHash then
                Debug("Hash mismatch! Remote: " .. remoteHash .. ", Local: " .. localHash)
                -- Delay request to avoid multiple people requesting at once
                local delay = 2 + math.random() * 5
                if not frame.syncTimer or GetTime() > frame.syncTimer then
                    frame.syncTimer = GetTime() + delay
                    -- Timer handled in OnUpdate
                    Debug("Sync scheduled in " .. string.format("%.2f", delay) .. "s")
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
        elseif string.find(message, "^REMOVE_RECIPE:") then
            -- Format: REMOVE_RECIPE:CharacterName:RecipeName
            local _, _, charName, recipeName = string.find(message, "^REMOVE_RECIPE:([^:]+):(.+)$")
            if charName and recipeName and IsOfficer(sender) then
                if ProfesjonellDB[charName] and ProfesjonellDB[charName][recipeName] then
                    ProfesjonellDB[charName][recipeName] = nil
                    Print("Removed " .. recipeName .. " from " .. charName .. " as requested by " .. sender)
                end
            end
        end
    end
end)

-- Slash Command
SLASH_PROFESJONELL1 = "/prof"
SLASH_PROFESJONELL2 = "/profesjonell"
SlashCmdList["PROFESJONELL"] = function(msg)
    if msg == "debug" then
        ProfesjonellConfig.debug = not ProfesjonellConfig.debug
        Print("Debug mode: " .. (ProfesjonellConfig.debug and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"))
        return
    end

    if msg == "sync" then
        local now = GetTime()
        if not lastSyncRequest or (now - lastSyncRequest > 30) then
            Print("Requesting manual sync from guild...")
            RequestSync()
            lastSyncRequest = now
        else
            local wait = math.ceil(30 - (now - lastSyncRequest))
            Print("Please wait " .. wait .. "s before syncing again.")
        end
        return
    end

    if string.find(msg, "^add ") then
        if IsOfficer(GetPlayerName()) then
            local _, _, charName, recipeName = string.find(msg, "^add ([^%s]+) (.+)$")
            if charName and recipeName then
                -- Extract name from item link if possible
                local _, _, cleanRecipeName = string.find(recipeName, "%[(.+)%]")
                cleanRecipeName = cleanRecipeName or recipeName

                if not ProfesjonellDB[charName] then
                    ProfesjonellDB[charName] = {}
                end

                if not ProfesjonellDB[charName][cleanRecipeName] then
                    ProfesjonellDB[charName][cleanRecipeName] = true
                    Print("Added " .. cleanRecipeName .. " to " .. charName .. " and broadcasting.")
                    
                    -- Announce to guild members using the addon
                    ShareRecipe(cleanRecipeName, charName)
                    
                    -- Announce to the guild chat as requested
                    if GetGuildName() then
                        SendChatMessage("Profesjonell: Added " .. cleanRecipeName .. " to " .. charName, "GUILD")
                    end
                else
                    Print(charName .. " already has " .. cleanRecipeName .. " in the database.")
                end
            else
                Print("Usage: /prof add [name] [recipe]")
            end
        else
            Print("Only officers can add recipes to guild members.")
        end
        return
    end

    if string.find(msg, "^remove ") then
        if IsOfficer(GetPlayerName()) then
            local _, _, charName, recipeName = string.find(msg, "^remove ([^%s]+) (.+)$")
            if charName and recipeName then
                -- Extract name from item link if possible
                local _, _, cleanRecipeName = string.find(recipeName, "%[(.+)%]")
                cleanRecipeName = cleanRecipeName or recipeName

                if ProfesjonellDB[charName] and ProfesjonellDB[charName][cleanRecipeName] then
                    ProfesjonellDB[charName][cleanRecipeName] = nil
                    Print("Removed " .. cleanRecipeName .. " from " .. charName .. " and broadcasting.")
                    
                    SendAddonMessage("Profesjonell", "REMOVE_RECIPE:" .. charName .. ":" .. cleanRecipeName, "GUILD")
                    
                    if GetGuildName() then
                        SendChatMessage("Profesjonell: Removed " .. cleanRecipeName .. " from " .. charName, "GUILD")
                    end
                else
                    Print(charName .. " does not have " .. (cleanRecipeName or "this recipe") .. " in the database.")
                end
            else
                -- If only name is provided, keep the old behavior of removing the whole character
                local charNameOnly = string.sub(msg, 8)
                if charNameOnly and charNameOnly ~= "" then
                    if ProfesjonellDB[charNameOnly] then
                        ProfesjonellDB[charNameOnly] = nil
                        Print("Removed " .. charNameOnly .. " from local database and broadcasting removal.")
                        SendAddonMessage("Profesjonell", "REMOVE_CHAR:" .. charNameOnly, "GUILD")
                    else
                        Print("Character " .. charNameOnly .. " not found in database.")
                    end
                else
                    Print("Usage: /prof remove [name] [recipe] (to remove a recipe)")
                    Print("   or: /prof remove [name] (to remove a character)")
                end
            end
        else
            Print("Only officers can remove recipes or characters from the guild database.")
        end
        return
    end

    if not msg or msg == "" or msg == "help" then
        Print("Available commands:")
        Print("  /prof [recipe name/link] - Search for who knows a recipe")
        Print("  /prof add [name] [recipe] - Add recipe to a member (officers only)")
        Print("  /prof remove [name] [recipe] - Remove a recipe from a member (officers only)")
        Print("  /prof remove [name] - Remove a character from DB (officers only)")
        Print("  /prof sync - Request manual sync from guild")
        Print("  /prof purge - Remove members no longer in guild from local DB (officers only)")
        Print("  /prof debug - Toggle debug mode")
        Print("  ?prof [recipe name/link] - Guild chat query")
        return
    end

    if msg == "purge" then
        if IsOfficer(GetPlayerName()) then
            UpdateGuildRosterCache()
            local charsToRemove = {}
            for charName, _ in pairs(ProfesjonellDB) do
                if not guildRosterCache[charName] then
                    table.insert(charsToRemove, charName)
                end
            end
            
            local count = table.getn(charsToRemove)
            if count == 0 then
                Print("No members to purge.")
                return
            end

            -- Process in chunks to avoid disconnects/throttling
            local index = 1
            local purgeTimer = CreateFrame("Frame")
            purgeTimer:SetScript("OnUpdate", function()
                local chunkCount = 0
                while index <= count and chunkCount < 5 do
                    local charName = charsToRemove[index]
                    ProfesjonellDB[charName] = nil
                    SendAddonMessage("Profesjonell", "REMOVE_CHAR:" .. charName, "GUILD")
                    index = index + 1
                    chunkCount = chunkCount + 1
                end
                
                if index > count then
                    purgeTimer:SetScript("OnUpdate", nil)
                    purgeTimer:Hide()
                    BroadcastHash()
                    Print("Purged and broadcasted " .. count .. " members no longer in guild.")
                end
            end)
        else
            Print("Only officers can purge the database.")
        end
        return
    end

    local found, cleanName, partialMatches = FindRecipeHolders(msg)
    
    if table.getn(found) > 0 then
        Print("Characters with " .. cleanName .. ": " .. table.concat(found, ", "))
    else
        local matchCount = 0
        for _ in pairs(partialMatches) do matchCount = matchCount + 1 end
        
        if matchCount > 0 then
            Print("No exact match for '" .. cleanName .. "', but found:")
            for rName, holders in pairs(partialMatches) do
                table.sort(holders)
                Print("  " .. rName .. ": " .. table.concat(holders, ", "))
            end
        else
            Print("No characters found with " .. cleanName)
        end
    end
end