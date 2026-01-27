-- Init.lua
-- Global table initialization for WoW 1.12.1

-- Ensure the global table exists immediately
if not Profesjonell then
    Profesjonell = {}
end

-- Core properties
Profesjonell.Name = "Profesjonell"
Profesjonell.Version = (GetAddOnMetadata and GetAddOnMetadata("Profesjonell", "Version")) or "0"

-- Ensure sub-tables exist
Profesjonell.PendingReplies = Profesjonell.PendingReplies or {}
Profesjonell.SyncSources = Profesjonell.SyncSources or {}
Profesjonell.GuildRosterCache = Profesjonell.GuildRosterCache or {}

-- Safe Print function
function Profesjonell.Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Profesjonell:|r " .. (msg or "nil"))
    end
end

-- Debug output with burst collapsing
function Profesjonell.Debug(msg)
    if not (ProfesjonellConfig and ProfesjonellConfig.debug and DEFAULT_CHAT_FRAME) then
        return
    end

    local now = GetTime()
    local state = Profesjonell.DebugState or {}
    local window = ProfesjonellConfig.debugBurstWindow or 1.0
    local max = ProfesjonellConfig.debugBurstMax or 4
    local text = msg or "nil"
    local dedupeKey = string.gsub(text, "%s*%(%d+[^)]*%)%s*$", "")

    if state.windowStart and (now - state.windowStart) > window then
        Profesjonell.FlushDebug(true)
    end

    if not state.windowStart then
        state.windowStart = now
        state.queue = {}
        state.suppressed = 0
    end

    local queueLen = table.getn(state.queue)
    if queueLen < max then
        local last = state.queue[queueLen]
        if last and last.key == dedupeKey then
            last.count = last.count + 1
        else
            table.insert(state.queue, { msg = text, count = 1, key = dedupeKey })
        end
    else
        state.suppressed = (state.suppressed or 0) + 1
    end

    state.flushAt = state.windowStart + window
    Profesjonell.DebugState = state
end

function Profesjonell.FlushDebug(force)
    if not (ProfesjonellConfig and ProfesjonellConfig.debug and DEFAULT_CHAT_FRAME) then
        return
    end

    local state = Profesjonell.DebugState
    if not state or not state.windowStart then
        return
    end

    local now = GetTime()
    if not force and (not state.flushAt or now < state.flushAt) then
        return
    end

    local parts = {}
    if state.queue then
        for _, entry in ipairs(state.queue) do
            if entry.count and entry.count > 1 then
                table.insert(parts, entry.msg .. " (x" .. entry.count .. ")")
            else
                table.insert(parts, entry.msg)
            end
        end
    end

    if state.suppressed and state.suppressed > 0 then
        table.insert(parts, "+" .. state.suppressed .. " suppressed")
    end

    if table.getn(parts) > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaaProfesjonell Debug:|r " .. table.concat(parts, " | "))
    end

    state.windowStart = nil
    state.flushAt = nil
    state.queue = {}
    state.suppressed = 0
end

-- Fallback for GetAddOnMetadata (1.12 standard)
function Profesjonell.GetAddOnMetadata(addon, field)
    if GetAddOnMetadata then
        return GetAddOnMetadata(addon, field)
    end
    return nil
end

-- Loading logger
function Profesjonell.Log(msg)
    Profesjonell.Debug("Load: " .. (msg or "nil"))
end

Profesjonell.Log("Init.lua loaded")
