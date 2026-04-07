-- Comm.lua
-- Communication, syncing, and sharing
-- Ensure the global table exists
Profesjonell = Profesjonell or {}

if Profesjonell.Log then
    Profesjonell.Log("Comm.lua loading")
end

local sharingInProgress = false
Profesjonell.LastSyncRequest = 0
Profesjonell.VersionWarned = {} -- Per-sender table; key "_newer" used for update warnings
Profesjonell.RemoteVersions = {}

-- Cache the string iteration function once at load time (WoW 1.12 uses gfind, later versions gmatch)
local gfindFunc = string.gfind or string.gmatch

-- Pre-compiled pattern for valid recipe ID validation (e.g. "i:1234", "s:5678")
local VALID_ID_PATTERN = "^%a+:%d+$"

-- Centralized pending action management
Profesjonell.Frame = Profesjonell.Frame or {}
Profesjonell.PendingActions = Profesjonell.PendingActions or {
    R = {}, -- Recipe requests per character
    B = {}, -- Batch sends per character
    Q = nil, -- Query character hashes
    C = nil, -- Character hash response
    P = {}, -- ?prof coordination per query key
    share = nil, -- Share all recipes delay
    broadcastHash = nil, -- Hash broadcast delay
    syncTimer = nil -- Sync retry timer
}

-- Legacy accessors for compatibility (will be removed gradually)
Profesjonell.Frame.pendingR = Profesjonell.PendingActions.R
Profesjonell.Frame.pendingB = Profesjonell.PendingActions.B

-- Helpers to keep the two sync timer variables in sync and centralise state cleanup.
-- Both pending.syncTimer and frame.syncTimer must always hold the same value;
-- pending.syncTimer is the authoritative one checked in OnCommUpdate.
local function SetSyncTimer(t)
    Profesjonell.PendingActions.syncTimer = t
    Profesjonell.Frame.syncTimer = t
end

local function ClearSyncState()
    Profesjonell.PendingActions.syncTimer = nil
    Profesjonell.Frame.syncTimer = nil
    Profesjonell.Frame.lastRemoteHash = nil
    Profesjonell.Frame.lastSyncPeer = nil
    Profesjonell.Frame.syncPendingChars = nil
    Profesjonell.Frame.syncRetryCount = nil
end

function Profesjonell.ShareRecipes(charName, recipeList)
    if not Profesjonell.GetGuildName() or not Profesjonell.IsInGuild(charName) then return end

    local prefix = "B:" .. charName .. ":"
    local prefixLen = string.len(prefix)
    local parts = {}
    local batches = {}
    local batchCount = 0
    local currentLen = prefixLen

    for _, recipeKey in ipairs(recipeList) do
        local keyLen = string.len(recipeKey)
        local separator = (batchCount > 0) and "," or ""
        local separatorLen = string.len(separator)

        -- Check if adding this recipe would exceed the 250 char limit
        if currentLen + separatorLen + keyLen > 250 then
            -- Finalize current batch
            table.insert(batches, {msg = prefix .. table.concat(parts, ","), count = batchCount})
            -- Start new batch
            parts = {recipeKey}
            batchCount = 1
            currentLen = prefixLen + keyLen
        else
            table.insert(parts, recipeKey)
            batchCount = batchCount + 1
            currentLen = currentLen + separatorLen + keyLen
        end
    end

    -- Finalize last batch
    if batchCount > 0 then
        table.insert(batches, {msg = prefix .. table.concat(parts, ","), count = batchCount})
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
            Profesjonell.Debug("Could not generate hash (roster not ready), rescheduling broadcast.")
            Profesjonell.Frame.broadcastHashTime = GetTime() + 5
        end
    end
end

function Profesjonell.ShareAllRecipes(isManual, baseDelay, rangeDelay)
    if sharingInProgress then
        Profesjonell.Debug("Sharing already in progress, skipping.")
        return
    end

    if not Profesjonell.UpdateGuildRosterCache() then
        Profesjonell.Debug("Roster not ready for sharing, delaying.")
        return
    end

    if not isManual then
        if not Profesjonell.Frame.pendingShare or GetTime() > Profesjonell.Frame.pendingShare then
            local delay = Profesjonell.GetSyncDelay(baseDelay or 0.5, rangeDelay or 2)
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

    local charsToShare = {}
    for charName, recipes in pairs(recipesByChar) do
        table.insert(charsToShare, {name = charName, recipes = recipes})
    end

    if table.getn(charsToShare) == 0 then return end

    sharingInProgress = true
    local index = 1
    local chunkTimer = Profesjonell.TimerFrames[1]
    chunkTimer:SetScript("OnUpdate", function()
        if index <= table.getn(charsToShare) then
            local item = charsToShare[index]
            Profesjonell.ShareRecipes(item.name, item.recipes)
            index = index + 1
        else
            chunkTimer:SetScript("OnUpdate", nil)
            sharingInProgress = false
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

    local parts = {}
    local currentLen = 2 -- "C:"
    local batches = {}

    for charName, hash in pairs(charHashes) do
        local entry = charName .. ":" .. hash
        local entryLen = string.len(entry)
        local separator = (table.getn(parts) > 0) and "," or ""
        local separatorLen = string.len(separator)

        if currentLen + separatorLen + entryLen > 250 then
            -- Finalize current batch
            local msg = "C:" .. table.concat(parts, ",")
            Profesjonell.Debug("Sending char hashes: " .. msg)
            SendAddonMessage(Profesjonell.Name, msg, "GUILD")
            -- Start new batch
            parts = {entry}
            currentLen = 2 + entryLen
        else
            table.insert(parts, entry)
            currentLen = currentLen + separatorLen + entryLen
        end
    end

    -- Finalize last batch (or send empty C: if no hashes)
    local msg = "C:" .. table.concat(parts, ",")
    Profesjonell.Debug("Sending char hashes: " .. msg)
    SendAddonMessage(Profesjonell.Name, msg, "GUILD")
end

function Profesjonell.OnCommUpdate()
    local now = GetTime()
    local frame = Profesjonell.Frame
    local pending = Profesjonell.PendingActions
    if not frame or not pending then return end

    -- Process broadcast hash
    if pending.broadcastHash and now >= pending.broadcastHash then
        Profesjonell.BroadcastHash()
        pending.broadcastHash = nil
        frame.broadcastHashTime = nil -- Legacy cleanup
    elseif frame.broadcastHashTime and now >= frame.broadcastHashTime then
        Profesjonell.BroadcastHash()
        frame.broadcastHashTime = nil
    end

    -- Process sync timer (single authoritative path via pending.syncTimer)
    if pending.syncTimer and now >= pending.syncTimer then
        if frame.lastRemoteHash and frame.lastSyncPeer then
            local currentHash = Profesjonell.GenerateDatabaseHash()
            if currentHash ~= frame.lastRemoteHash then
                if frame.syncRetryCount and frame.syncRetryCount >= 3 then
                    Profesjonell.Debug("Sync retries exhausted for " .. frame.lastSyncPeer .. ". Stopping sync to avoid loops.")
                    ClearSyncState()
                    return
                end

                frame.syncRetryCount = (frame.syncRetryCount or 0) + 1
                Profesjonell.Debug("Sync timer expired, hashes still mismatch (attempt " .. frame.syncRetryCount .. "/3). Requesting character hashes from " .. frame.lastSyncPeer)

                pending.Q = GetTime() + Profesjonell.GetSyncDelay(0.5, 1.5)
                frame.pendingQ = pending.Q
                SetSyncTimer(GetTime() + 15 + math.random() * 5)
                return
            end
            frame.syncRetryCount = nil
        end
        Profesjonell.RequestSync()
        ClearSyncState()
    end

    -- Process share
    if pending.share and now >= pending.share then
        Profesjonell.ShareAllRecipes(true)
        pending.share = nil
        frame.pendingShare = nil
    elseif frame.pendingShare and now >= frame.pendingShare then
        Profesjonell.ShareAllRecipes(true)
        frame.pendingShare = nil
    end

    -- Process Q
    if pending.Q and now >= pending.Q then
        Profesjonell.Debug("Sending delayed Q request")
        SendAddonMessage(Profesjonell.Name, "Q", "GUILD")
        pending.Q = nil
        frame.pendingQ = nil
    elseif frame.pendingQ and now >= frame.pendingQ then
        Profesjonell.Debug("Sending delayed Q request")
        SendAddonMessage(Profesjonell.Name, "Q", "GUILD")
        frame.pendingQ = nil
    end

    -- Process C
    if pending.C and now >= pending.C then
        Profesjonell.Debug("Sending delayed C response (char hashes)")
        Profesjonell.BroadcastCharacterHashes()
        pending.C = nil
        frame.pendingC = nil
    elseif frame.pendingC and now >= frame.pendingC then
        Profesjonell.Debug("Sending delayed C response (char hashes)")
        Profesjonell.BroadcastCharacterHashes()
        frame.pendingC = nil
    end

    -- Process R requests
    for charName, time in pairs(pending.R) do
        if now >= time then
            Profesjonell.Debug("Sending delayed R request for " .. charName)
            SendAddonMessage(Profesjonell.Name, "R:" .. charName, "GUILD")
            pending.R[charName] = nil
        end
    end

    -- Process B sends
    for charName, time in pairs(pending.B) do
        if now >= time then
            Profesjonell.Debug("Sending delayed B response for " .. charName)
            local recipes = {}
            if ProfesjonellDB then
                for key, holders in pairs(ProfesjonellDB) do
                    if holders[charName] then
                        table.insert(recipes, key)
                    end
                end
            end
            local recipeCount = table.getn(recipes)
            if recipeCount > 0 then
                Profesjonell.ShareRecipes(charName, recipes)
            end
            pending.B[charName] = nil
        end
    end
end

function Profesjonell.OnAddonMessage(message, sender)
    if sender == Profesjonell.GetPlayerName() then return end

    local remoteVersion = Profesjonell.RemoteVersions[sender]

    if string.sub(message, 1, 2) == "B:" then
        local _, _, charName, idList = string.find(message, "^B:([^:]+):(.+)$")
        if charName and idList then
            Profesjonell.Debug("Received recipe batch from " .. sender .. " for " .. charName)

            if Profesjonell.IsInGuild(charName) then
                -- Cancel pending R request: they already sent the data, no need to request it
                if Profesjonell.Frame.pendingR[charName] then
                    Profesjonell.Debug("Received B for " .. charName .. ". Cancelling pending R request.")
                    Profesjonell.Frame.pendingR[charName] = nil
                end
                -- Note: we intentionally do NOT cancel pendingB here. If we have a push scheduled
                -- it is because we hold data the sender may not have (bidirectional mismatch), and
                -- we still need to send it for convergence.

                local addedAny = false
                for rawId in gfindFunc(idList, "([^,]+)") do
                    -- Normalize ID and validate format
                    local id = Profesjonell.GetIDFromLink(rawId)

                    -- Only proceed if it looks like a valid ID
                    if id and string.find(id, VALID_ID_PATTERN) then
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
                end

                if addedAny then
                    if Profesjonell.InvalidateTooltipCache then
                        Profesjonell.InvalidateTooltipCache()
                    end

                    -- Reset retry count: we are making progress, don't penalise the sync
                    if Profesjonell.Frame.syncRetryCount and Profesjonell.Frame.syncRetryCount > 0 then
                        Profesjonell.Debug("Received new data from " .. sender .. ", resetting sync retry count.")
                        Profesjonell.Frame.syncRetryCount = 0
                    end

                    -- Schedule a hash re-broadcast so peers tracking us see the updated state
                    local pending = Profesjonell.PendingActions
                    if not pending.broadcastHash then
                        pending.broadcastHash = GetTime() + 3 + math.random() * 2
                        Profesjonell.Frame.broadcastHashTime = pending.broadcastHash
                    end

                    -- Still doesn't match, but we are making progress. Delay the full sync.
                    if Profesjonell.Frame.syncTimer and Profesjonell.Frame.lastRemoteHash then
                        local currentHash = Profesjonell.GenerateDatabaseHash()
                        if currentHash and currentHash == Profesjonell.Frame.lastRemoteHash then
                            Profesjonell.Debug("Incremental update resolved hash mismatch. Cancelling sync request.")
                            ClearSyncState()
                        else
                            Profesjonell.Debug("Received data, extending sync timer.")
                            SetSyncTimer(GetTime() + 10 + math.random() * 5)
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
                                    Profesjonell.Debug("Data received, but hashes still mismatch. Scheduling Q.")
                                    -- Request Q instead of sending immediately
                                    local pending = Profesjonell.PendingActions
                                    pending.Q = GetTime() + Profesjonell.GetSyncDelay(0.5, 1.5)
                                    Profesjonell.Frame.pendingQ = pending.Q
                                    -- Keep tracking this peer and extend timer
                                    SetSyncTimer(GetTime() + 15 + math.random() * 5)
                                else
                                    Profesjonell.Debug("Incremental update resolved hash mismatch.")
                                    ClearSyncState()
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
                        SetSyncTimer(math.max(Profesjonell.Frame.syncTimer, GetTime() + 10 + math.random() * 5))
                    end
                end
            end
        else
            Profesjonell.Debug("Received addon message from " .. sender .. ": " .. message)
        end
    elseif message == "S" then
        Profesjonell.ShareAllRecipes()
    elseif message == "Q" then
        -- Suppress our own pending Q to avoid duplicate broadcasts
        if Profesjonell.Frame.pendingQ or Profesjonell.PendingActions.Q then
            Profesjonell.Debug("Received Q from " .. sender .. ". Cancelling our own Q request.")
            Profesjonell.Frame.pendingQ = nil
            Profesjonell.PendingActions.Q = nil
        end
        local delay = Profesjonell.GetSyncDelay(0.5, 1.5)
        Profesjonell.Frame.pendingC = GetTime() + delay
        Profesjonell.Debug("Received Q from " .. sender .. ". Scheduling C response in " .. string.format("%.2f", delay) .. "s")
    elseif string.sub(message, 1, 2) == "C:" then
        local data = string.sub(message, 3)
        do
            -- Skip sync with incompatible old versions
            if remoteVersion and Profesjonell.CompareVersions(remoteVersion, "0.34") < 0 then
                Profesjonell.Debug("Ignoring C: from incompatible version " .. remoteVersion .. " from " .. sender)
                return
            end

            if Profesjonell.Frame.pendingC then
                Profesjonell.Debug("Received C from " .. sender .. ". Cancelling our own C response.")
                Profesjonell.Frame.pendingC = nil
            end
            local myHashes = Profesjonell.GenerateCharacterHashes()
            if myHashes then
                local mismatchCount = 0
                local myOwnHashMismatch = false
                local remoteChars = {}
                for charEntry in gfindFunc(data, "([^,]+)") do
                    local _, _, charName, remoteHash = string.find(charEntry, "([^:]+):([^:]+)")
                    if charName and remoteHash then
                        remoteChars[charName] = true
                        if charName == Profesjonell.GetPlayerName() then
                            if myHashes[charName] ~= remoteHash then
                                myOwnHashMismatch = true
                            end
                        elseif myHashes[charName] ~= remoteHash then
                            -- Pull their data for this character
                            Profesjonell.Debug("Hash mismatch for " .. charName .. ". Scheduling R request.")
                            local pullDelay = Profesjonell.GetSyncDelay(0.5, 1.5)
                            Profesjonell.Frame.pendingR[charName] = GetTime() + pullDelay
                            mismatchCount = mismatchCount + 1
                            -- If we also have local data for this character, push it back so the
                            -- remote gets any records we hold that they don't (bidirectional exchange)
                            if myHashes[charName] then
                                Profesjonell.Debug("We have local data for " .. charName .. " that may differ. Scheduling B push.")
                                local pushDelay = Profesjonell.GetSyncDelay(2.0, 4.0)
                                Profesjonell.Frame.pendingB[charName] = GetTime() + pushDelay
                            end
                        end
                    end
                end

                -- Check for characters we have locally that the remote didn't mention.
                -- These are characters the remote doesn't know about, so we push our data.
                local pushCount = 0
                local playerName = Profesjonell.GetPlayerName()
                for charName, _ in pairs(myHashes) do
                    if not remoteChars[charName] and charName ~= playerName then
                        Profesjonell.Debug("Remote missing character " .. charName .. ". Scheduling B push.")
                        local delay = Profesjonell.GetSyncDelay(0.5, 1.5)
                        Profesjonell.Frame.pendingB[charName] = GetTime() + delay
                        pushCount = pushCount + 1
                    end
                end

                if mismatchCount > 0 or pushCount > 0 then
                    if Profesjonell.Frame.syncTimer then
                        -- Extend sync timer to allow character-specific syncs to complete
                        local totalActions = mismatchCount + pushCount
                        local extension = math.min(totalActions * 5, 30)
                        SetSyncTimer(GetTime() + 10 + extension + math.random() * 5)
                        Profesjonell.Debug("Mismatches: " .. mismatchCount .. ", pushes: " .. pushCount .. ". Extending sync timer by " .. extension .. "s.")
                    end
                    -- Track how many characters we are waiting for from this peer
                    Profesjonell.Frame.syncPendingChars = mismatchCount
                    -- Also push our own recipes if the remote has a stale hash for us
                    if myOwnHashMismatch then
                        local delay = Profesjonell.GetSyncDelay(0.5, 1.5, true)
                        Profesjonell.Frame.pendingB[playerName] = GetTime() + delay
                    end
                elseif myOwnHashMismatch then
                    Profesjonell.Debug("Remote has an old hash for us. Scheduling push of our recipes.")
                    local playerName = Profesjonell.GetPlayerName()
                    local delay = Profesjonell.GetSyncDelay(0.5, 1.5, true)
                    Profesjonell.Frame.pendingB[playerName] = GetTime() + delay

                    -- We pushed our data, now we just wait for the peer to update and broadcast H
                    if Profesjonell.Frame.syncTimer then
                        SetSyncTimer(GetTime() + 10 + math.random() * 5)
                    end
                else
                    -- No mismatches found in this C message.
                    -- If we were waiting for this peer, we might be done if we didn't find any mismatches to pull.
                    if sender == Profesjonell.Frame.lastSyncPeer then
                        local currentHash = Profesjonell.GenerateDatabaseHash()
                        if currentHash ~= Profesjonell.Frame.lastRemoteHash then
                            -- We have nothing to pull from them, but they are still mismatching our view.
                            -- This means we likely have data they don't.
                            -- Broadcast our hash so they can initiate a pull from us.
                            Profesjonell.Debug("No mismatches to pull from " .. sender .. ", but hashes still mismatch. Scheduling reciprocal broadcast.")
                            local pending = Profesjonell.PendingActions
                            pending.broadcastHash = GetTime() + Profesjonell.GetSyncDelay(1.0, 3.0)
                            Profesjonell.Frame.broadcastHashTime = pending.broadcastHash
                        else
                            Profesjonell.Debug("No mismatches found in C response from " .. sender .. ". Sync considered complete.")
                        end
                        ClearSyncState()
                    end
                end
            else
                Profesjonell.Debug("Roster not ready for character hash comparison, skipping.")
            end
        end
    elseif string.sub(message, 1, 2) == "R:" then
        local charName = string.sub(message, 3)
        if charName and charName ~= "" then
            if Profesjonell.Frame.pendingR[charName] then
                Profesjonell.Debug("Received R for " .. charName .. " from " .. sender .. ". Cancelling our own R request.")
                Profesjonell.Frame.pendingR[charName] = nil
            end
            local isMyChar = (charName == Profesjonell.GetPlayerName())
            local delay = Profesjonell.GetSyncDelay(0.5, 1.5, isMyChar)
            Profesjonell.Frame.pendingB[charName] = GetTime() + delay
            Profesjonell.Debug("Received R for " .. charName .. " from " .. sender .. ". Scheduling B response in " .. string.format("%.2f", delay) .. "s")

            -- After responding to a request, if we were originally triggered by a broadcast
            -- from this same peer and we still mismatch, we should ensure we eventually
            -- request data back from them.
            if sender == Profesjonell.Frame.lastSyncPeer and Profesjonell.Frame.lastRemoteHash then
                local currentHash = Profesjonell.GenerateDatabaseHash()
                if currentHash ~= Profesjonell.Frame.lastRemoteHash then
                    -- Delay our own sync slightly to avoid colliding with their requests
                    SetSyncTimer(math.max(Profesjonell.PendingActions.syncTimer or 0, GetTime() + 15 + math.random() * 5))
                    Profesjonell.Debug("Scheduled B response for " .. sender .. ", but hashes still mismatch. Scheduled reciprocal sync.")
                end
            end
        end
    elseif string.sub(message, 1, 2) == "H:" then
        local _, _, remoteHash, remoteVersion = string.find(message, "^H:([^:]+):(.+)$")

        if not remoteHash or not remoteVersion then
            Profesjonell.Debug("Received malformed H: message from " .. sender)
            return
        end

        Profesjonell.RemoteVersions[sender] = remoteVersion

        local localHash = Profesjonell.GenerateDatabaseHash()
        if localHash and localHash == remoteHash then
            if Profesjonell.Frame.pendingShare then
                Profesjonell.Debug("Remote hash matches ours. Cancelling pending sync response.")
                Profesjonell.Frame.pendingShare = nil
            end

            -- If we were syncing with this peer, we're done
            if sender == Profesjonell.Frame.lastSyncPeer then
                Profesjonell.Debug("Sync with " .. sender .. " completed successfully.")
                ClearSyncState()
            end
        end

        -- Warn about version mismatches (per-sender to avoid silencing warnings from different players)
        local versionDiff = Profesjonell.CompareVersions(remoteVersion, Profesjonell.Version)
        if versionDiff > 0 and not Profesjonell.VersionWarned["_newer"] then
            Profesjonell.Print("|cffff0000Warning:|r A newer version of Profesjonell (v" .. remoteVersion .. ") is available! Please update.")
            Profesjonell.VersionWarned["_newer"] = true
        elseif versionDiff < 0 and Profesjonell.CompareVersions(remoteVersion, "0.34") < 0 and not Profesjonell.VersionWarned[sender] then
            Profesjonell.Print("|cffff0000Incompatible:|r " .. sender .. " is using v" .. remoteVersion .. " (requires v0.34+). Sync disabled.")
            Profesjonell.VersionWarned[sender] = true
        end

        if localHash then
            if localHash ~= remoteHash then
                -- Skip sync with incompatible old versions
                if Profesjonell.CompareVersions(remoteVersion, "0.34") < 0 then
                    Profesjonell.Debug("Ignoring hash mismatch with incompatible version " .. remoteVersion .. " from " .. sender)
                    return
                end

                Profesjonell.Debug("Hash mismatch with " .. sender .. "! Scheduling Q request.")
                local pending = Profesjonell.PendingActions
                pending.Q = GetTime() + Profesjonell.GetSyncDelay(0.5, 1.5)
                Profesjonell.Frame.pendingQ = pending.Q

                Profesjonell.Frame.syncPendingChars = nil -- Reset any stale count
                -- Only reset retry count if the peer or hash actually changed
                if Profesjonell.Frame.lastSyncPeer ~= sender or Profesjonell.Frame.lastRemoteHash ~= remoteHash then
                    Profesjonell.Frame.syncRetryCount = 0
                end
                Profesjonell.Frame.lastRemoteHash = remoteHash
                Profesjonell.Frame.lastSyncPeer = sender
                local delay = 20 + math.random() * 10
                if not pending.syncTimer or GetTime() > pending.syncTimer then
                    SetSyncTimer(GetTime() + delay)
                end
            else
                if Profesjonell.Frame.syncTimer or Profesjonell.Frame.lastRemoteHash == remoteHash then
                    Profesjonell.Debug("Hashes match, cancelling pending sync.")
                    ClearSyncState()
                end
            end
        end
    elseif string.sub(message, 1, 12) == "REMOVE_CHAR:" then
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
                if Profesjonell.PendingActions.syncTimer then
                    SetSyncTimer(GetTime() + 2 + math.random() * 3)
                end
                if Profesjonell.InvalidateTooltipCache then
                    Profesjonell.InvalidateTooltipCache()
                end
            end
        end
    elseif string.sub(message, 1, 14) == "REMOVE_RECIPE:" then
        local _, _, charName, recipeKey = string.find(message, "^REMOVE_RECIPE:([^:]+):(.+)$")
        if Profesjonell.IsOfficer(sender) then
            -- Normalize recipeKey for backward compatibility
            recipeKey = Profesjonell.GetIDFromLink(recipeKey) or recipeKey

            if ProfesjonellDB[recipeKey] and ProfesjonellDB[recipeKey][charName] then
                ProfesjonellDB[recipeKey][charName] = nil
                if not next(ProfesjonellDB[recipeKey]) then ProfesjonellDB[recipeKey] = nil end
                Profesjonell.Print("Removed recipe '" .. recipeKey .. "' from " .. Profesjonell.ColorizeName(charName) .. " as requested by " .. Profesjonell.ColorizeName(sender))
                if Profesjonell.PendingActions.syncTimer then
                    SetSyncTimer(GetTime() + 2 + math.random() * 3)
                end
                if Profesjonell.InvalidateTooltipCache then
                    Profesjonell.InvalidateTooltipCache()
                end
            end
        end
    elseif string.sub(message, 1, 2) == "P:" then
        local queryKey = string.sub(message, 3)
        if queryKey then
            if Profesjonell.PendingReplies[queryKey] then
                -- Someone else is claiming this reply. Use alphabetical name comparison for priority.
                if sender < Profesjonell.GetPlayerName() then
                    Profesjonell.Debug("Received P for '" .. queryKey .. "' from " .. sender .. " (higher priority). Cancelling local reply.")
                    Profesjonell.PendingReplies[queryKey] = nil
                else
                    Profesjonell.Debug("Received P for '" .. queryKey .. "' from " .. sender .. " but we have priority (alphabetically). Keeping local reply.")
                end
            end
        end
    end
end
