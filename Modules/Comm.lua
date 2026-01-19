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

function Profesjonell.ShareRecipe(recipeName, targetChar)
    if Profesjonell.GetGuildName() then
        if not Profesjonell.IsInGuild(targetChar) then return end

        local msg = "ADD:" .. recipeName
        if targetChar and targetChar ~= Profesjonell.GetPlayerName() then
            msg = "ADD_EXT:" .. targetChar .. ":" .. recipeName
        end
        Profesjonell.Debug("Sending addon message: " .. msg)
        SendAddonMessage(Profesjonell.Name, msg, "GUILD")
    end
end

function Profesjonell.RequestSync()
    if Profesjonell.GetGuildName() then
        Profesjonell.Debug("Sending sync request")
        SendAddonMessage(Profesjonell.Name, "REQ_SYNC", "GUILD")
    end
end

function Profesjonell.BroadcastHash()
    if Profesjonell.GetGuildName() then
        local hash = Profesjonell.GenerateDatabaseHash()
        Profesjonell.Debug("Broadcasting database hash: " .. hash .. " (v" .. Profesjonell.Version .. ")")
        SendAddonMessage(Profesjonell.Name, "HASH:" .. hash .. ":" .. Profesjonell.Version, "GUILD")
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

    Profesjonell.RecipesToShare = {}
    if ProfesjonellDB then
        for recipeName, holders in pairs(ProfesjonellDB) do
            for charName, _ in pairs(holders) do
                if Profesjonell.GuildRosterCache and Profesjonell.GuildRosterCache[charName] then
                    table.insert(Profesjonell.RecipesToShare, {char = charName, recipe = recipeName})
                end
            end
        end
    end

    if table.getn(Profesjonell.RecipesToShare) == 0 then return end

    Profesjonell.SharingInProgress = true
    local index = 1
    local chunkTimer = CreateFrame("Frame")
    chunkTimer:SetScript("OnUpdate", function()
        local count = 0
        while index <= table.getn(Profesjonell.RecipesToShare) and count < 5 do
            local item = Profesjonell.RecipesToShare[index]
            Profesjonell.ShareRecipe(item.recipe, item.char)
            index = index + 1
            count = count + 1
        end
        
        if index > table.getn(Profesjonell.RecipesToShare) then
            chunkTimer:SetScript("OnUpdate", nil)
            chunkTimer:Hide()
            Profesjonell.SharingInProgress = false
            Profesjonell.Debug("Finished sharing all recipes.")
        end
    end)
end

function Profesjonell.OnAddonMessage(message, sender)
    if sender == Profesjonell.GetPlayerName() then return end
    
    Profesjonell.Debug("Received addon message from " .. sender .. ": " .. message)
    if string.find(message, "^ADD:") then
        local recipeName = string.sub(message, 5)
        if Profesjonell.IsInGuild(sender) then
            if not ProfesjonellDB[recipeName] then ProfesjonellDB[recipeName] = {} end
            if not ProfesjonellDB[recipeName][sender] then
                ProfesjonellDB[recipeName][sender] = true
                Profesjonell.SyncNewRecipesCount = Profesjonell.SyncNewRecipesCount + 1
                Profesjonell.SyncSources[sender] = true
                Profesjonell.SyncSummaryTimer = GetTime() + 2
                
                if Profesjonell.Frame.syncTimer and Profesjonell.Frame.lastRemoteHash then
                    if Profesjonell.GenerateDatabaseHash() == Profesjonell.Frame.lastRemoteHash then
                        Profesjonell.Debug("Incremental update resolved hash mismatch. Cancelling sync request.")
                        Profesjonell.Frame.syncTimer = nil
                        Profesjonell.Frame.lastRemoteHash = nil
                    end
                end
            end

            if Profesjonell.Frame.pendingShare then
                Profesjonell.Debug("Received ADD from " .. sender .. ". Cancelling pending sync response.")
                Profesjonell.Frame.pendingShare = nil
            end
            if Profesjonell.Frame.syncTimer then
                Profesjonell.Debug("Received ADD, delaying sync request.")
                Profesjonell.Frame.syncTimer = GetTime() + 2 + math.random() * 3
            end
        end
    elseif string.find(message, "^ADD_EXT:") then
        local _, _, charName, recipeName = string.find(message, "^ADD_EXT:([^:]+):(.+)$")
        if charName and recipeName and Profesjonell.IsInGuild(charName) then
            if not ProfesjonellDB[recipeName] then ProfesjonellDB[recipeName] = {} end
            if not ProfesjonellDB[recipeName][charName] then
                ProfesjonellDB[recipeName][charName] = true
                Profesjonell.SyncNewRecipesCount = Profesjonell.SyncNewRecipesCount + 1
                Profesjonell.SyncSources[sender] = true
                Profesjonell.SyncSummaryTimer = GetTime() + 2
                
                if Profesjonell.Frame.syncTimer and Profesjonell.Frame.lastRemoteHash then
                    if Profesjonell.GenerateDatabaseHash() == Profesjonell.Frame.lastRemoteHash then
                        Profesjonell.Frame.syncTimer = nil
                        Profesjonell.Frame.lastRemoteHash = nil
                    end
                end
            end

            if Profesjonell.Frame.pendingShare then
                Profesjonell.Frame.pendingShare = nil
            end
            if Profesjonell.Frame.syncTimer then
                Profesjonell.Frame.syncTimer = GetTime() + 2 + math.random() * 3
            end
        end
    elseif message == "REQ_SYNC" then
        Profesjonell.ShareAllRecipes()
    elseif string.find(message, "^HASH:") then
        local _, _, remoteHash, remoteVersion = string.find(message, "^HASH:([^:]+):(.+)$")
        if not remoteHash then
            remoteHash = string.sub(message, 6)
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
            Profesjonell.Debug("Hash mismatch! Remote: " .. remoteHash .. ", Local: " .. localHash)
            Profesjonell.Frame.lastRemoteHash = remoteHash
            local delay = 10 + math.random() * 10
            if not Profesjonell.Frame.syncTimer or GetTime() > Profesjonell.Frame.syncTimer then
                Profesjonell.Frame.syncTimer = GetTime() + delay
                Profesjonell.Debug("Sync scheduled in " .. string.format("%.2f", delay) .. "s")
            end
        else
            if Profesjonell.Frame.syncTimer or Profesjonell.Frame.lastRemoteHash == remoteHash then
                Profesjonell.Debug("Hashes match, cancelling pending sync.")
                Profesjonell.Frame.syncTimer = nil
                Profesjonell.Frame.lastRemoteHash = nil
            end
        end
    elseif string.find(message, "^REMOVE_CHAR:") then
        local charToRemove = string.sub(message, 13)
        if Profesjonell.IsOfficer(sender) then
            local removedCount = 0
            for recipeName, holders in pairs(ProfesjonellDB) do
                if holders[charToRemove] then
                    holders[charToRemove] = nil
                    removedCount = removedCount + 1
                    if not next(holders) then ProfesjonellDB[recipeName] = nil end
                end
            end
            if removedCount > 0 then
                Profesjonell.Print("Removed " .. charToRemove .. " from database as requested by " .. sender)
                if Profesjonell.Frame.syncTimer then
                    Profesjonell.Frame.syncTimer = GetTime() + 2 + math.random() * 3
                end
            end
        end
    elseif string.find(message, "^REMOVE_RECIPE:") then
        local _, _, charName, recipeName = string.find(message, "^REMOVE_RECIPE:([^:]+):(.+)$")
        if Profesjonell.IsOfficer(sender) then
            if ProfesjonellDB[recipeName] and ProfesjonellDB[recipeName][charName] then
                ProfesjonellDB[recipeName][charName] = nil
                if not next(ProfesjonellDB[recipeName]) then ProfesjonellDB[recipeName] = nil end
                Profesjonell.Print("Removed recipe '" .. recipeName .. "' from " .. charName .. " as requested by " .. sender)
                if Profesjonell.Frame.syncTimer then
                    Profesjonell.Frame.syncTimer = GetTime() + 2 + math.random() * 3
                end
            end
        end
    end
end
