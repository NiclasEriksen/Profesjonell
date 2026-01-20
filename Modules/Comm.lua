-- Comm.lua
-- Communication, syncing, and sharing
-- Ensure the global table exists
Profesjonell = Profesjonell or {}

if Profesjonell.Log then
    Profesjonell.Log("Comm.lua loading")
end

Profesjonell.SharingInProgress = false
Profesjonell.RecipesToShare = {}
Profesjonell.LastSyncRequest = 0
Profesjonell.VersionWarned = false

function Profesjonell.ShareRecipes(charName, recipeList)
    if not Profesjonell.GetGuildName() or not Profesjonell.IsInGuild(charName) then return end
    
    local prefix = "B:" .. charName .. ":"
    local currentMsg = prefix
    
    for _, recipeKey in ipairs(recipeList) do
        -- Check if adding this recipe would exceed the 255 char limit
        if string.len(currentMsg) + string.len(recipeKey) + 1 > 250 then
            Profesjonell.Debug("Sending batched addon message (full): " .. currentMsg)
            SendAddonMessage(Profesjonell.Name, currentMsg, "GUILD")
            currentMsg = prefix .. recipeKey
        else
            if currentMsg == prefix then
                currentMsg = currentMsg .. recipeKey
            else
                currentMsg = currentMsg .. "," .. recipeKey
            end
        end
    end
    
    if currentMsg ~= prefix then
        Profesjonell.Debug("Sending batched addon message: " .. currentMsg)
        SendAddonMessage(Profesjonell.Name, currentMsg, "GUILD")
    end
end

function Profesjonell.RequestSync()
    if Profesjonell.GetGuildName() then
        Profesjonell.Debug("Sending sync request")
        SendAddonMessage(Profesjonell.Name, "S", "GUILD")
    end
end

function Profesjonell.BroadcastHash()
    if Profesjonell.GetGuildName() then
        local hash = Profesjonell.GenerateDatabaseHash()
        Profesjonell.Debug("Broadcasting database hash: " .. hash .. " (v" .. Profesjonell.Version .. ")")
        SendAddonMessage(Profesjonell.Name, "H:" .. hash .. ":" .. Profesjonell.Version, "GUILD")
    end
end

function Profesjonell.ShareAllRecipes(isManual)
    if Profesjonell.SharingInProgress then 
        Profesjonell.Debug("Sharing already in progress, skipping.")
        return 
    end
    
    if not Profesjonell.UpdateGuildRosterCache() then
        Profesjonell.Debug("Roster not ready for sharing, delaying.")
        return
    end

    if not isManual then
        if not Profesjonell.Frame.pendingShare or GetTime() > Profesjonell.Frame.pendingShare then
            local playerName = Profesjonell.GetPlayerName()
            local playerOffset = 0
            if playerName then
                for i=1, string.len(playerName) do
                    playerOffset = math.mod(playerOffset + string.byte(playerName, i), 50)
                end
                playerOffset = playerOffset / 100
            end
            
            local delay = 0.5 + playerOffset + math.random() * 2
            Profesjonell.Frame.pendingShare = GetTime() + delay
            Profesjonell.Debug("Sync response scheduled in " .. string.format("%.2f", delay) .. "s")
        end
        return
    end

    local recipesByChar = {}
    if ProfesjonellDB then
        for recipeKey, holders in pairs(ProfesjonellDB) do
            for charName, _ in pairs(holders) do
                if Profesjonell.GuildRosterCache and Profesjonell.GuildRosterCache[charName] then
                    if not recipesByChar[charName] then recipesByChar[charName] = {} end
                    table.insert(recipesByChar[charName], recipeKey)
                end
            end
        end
    end

    Profesjonell.CharsToShare = {}
    for charName, recipes in pairs(recipesByChar) do
        table.insert(Profesjonell.CharsToShare, {name = charName, recipes = recipes})
    end

    if table.getn(Profesjonell.CharsToShare) == 0 then return end

    Profesjonell.SharingInProgress = true
    local index = 1
    local chunkTimer = CreateFrame("Frame")
    chunkTimer:SetScript("OnUpdate", function()
        if index <= table.getn(Profesjonell.CharsToShare) then
            local item = Profesjonell.CharsToShare[index]
            Profesjonell.ShareRecipes(item.name, item.recipes)
            index = index + 1
        else
            chunkTimer:SetScript("OnUpdate", nil)
            chunkTimer:Hide()
            Profesjonell.SharingInProgress = false
            Profesjonell.Debug("Finished sharing all recipes.")
        end
    end)
end

function Profesjonell.BroadcastCharacterHashes()
    local charHashes = Profesjonell.GenerateCharacterHashes()
    local currentMsg = "C:"
    
    for charName, hash in pairs(charHashes) do
        local entry = charName .. ":" .. hash
        if string.len(currentMsg) + string.len(entry) + 1 > 250 then
            Profesjonell.Debug("Sending char hashes: " .. currentMsg)
            SendAddonMessage(Profesjonell.Name, currentMsg, "GUILD")
            currentMsg = "C:" .. entry
        else
            if currentMsg == "C:" then
                currentMsg = currentMsg .. entry
            else
                currentMsg = currentMsg .. "," .. entry
            end
        end
    end
    
    if currentMsg ~= "C:" then
        Profesjonell.Debug("Sending char hashes: " .. currentMsg)
        SendAddonMessage(Profesjonell.Name, currentMsg, "GUILD")
    end
end

function Profesjonell.OnAddonMessage(message, sender)
    if sender == Profesjonell.GetPlayerName() then return end
    
    Profesjonell.Debug("Received addon message from " .. sender .. ": " .. message)
    if string.find(message, "^B:") then
        local _, _, charName, idList = string.find(message, "^B:([^:]+):(.+)$")
        if charName and idList and Profesjonell.IsInGuild(charName) then
            local addedAny = false
            local gfindFunc = string.gfind or string.gmatch
            for id in gfindFunc(idList, "([^,]+)") do
                -- Normalize ID and validate format
                local _, _, type, idNum = string.find(id, "([^:]+):(%d+)")
                if type and idNum then
                    if type == "item" then id = "i:" .. idNum
                    elseif type == "spell" then id = "s:" .. idNum
                    elseif type == "enchant" then id = "e:" .. idNum
                    else id = type .. ":" .. idNum
                    end
                    
                    -- Only proceed if it looks like a valid ID
                    if string.find(id, "^%a+:%d+$") then
                        if not ProfesjonellDB[id] then ProfesjonellDB[id] = {} end
                        if not ProfesjonellDB[id][charName] then
                            ProfesjonellDB[id][charName] = true
                            Profesjonell.SyncNewRecipesCount = Profesjonell.SyncNewRecipesCount + 1
                            Profesjonell.SyncSources[sender] = true
                            Profesjonell.SyncSummaryTimer = GetTime() + 2
                            addedAny = true
                        end
                    end
                else
                    Profesjonell.Debug("Ignoring invalid recipe key from " .. sender .. ": " .. id)
                end
            end
            
            if addedAny then
                if Profesjonell.Frame.syncTimer and Profesjonell.Frame.lastRemoteHash then
                    if Profesjonell.GenerateDatabaseHash() == Profesjonell.Frame.lastRemoteHash then
                        Profesjonell.Debug("Incremental update resolved hash mismatch. Cancelling sync request.")
                        Profesjonell.Frame.syncTimer = nil
                        Profesjonell.Frame.lastRemoteHash = nil
                    end
                end

                if Profesjonell.Frame.pendingShare then
                    Profesjonell.Debug("Received B from " .. sender .. ". Cancelling pending sync response.")
                    Profesjonell.Frame.pendingShare = nil
                end
                if Profesjonell.Frame.syncTimer then
                    Profesjonell.Debug("Received B, delaying sync request.")
                    Profesjonell.Frame.syncTimer = GetTime() + 2 + math.random() * 3
                end
            end
        end
    elseif message == "S" or message == "REQ_SYNC" then
        Profesjonell.ShareAllRecipes()
    elseif message == "Q" then
        Profesjonell.BroadcastCharacterHashes()
    elseif string.find(message, "^C:") then
        local _, _, data = string.find(message, "^C:(.+)$")
        if data then
            local myHashes = Profesjonell.GenerateCharacterHashes()
            local gfindFunc = string.gfind or string.gmatch
            for charEntry in gfindFunc(data, "([^,]+)") do
                local _, _, charName, remoteHash = string.find(charEntry, "([^:]+):([^:]+)")
                if charName and remoteHash then
                    if myHashes[charName] ~= remoteHash then
                        Profesjonell.Debug("Hash mismatch for " .. charName .. ". Requesting sync.")
                        SendAddonMessage(Profesjonell.Name, "R:" .. charName, "GUILD")
                    end
                end
            end
        end
    elseif string.find(message, "^R:") then
        local charName = string.sub(message, 3)
        if charName then
            local recipes = {}
            if ProfesjonellDB then
                for key, holders in pairs(ProfesjonellDB) do
                    if holders[charName] then
                        table.insert(recipes, key)
                    end
                end
            end
            if table.getn(recipes) > 0 then
                Profesjonell.ShareRecipes(charName, recipes)
            end
        end
    elseif string.find(message, "^H:") or string.find(message, "^HASH:") then
        local pattern = "^H:([^:]+):(.+)$"
        if string.find(message, "^HASH:") then pattern = "^HASH:([^:]+):(.+)$" end
        
        local _, _, remoteHash, remoteVersion = string.find(message, pattern)
        if not remoteHash then
            remoteHash = string.sub(message, string.len(string.find(message, ":")) + 1)
            remoteVersion = "0"
        end

        local localHash = Profesjonell.GenerateDatabaseHash()
        if localHash == remoteHash then
            if Profesjonell.Frame.pendingShare then
                Profesjonell.Debug("Remote hash matches ours. Cancelling pending sync response.")
                Profesjonell.Frame.pendingShare = nil
            end
        end

        if not Profesjonell.VersionWarned then
            if remoteVersion > Profesjonell.Version then
                Profesjonell.Print("|cffff0000Warning:|r A newer version of Profesjonell (v" .. remoteVersion .. ") is available! Please update.")
                Profesjonell.VersionWarned = true
            elseif remoteVersion < Profesjonell.Version and remoteVersion ~= "0" then
                Profesjonell.Frame.broadcastHashTime = GetTime() + 1
                Profesjonell.VersionWarned = true
            end
        end
        
        if localHash ~= remoteHash then
            Profesjonell.Debug("Hash mismatch! Requesting character hashes.")
            SendAddonMessage(Profesjonell.Name, "Q", "GUILD")
            
            Profesjonell.Frame.lastRemoteHash = remoteHash
            local delay = 10 + math.random() * 10
            if not Profesjonell.Frame.syncTimer or GetTime() > Profesjonell.Frame.syncTimer then
                Profesjonell.Frame.syncTimer = GetTime() + delay
            end
        else
            if Profesjonell.Frame.syncTimer or Profesjonell.Frame.lastRemoteHash == remoteHash then
                Profesjonell.Debug("Hashes match, cancelling pending sync.")
                Profesjonell.Frame.syncTimer = nil
                Profesjonell.Frame.lastRemoteHash = nil
            end
        end
    elseif string.find(message, "^REMOVE_CHAR:") then
        -- We'll keep REMOVE support for now, but it's officer only
        local charToRemove = string.sub(message, 13)
        if Profesjonell.IsOfficer(sender) then
            local removedCount = 0
            for recipeKey, holders in pairs(ProfesjonellDB) do
                if holders[charToRemove] then
                    holders[charToRemove] = nil
                    removedCount = removedCount + 1
                    if not next(holders) then ProfesjonellDB[recipeKey] = nil end
                end
            end
            if removedCount > 0 then
                Profesjonell.Print("Removed " .. Profesjonell.ColorizeName(charToRemove) .. " from database as requested by " .. Profesjonell.ColorizeName(sender))
                if Profesjonell.Frame.syncTimer then
                    Profesjonell.Frame.syncTimer = GetTime() + 2 + math.random() * 3
                end
            end
        end
    elseif string.find(message, "^REMOVE_RECIPE:") then
        local _, _, charName, recipeKey = string.find(message, "^REMOVE_RECIPE:([^:]+):(.+)$")
        if Profesjonell.IsOfficer(sender) then
            -- Normalize recipeKey for backward compatibility
            local _, _, type, idNum = string.find(recipeKey, "([^:]+):(%d+)")
            if type == "item" then recipeKey = "i:" .. idNum
            elseif type == "spell" then recipeKey = "s:" .. idNum
            elseif type == "enchant" then recipeKey = "e:" .. idNum
            end

            if ProfesjonellDB[recipeKey] and ProfesjonellDB[recipeKey][charName] then
                ProfesjonellDB[recipeKey][charName] = nil
                if not next(ProfesjonellDB[recipeKey]) then ProfesjonellDB[recipeKey] = nil end
                Profesjonell.Print("Removed recipe '" .. recipeKey .. "' from " .. Profesjonell.ColorizeName(charName) .. " as requested by " .. Profesjonell.ColorizeName(sender))
                if Profesjonell.Frame.syncTimer then
                    Profesjonell.Frame.syncTimer = GetTime() + 2 + math.random() * 3
                end
            end
        end
    end
end
