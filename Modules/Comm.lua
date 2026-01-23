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
    local batches = {}
    local batchCount = 0

    for _, recipeKey in ipairs(recipeList) do
        -- Check if adding this recipe would exceed the 255 char limit
        if string.len(currentMsg) + string.len(recipeKey) + 1 > 250 then
            table.insert(batches, {msg = currentMsg, count = batchCount})
            currentMsg = prefix .. recipeKey
            batchCount = 1
        else
            if currentMsg == prefix then
                currentMsg = currentMsg .. recipeKey
                batchCount = 1
            else
                currentMsg = currentMsg .. "," .. recipeKey
                batchCount = batchCount + 1
            end
        end
    end

    if currentMsg ~= prefix then
        table.insert(batches, {msg = currentMsg, count = batchCount})
    end

    local totalBatches = table.getn(batches)
    for i, batch in ipairs(batches) do
        Profesjonell.Debug("Sending recipe batch " .. i .. "/" .. totalBatches .. " (" .. batch.count .. " recipes)")
        SendAddonMessage(Profesjonell.Name, batch.msg, "GUILD")
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
        if hash then
            Profesjonell.Debug("Broadcasting database hash: " .. hash .. " (v" .. Profesjonell.Version .. ")")
            SendAddonMessage(Profesjonell.Name, "H:" .. hash .. ":" .. Profesjonell.Version, "GUILD")
        else
            Profesjonell.Debug("Could not generate hash (roster not ready), skipping broadcast.")
        end
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
    if not charHashes then
        Profesjonell.Debug("Could not generate character hashes, skipping response.")
        return
    end

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
    
    if string.find(message, "^B:") then
        local _, _, charName, idList = string.find(message, "^B:([^:]+):(.+)$")
        if charName and idList then
            local count = 0
            local gfindFunc = string.gfind or string.gmatch
            for _ in gfindFunc(idList, "([^,]+)") do
                count = count + 1
            end
            Profesjonell.Debug("Received recipe batch from " .. sender .. " for " .. charName .. " (" .. count .. " recipes)")
        else
            Profesjonell.Debug("Received addon message from " .. sender .. ": " .. message)
        end
    else
        Profesjonell.Debug("Received addon message from " .. sender .. ": " .. message)
    end
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
                            -- Cleanup legacy name-based entry if it exists for this character
                            local recipeName = Profesjonell.GetNameFromKey(id)
                            if recipeName and not string.find(recipeName, "^Unknown") then
                                if ProfesjonellDB[recipeName] and ProfesjonellDB[recipeName][charName] then
                                    ProfesjonellDB[recipeName][charName] = nil
                                    if not next(ProfesjonellDB[recipeName]) then
                                        ProfesjonellDB[recipeName] = nil
                                    end
                                end
                            end

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
                if Profesjonell.InvalidateTooltipCache then
                    Profesjonell.InvalidateTooltipCache()
                end
                -- Still doesn't match, but we are making progress. Delay the full sync.
                if Profesjonell.Frame.syncTimer and Profesjonell.Frame.lastRemoteHash then
                    local currentHash = Profesjonell.GenerateDatabaseHash()
                    if currentHash and currentHash == Profesjonell.Frame.lastRemoteHash then
                        Profesjonell.Debug("Incremental update resolved hash mismatch. Cancelling sync request.")
                        Profesjonell.Frame.syncTimer = nil
                        Profesjonell.Frame.lastRemoteHash = nil
                        Profesjonell.Frame.lastSyncPeer = nil
                        Profesjonell.Frame.syncPendingChars = nil
                    else
                        Profesjonell.Debug("Received data, extending sync timer.")
                        Profesjonell.Frame.syncTimer = GetTime() + 10 + math.random() * 5
                    end
                end

                if Profesjonell.Frame.syncPendingChars and sender == Profesjonell.Frame.lastSyncPeer then
                    Profesjonell.Frame.syncPendingChars = Profesjonell.Frame.syncPendingChars - 1
                    Profesjonell.Debug("Pending characters from " .. sender .. ": " .. Profesjonell.Frame.syncPendingChars)
                    
                    if Profesjonell.Frame.syncPendingChars <= 0 then
                        Profesjonell.Frame.syncPendingChars = nil
                        -- We received all data we requested. Check if we still mismatch.
                        if Profesjonell.Frame.lastRemoteHash then
                            local currentHash = Profesjonell.GenerateDatabaseHash()
                            if currentHash ~= Profesjonell.Frame.lastRemoteHash then
                                Profesjonell.Debug("Data received, but hashes still mismatch. Requesting Q from " .. sender)
                                -- Request Q from the peer we were syncing with
                                SendAddonMessage(Profesjonell.Name, "Q", "GUILD")
                                -- Keep tracking this peer and extend timer
                                Profesjonell.Frame.syncTimer = GetTime() + 15 + math.random() * 5
                            else
                                Profesjonell.Debug("Incremental update resolved hash mismatch.")
                                Profesjonell.Frame.syncTimer = nil
                                Profesjonell.Frame.lastRemoteHash = nil
                                Profesjonell.Frame.lastSyncPeer = nil
                            end
                        end
                    end
                end

                if Profesjonell.Frame.pendingShare then
                    Profesjonell.Debug("Received B from " .. sender .. ". Cancelling pending sync response.")
                    Profesjonell.Frame.pendingShare = nil
                end
                if Profesjonell.Frame.syncTimer then
                    Profesjonell.Debug("Received B, delaying sync request.")
                    -- We already extended it above if addedAny was true, 
                    -- but this part handles the general case and adds a bit more randomness.
                    Profesjonell.Frame.syncTimer = math.max(Profesjonell.Frame.syncTimer, GetTime() + 10 + math.random() * 5)
                end
            end
        end
    elseif string.find(message, "^S") or message == "REQ_SYNC" then
        if message == "S" or message == "REQ_SYNC" then
            Profesjonell.ShareAllRecipes()
        end
    elseif message == "Q" then
        Profesjonell.BroadcastCharacterHashes()
    elseif string.find(message, "^C:") then
        local _, _, data = string.find(message, "^C:(.+)$")
        if data then
            local myHashes = Profesjonell.GenerateCharacterHashes()
            if myHashes then
                local mismatchCount = 0
                local myOwnHashMismatch = false
                local gfindFunc = string.gfind or string.gmatch
                for charEntry in gfindFunc(data, "([^,]+)") do
                    local _, _, charName, remoteHash = string.find(charEntry, "([^:]+):([^:]+)")
                    if charName and remoteHash then
                        if charName == Profesjonell.GetPlayerName() then
                            if myHashes[charName] ~= remoteHash then
                                myOwnHashMismatch = true
                            end
                        elseif myHashes[charName] ~= remoteHash then
                            Profesjonell.Debug("Hash mismatch for " .. charName .. ". Requesting sync.")
                            SendAddonMessage(Profesjonell.Name, "R:" .. charName, "GUILD")
                            mismatchCount = mismatchCount + 1
                        end
                    end
                end

                if mismatchCount > 0 then
                    if Profesjonell.Frame.syncTimer then
                        -- Extend sync timer to allow character-specific syncs to complete
                        local extension = math.min(mismatchCount * 5, 30)
                        Profesjonell.Frame.syncTimer = GetTime() + 10 + extension + math.random() * 5
                        Profesjonell.Debug("Mismatches found: " .. mismatchCount .. ". Extending sync timer by " .. extension .. "s.")
                    end
                    -- Track how many characters we are waiting for from this peer
                    Profesjonell.Frame.syncPendingChars = mismatchCount
                elseif myOwnHashMismatch then
                    Profesjonell.Debug("Remote has an old hash for us. Pushing our recipes.")
                    local playerName = Profesjonell.GetPlayerName()
                    local recipes = {}
                    if ProfesjonellDB then
                        for key, holders in pairs(ProfesjonellDB) do
                            if holders[playerName] then
                                table.insert(recipes, key)
                            end
                        end
                    end
                    if table.getn(recipes) > 0 then
                        Profesjonell.ShareRecipes(playerName, recipes)
                    end
                    -- We pushed our data, now we just wait for the peer to update and broadcast H
                    if Profesjonell.Frame.syncTimer then
                        Profesjonell.Frame.syncTimer = GetTime() + 10 + math.random() * 5
                    end
                end
            else
                Profesjonell.Debug("Roster not ready for character hash comparison, skipping.")
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
            
            -- After responding to a request, if we were originally triggered by a broadcast 
            -- from this same peer and we still mismatch, we should ensure we eventually
            -- request data back from them.
            if sender == Profesjonell.Frame.lastSyncPeer and Profesjonell.Frame.lastRemoteHash then
                local currentHash = Profesjonell.GenerateDatabaseHash()
                if currentHash ~= Profesjonell.Frame.lastRemoteHash then
                    -- Delay our own sync slightly to avoid colliding with their requests
                    Profesjonell.Frame.syncTimer = math.max(Profesjonell.Frame.syncTimer or 0, GetTime() + 15 + math.random() * 5)
                    Profesjonell.Debug("Responded to " .. sender .. ", but hashes still mismatch. Scheduled reciprocal sync.")
                end
            end
        end
    elseif string.find(message, "^H:") or string.find(message, "^HASH:") then
        local pattern = "^H:([^:]+):(.+)$"
        if string.find(message, "^HASH:") then pattern = "^HASH:([^:]+):(.+)$" end
        
        local _, _, remoteHash, remoteVersion = string.find(message, pattern)
        if not remoteHash then
            local colonPos = string.find(message, ":")
            if colonPos then
                remoteHash = string.sub(message, colonPos + 1)
            else
                remoteHash = ""
            end
            remoteVersion = "0"
        end

        local localHash = Profesjonell.GenerateDatabaseHash()
        if localHash and localHash == remoteHash then
            if Profesjonell.Frame.pendingShare then
                Profesjonell.Debug("Remote hash matches ours. Cancelling pending sync response.")
                Profesjonell.Frame.pendingShare = nil
            end
            
            -- If we were syncing with this peer, we're done
            if sender == Profesjonell.Frame.lastSyncPeer then
                Profesjonell.Debug("Sync with " .. sender .. " completed successfully.")
                Profesjonell.Frame.syncTimer = nil
                Profesjonell.Frame.lastRemoteHash = nil
                Profesjonell.Frame.lastSyncPeer = nil
                Profesjonell.Frame.syncPendingChars = nil
                Profesjonell.Frame.syncRetryCount = nil
            end
        end

        if not Profesjonell.VersionWarned then
            if Profesjonell.CompareVersions(remoteVersion, Profesjonell.Version) > 0 then
                Profesjonell.Print("|cffff0000Warning:|r A newer version of Profesjonell (v" .. remoteVersion .. ") is available! Please update.")
                Profesjonell.VersionWarned = true
            elseif Profesjonell.CompareVersions(remoteVersion, Profesjonell.Version) < 0 and remoteVersion ~= "0" then
                Profesjonell.Frame.broadcastHashTime = GetTime() + 1
                Profesjonell.VersionWarned = true
            end
        end
        
        if localHash then
            if localHash ~= remoteHash then
                local versionDiff = Profesjonell.CompareVersions(remoteVersion, Profesjonell.Version)
                
                if versionDiff < 0 then
                    Profesjonell.Debug("Hash mismatch with older version " .. remoteVersion .. " from " .. sender .. ". Skipping sync to avoid loops.")
                    return
                end

                Profesjonell.Debug("Hash mismatch with " .. sender .. "! Requesting character hashes.")
                SendAddonMessage(Profesjonell.Name, "Q", "GUILD")
                
                Profesjonell.Frame.lastRemoteHash = remoteHash
                Profesjonell.Frame.lastSyncPeer = sender
                Profesjonell.Frame.syncPendingChars = nil -- Reset any stale count
                Profesjonell.Frame.syncRetryCount = 0 -- Reset retry count for new peer/hash
                local delay = 20 + math.random() * 10
                if not Profesjonell.Frame.syncTimer or GetTime() > Profesjonell.Frame.syncTimer then
                    Profesjonell.Frame.syncTimer = GetTime() + delay
                end
            else
                if Profesjonell.Frame.syncTimer or Profesjonell.Frame.lastRemoteHash == remoteHash then
                    Profesjonell.Debug("Hashes match, cancelling pending sync.")
                    Profesjonell.Frame.syncTimer = nil
                    Profesjonell.Frame.lastRemoteHash = nil
                    Profesjonell.Frame.lastSyncPeer = nil
                    Profesjonell.Frame.syncPendingChars = nil
                end
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
                if Profesjonell.InvalidateTooltipCache then
                    Profesjonell.InvalidateTooltipCache()
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
                if Profesjonell.InvalidateTooltipCache then
                    Profesjonell.InvalidateTooltipCache()
                end
            end
        end
    end
end
