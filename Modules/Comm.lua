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
Profesjonell.KnownAddonUsers = Profesjonell.KnownAddonUsers or {}
Profesjonell.KnownAddonUserCount = Profesjonell.KnownAddonUserCount or 0
Profesjonell.LastHBroadcastTime = 0 -- Minimum interval tracking for H broadcasts

-- Anti-loop B cancellation state
Profesjonell.YieldedBTo = {} -- charName -> sender we yielded to
Profesjonell.BPriority = {} -- charName -> true if our next B should not be cancelled

-- Per-peer sync exhaustion cooldown: ExhaustedPeers[sender] = {time=GetTime(), count=N}
-- After exhausting retries with a peer, we back off with increasing delays.
Profesjonell.ExhaustedPeers = {}

-- C: message accumulation buffer (per-sender)
-- Structure: IncomingCBuffer[sender] = { chars = {name=hash,...}, lastReceived=time, settleTime=time }
Profesjonell.IncomingCBuffer = {}
local C_SETTLE_DELAY = 1.5 -- seconds to wait after last C: split before processing

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
    Profesjonell.Frame.syncRetryCount = nil
    Profesjonell.Frame.pendingQTarget = nil
    Profesjonell.YieldedBTo = {}
    Profesjonell.BPriority = {}
    Profesjonell.IncomingCBuffer = {}
    -- If a queued peer is waiting, start a new sync cycle with them
    if Profesjonell.Frame.nextSyncPeer and Profesjonell.Frame.nextSyncHash then
        local peer = Profesjonell.Frame.nextSyncPeer
        local hash = Profesjonell.Frame.nextSyncHash
        Profesjonell.Frame.nextSyncPeer = nil
        Profesjonell.Frame.nextSyncHash = nil
        Profesjonell.Debug("Starting queued sync with " .. peer)
        Profesjonell.Frame.lastRemoteHash = hash
        Profesjonell.Frame.lastSyncPeer = peer
        Profesjonell.Frame.syncRetryCount = 0
        -- Deterministic coordinator: only lowest name coordinates
        local myName = Profesjonell.GetPlayerName()
        if myName < peer then
            local delay = Profesjonell.GetSyncDelay(0.5, 1.5)
            Profesjonell.PendingActions.Q = GetTime() + delay
            Profesjonell.Frame.pendingQ = Profesjonell.PendingActions.Q
            Profesjonell.Frame.pendingQTarget = peer
        end
        local syncDelay = 20 + math.random() * 10
        SetSyncTimer(GetTime() + syncDelay)
    end
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
    -- Phase B: Deprecated. We no longer send S (full sync) to avoid flooding.
    -- Instead, we rely on targeted Q:<name> queries and coordinator election.
    -- We still *respond* to incoming S from old clients (see OnAddonMessage handler).
    if Profesjonell.GetGuildName() then
        Profesjonell.Debug("Sync request suppressed (Phase B: S command deprecated). Using targeted sync instead.")
        -- Fall back to a targeted Q if we have a known sync peer
        if Profesjonell.Frame.lastSyncPeer then
            local delay = Profesjonell.GetSyncDelay(0.5, 1.5)
            Profesjonell.PendingActions.Q = GetTime() + delay
            Profesjonell.Frame.pendingQ = Profesjonell.PendingActions.Q
            Profesjonell.Frame.pendingQTarget = Profesjonell.Frame.lastSyncPeer
            Profesjonell.Debug("Scheduling targeted Q:" .. Profesjonell.Frame.lastSyncPeer .. " instead of S.")
        end
    end
end

-- Minimum interval between H broadcasts (seconds)
Profesjonell.MIN_H_BROADCAST_INTERVAL = 30

function Profesjonell.BroadcastHash()
    if Profesjonell.GetGuildName() then
        local now = GetTime()
        -- Suppress H re-broadcasts during active sync cycles (check first, before interval)
        if Profesjonell.PendingActions.syncTimer then
            Profesjonell.Debug("Suppressing H broadcast during active sync cycle.")
            return
        end
        -- Enforce minimum interval between H broadcasts
        if now - Profesjonell.LastHBroadcastTime < Profesjonell.MIN_H_BROADCAST_INTERVAL then
            Profesjonell.Debug("Suppressing H broadcast: minimum interval not reached (" .. string.format("%.0f", Profesjonell.MIN_H_BROADCAST_INTERVAL - (now - Profesjonell.LastHBroadcastTime)) .. "s remaining).")
            return
        end
        local hash = Profesjonell.GenerateDatabaseHash()
        if hash then
            Profesjonell.Debug("Broadcasting database hash: " .. hash .. " (v" .. Profesjonell.Version .. ")")
            SendAddonMessage(Profesjonell.Name, "H:" .. hash .. ":" .. Profesjonell.Version, "GUILD")
            Profesjonell.LastHBroadcastTime = now
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

-- Process accumulated character hashes from a single sender.
-- Called from OnCommUpdate after the settle delay, with the fully accumulated
-- remoteChars table containing ALL characters from ALL C: splits.
function Profesjonell.ProcessCharacterHashes(sender, remoteCharHashes)
    local myHashes = Profesjonell.GenerateCharacterHashes()
    if not myHashes then
        Profesjonell.Debug("Roster not ready for character hash comparison, skipping.")
        return
    end

    local mismatchCount = 0
    local myOwnHashMismatch = false
    local remoteChars = {}

    for charName, remoteHash in pairs(remoteCharHashes) do
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
                -- Mark as priority if we previously yielded B for this character
                if Profesjonell.YieldedBTo and Profesjonell.YieldedBTo[charName] then
                    if not Profesjonell.BPriority then Profesjonell.BPriority = {} end
                    Profesjonell.BPriority[charName] = true
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
            -- Mark as priority if we previously yielded B for this character
            if Profesjonell.YieldedBTo and Profesjonell.YieldedBTo[charName] then
                if not Profesjonell.BPriority then Profesjonell.BPriority = {} end
                Profesjonell.BPriority[charName] = true
            end
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
        -- Also push our own recipes if the remote has a stale hash for us
        if myOwnHashMismatch then
            local delay = Profesjonell.GetSyncDelay(0.5, 1.5, true)
            Profesjonell.Frame.pendingB[playerName] = GetTime() + delay
        end
    elseif myOwnHashMismatch then
        Profesjonell.Debug("Remote has an old hash for us. Scheduling push of our recipes.")
        local delay = Profesjonell.GetSyncDelay(0.5, 1.5, true)
        Profesjonell.Frame.pendingB[playerName] = GetTime() + delay

        -- We pushed our data, now we just wait for the peer to update and broadcast H
        if Profesjonell.Frame.syncTimer then
            SetSyncTimer(GetTime() + 10 + math.random() * 5)
        end
    else
        -- No mismatches found in accumulated C response.
        -- If we were waiting for this peer, we might be done.
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
                    local peer = frame.lastSyncPeer
                    -- Track exhaustion for this peer with escalating backoff
                    local exhaustInfo = Profesjonell.ExhaustedPeers[peer] or {time = 0, count = 0}
                    exhaustInfo.count = exhaustInfo.count + 1
                    exhaustInfo.time = GetTime()
                    Profesjonell.ExhaustedPeers[peer] = exhaustInfo
                    -- Backoff: 5 min, 10 min, 15 min, ... capped at 15 min
                    local cooldownMinutes = math.min(exhaustInfo.count * 5, 15)
                    Profesjonell.Debug("Sync retries exhausted for " .. peer .. " (" .. exhaustInfo.count .. " time(s)). Backing off for " .. cooldownMinutes .. " min.")
                    ClearSyncState()
                    -- Schedule a fresh H broadcast after the cooldown so a clean sync cycle can eventually start
                    local cooldownSec = cooldownMinutes * 60 + math.random() * 30
                    pending.broadcastHash = GetTime() + cooldownSec
                    frame.broadcastHashTime = pending.broadcastHash
                    Profesjonell.Debug("Fresh H broadcast scheduled in ~" .. string.format("%.0f", cooldownSec) .. "s for " .. peer)
                    return
                end

                frame.syncRetryCount = (frame.syncRetryCount or 0) + 1
                Profesjonell.Debug("Sync timer expired, hashes still mismatch (attempt " .. frame.syncRetryCount .. "/3). Requesting character hashes from " .. frame.lastSyncPeer .. ".")

                pending.Q = GetTime() + Profesjonell.GetSyncDelay(0.5, 1.5)
                frame.pendingQ = pending.Q
                -- First retry uses targeted Q; subsequent retries fall back
                -- to broadcast Q for backward compatibility with older clients that
                -- don't understand the Q:<target> format.
                if frame.syncRetryCount <= 1 then
                    frame.pendingQTarget = frame.lastSyncPeer
                    Profesjonell.Debug("Sending targeted Q:" .. frame.lastSyncPeer .. ".")
                else
                    frame.pendingQTarget = nil
                    Profesjonell.Debug("Falling back to broadcast Q for backward compatibility.")
                end
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
        local target = frame.pendingQTarget
        if target then
            Profesjonell.Debug("Sending targeted Q:" .. target)
            SendAddonMessage(Profesjonell.Name, "Q:" .. target, "GUILD")
        else
            Profesjonell.Debug("Sending delayed Q request")
            SendAddonMessage(Profesjonell.Name, "Q", "GUILD")
        end
        pending.Q = nil
        frame.pendingQ = nil
        frame.pendingQTarget = nil
    elseif frame.pendingQ and now >= frame.pendingQ then
        local target = frame.pendingQTarget
        if target then
            Profesjonell.Debug("Sending targeted Q:" .. target)
            SendAddonMessage(Profesjonell.Name, "Q:" .. target, "GUILD")
        else
            Profesjonell.Debug("Sending delayed Q request")
            SendAddonMessage(Profesjonell.Name, "Q", "GUILD")
        end
        frame.pendingQ = nil
        frame.pendingQTarget = nil
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

    -- Process settled C: buffers
    if Profesjonell.IncomingCBuffer then
        for bufSender, buf in pairs(Profesjonell.IncomingCBuffer) do
            if buf.settleTime and now >= buf.settleTime then
                local charCount = 0
                for _ in pairs(buf.chars) do charCount = charCount + 1 end
                Profesjonell.Debug("Processing settled C: buffer from " .. bufSender .. " with " .. charCount .. " characters")
                Profesjonell.ProcessCharacterHashes(bufSender, buf.chars)
                Profesjonell.IncomingCBuffer[bufSender] = nil
            end
        end
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
            -- Clear yield/priority state after successfully sending B
            if Profesjonell.YieldedBTo then Profesjonell.YieldedBTo[charName] = nil end
            if Profesjonell.BPriority then Profesjonell.BPriority[charName] = nil end
        end
    end
end

function Profesjonell.OnAddonMessage(message, sender)
    if sender == Profesjonell.GetPlayerName() then return end

    -- Track known addon users for delay scaling
    if not Profesjonell.KnownAddonUsers[sender] then
        Profesjonell.KnownAddonUsers[sender] = true
        Profesjonell.KnownAddonUserCount = Profesjonell.KnownAddonUserCount + 1
    end

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
                -- Cancel pending B for this character unconditionally, unless we
                -- previously yielded to this same sender and marked our B as priority
                if Profesjonell.PendingActions.B[charName] then
                    local isPriority = Profesjonell.BPriority and Profesjonell.BPriority[charName]
                    if isPriority then
                        Profesjonell.Debug("Received B for " .. charName .. " from " .. sender .. " but our B is priority (previously yielded). Keeping.")
                        -- Priority consumed: clear it so future yields work normally
                        Profesjonell.BPriority[charName] = nil
                    else
                        Profesjonell.Debug("Received B for " .. charName .. " from " .. sender .. ". Cancelling our pending B (deferring).")
                        Profesjonell.PendingActions.B[charName] = nil
                        -- Track who we yielded to, so next time we mark our B as priority
                        if not Profesjonell.YieldedBTo then Profesjonell.YieldedBTo = {} end
                        Profesjonell.YieldedBTo[charName] = sender
                    end
                end

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

                    if Profesjonell.Frame.pendingShare then
                        Profesjonell.Debug("Received B from " .. sender .. ". Cancelling pending sync response.")
                        Profesjonell.Frame.pendingShare = nil
                    end
                end
            end
        else
            Profesjonell.Debug("Received addon message from " .. sender .. ": " .. message)
        end
    elseif string.sub(message, 1, 2) == "E:" then
        -- Legacy: E: coordinator election messages from older Phase B clients.
        -- No longer used; kept as no-op for backward compatibility.
        Profesjonell.Debug("Received legacy E: from " .. sender .. " (ignored).")
    elseif message == "S" then
        Profesjonell.ShareAllRecipes()
    elseif string.sub(message, 1, 2) == "Q:" then
        -- Phase B: Targeted Q:<targetPlayer> — only respond if we are the target
        local target = string.sub(message, 3)
        if target == Profesjonell.GetPlayerName() then
            -- Suppress our own pending Q to avoid duplicate broadcasts
            if Profesjonell.Frame.pendingQ or Profesjonell.PendingActions.Q then
                Profesjonell.Debug("Received targeted Q from " .. sender .. ". Cancelling our own Q request.")
                Profesjonell.Frame.pendingQ = nil
                Profesjonell.PendingActions.Q = nil
                Profesjonell.Frame.pendingQTarget = nil
            end
            local delay = Profesjonell.GetSyncDelay(0.5, 1.5)
            Profesjonell.PendingActions.C = GetTime() + delay
            Profesjonell.Frame.pendingC = Profesjonell.PendingActions.C
            Profesjonell.Debug("Received targeted Q from " .. sender .. " for us. Scheduling C response in " .. string.format("%.2f", delay) .. "s")
        else
            Profesjonell.Debug("Received targeted Q from " .. sender .. " for " .. target .. " (not us). Ignoring.")
        end
    elseif message == "Q" then
        -- Suppress our own pending Q to avoid duplicate broadcasts
        if Profesjonell.Frame.pendingQ or Profesjonell.PendingActions.Q then
            Profesjonell.Debug("Received Q from " .. sender .. ". Cancelling our own Q request.")
            Profesjonell.Frame.pendingQ = nil
            Profesjonell.PendingActions.Q = nil
            Profesjonell.Frame.pendingQTarget = nil
        end
        -- Wider jitter window for C response (Phase A: was 0.5-1.5, now 2-6)
        local delay = Profesjonell.GetSyncDelay(2.0, 4.0)
        Profesjonell.PendingActions.C = GetTime() + delay
        Profesjonell.Frame.pendingC = Profesjonell.PendingActions.C
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

            -- Accumulate into per-sender buffer instead of processing immediately.
            -- C: messages are split across multiple messages to stay under the 250-char
            -- limit, so we must collect all splits before comparing character lists.
            if not Profesjonell.IncomingCBuffer then Profesjonell.IncomingCBuffer = {} end
            if not Profesjonell.IncomingCBuffer[sender] then
                Profesjonell.IncomingCBuffer[sender] = { chars = {} }
            end
            local buf = Profesjonell.IncomingCBuffer[sender]

            for charEntry in gfindFunc(data, "([^,]+)") do
                local _, _, charName, remoteHash = string.find(charEntry, "([^:]+):([^:]+)")
                if charName and remoteHash then
                    buf.chars[charName] = remoteHash
                end
            end

            buf.lastReceived = GetTime()
            buf.settleTime = GetTime() + C_SETTLE_DELAY

            local charCount = 0
            for _ in pairs(buf.chars) do charCount = charCount + 1 end
            Profesjonell.Debug("Buffered C: from " .. sender .. " (accumulated chars: " .. charCount .. ")")
        end
    elseif string.sub(message, 1, 2) == "R:" then
        local charName = string.sub(message, 3)
        if charName and charName ~= "" then
            if Profesjonell.Frame.pendingR[charName] then
                Profesjonell.Debug("Received R for " .. charName .. " from " .. sender .. ". Cancelling our own R request.")
                Profesjonell.Frame.pendingR[charName] = nil
            end
            local isMyChar = (charName == Profesjonell.GetPlayerName())
            -- Wider jitter for B response to R requests (Phase A: non-owner 3-8s, owner gets priority)
            local delay
            if isMyChar then
                delay = Profesjonell.GetSyncDelay(0.5, 1.0, true)
            else
                delay = Profesjonell.GetSyncDelay(3.0, 5.0)
            end
            Profesjonell.PendingActions.B[charName] = GetTime() + delay
            Profesjonell.Frame.pendingB[charName] = Profesjonell.PendingActions.B[charName]
            -- Mark as priority if we previously yielded B for this character
            if Profesjonell.YieldedBTo and Profesjonell.YieldedBTo[charName] then
                if not Profesjonell.BPriority then Profesjonell.BPriority = {} end
                Profesjonell.BPriority[charName] = true
                Profesjonell.Debug("Previously yielded B for " .. charName .. " — marking as priority (won't cancel).")
            end
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
                return -- ClearSyncState may start a queued sync; don't fall through
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

                -- Skip sync with peers we recently exhausted retries for
                local exhaustInfo = Profesjonell.ExhaustedPeers[sender]
                if exhaustInfo then
                    local cooldownMinutes = math.min(exhaustInfo.count * 5, 15)
                    local elapsed = GetTime() - exhaustInfo.time
                    if elapsed < cooldownMinutes * 60 then
                        local remaining = math.ceil((cooldownMinutes * 60 - elapsed) / 60)
                        Profesjonell.Debug("Ignoring hash mismatch with " .. sender .. ": sync exhaustion cooldown (" .. remaining .. " min remaining).")
                        return
                    else
                        -- Cooldown expired, allow sync again
                        Profesjonell.ExhaustedPeers[sender] = nil
                    end
                end

                -- If we are already mid-sync with a different peer, queue this one
                if Profesjonell.PendingActions.syncTimer and Profesjonell.Frame.lastSyncPeer
                   and Profesjonell.Frame.lastSyncPeer ~= sender then
                    Profesjonell.Debug("Hash mismatch with " .. sender .. " but already syncing with " .. Profesjonell.Frame.lastSyncPeer .. ". Queuing.")
                    Profesjonell.Frame.nextSyncPeer = sender
                    Profesjonell.Frame.nextSyncHash = remoteHash
                    return
                end

                -- If this is a hash update from the same peer we're syncing with, just update the reference hash
                if Profesjonell.PendingActions.syncTimer and Profesjonell.Frame.lastSyncPeer == sender then
                    Profesjonell.Debug("Updated lastRemoteHash from " .. (Profesjonell.Frame.lastRemoteHash or "nil") .. " to " .. remoteHash .. " for " .. sender)
                    Profesjonell.Frame.lastRemoteHash = remoteHash
                    Profesjonell.Frame.syncRetryCount = 0
                    return
                end

                Profesjonell.Debug("Hash mismatch with " .. sender .. "!")
                -- Only reset retry count if the peer or hash actually changed
                if Profesjonell.Frame.lastSyncPeer ~= sender or Profesjonell.Frame.lastRemoteHash ~= remoteHash then
                    Profesjonell.Frame.syncRetryCount = 0
                end
                Profesjonell.Frame.lastRemoteHash = remoteHash
                Profesjonell.Frame.lastSyncPeer = sender
                -- Deterministic coordinator: alphabetically lowest name coordinates
                local myName = Profesjonell.GetPlayerName()
                if myName < sender then
                    Profesjonell.Debug("Coordinator: I am lower (" .. myName .. " < " .. sender .. "). Scheduling Q.")
                    local qDelay = Profesjonell.GetSyncDelay(0.5, 1.5)
                    Profesjonell.PendingActions.Q = GetTime() + qDelay
                    Profesjonell.Frame.pendingQ = Profesjonell.PendingActions.Q
                    Profesjonell.Frame.pendingQTarget = sender
                else
                    Profesjonell.Debug("Not coordinator: waiting for " .. sender .. " to drive sync.")
                end
                local delay = 20 + math.random() * 10
                if not Profesjonell.PendingActions.syncTimer or GetTime() > Profesjonell.PendingActions.syncTimer then
                    SetSyncTimer(GetTime() + delay)
                end
            else
                -- Hashes match: always clear exhaustion state for this peer
                Profesjonell.ExhaustedPeers[sender] = nil
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
