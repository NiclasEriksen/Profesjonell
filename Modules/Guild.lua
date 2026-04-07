-- Guild.lua
-- Roster and Guild management
-- Ensure the global table exists
Profesjonell = Profesjonell or {}

if Profesjonell.Log then
    Profesjonell.Log("Guild.lua loading")
end

Profesjonell.GuildRosterCache = {}
Profesjonell.GuildRosterRankCache = {}
Profesjonell.LastRosterUpdate = 0
Profesjonell.LastRosterRequest = 0

function Profesjonell.UpdateGuildRosterCache()
    local now = GetTime()
    local guildName = Profesjonell.GetGuildName()

    if not guildName then
        Profesjonell.GuildRosterCache = {}
        Profesjonell.LastRosterUpdate = 0
        return false
    end

    -- If we have data and it's fresh (within 5s), return immediately without any additional work
    if now - Profesjonell.LastRosterUpdate < 5 and next(Profesjonell.GuildRosterCache) then
        return true
    end

    -- Ensure ShowOffline is enabled BEFORE any roster operations
    -- This ensures we always see the full guild roster including offline members
    local showOffline = GetGuildRosterShowOffline()
    if showOffline ~= 1 then
        SetGuildRosterShowOffline(1)
    end

    -- Throttle actual server requests (only request every 60s)
    if now - Profesjonell.LastRosterRequest > 60 then
        Profesjonell.Debug("Requesting GuildRoster from server (with offline members)")
        GuildRoster()
        Profesjonell.LastRosterRequest = now
    end

    -- If we have data and it's somewhat fresh (within 30s), just return true without re-parsing
    if now - Profesjonell.LastRosterUpdate < 30 and next(Profesjonell.GuildRosterCache) then
        return true
    end

    -- Cache is stale, rebuild it

    local num = GetNumGuildMembers()
    if num == 0 then
        if showOffline ~= 1 then
            SetGuildRosterShowOffline(showOffline)
        end
        return false
    end

    Profesjonell.GuildRosterCache = {}
    Profesjonell.GuildRosterRankCache = {}
    for i = 1, num do
        local name, rank, rankIndex, _, class = GetGuildRosterInfo(i)
        if name then
            Profesjonell.GuildRosterCache[name] = class
            Profesjonell.GuildRosterRankCache[name] = { rank = rank, rankIndex = rankIndex }
        end
    end

    if showOffline ~= 1 then
        SetGuildRosterShowOffline(showOffline)
    end

    Profesjonell.LastRosterUpdate = now
    return true
end

function Profesjonell.IsInGuild(name)
    if not Profesjonell.GetGuildName() then return false end
    Profesjonell.UpdateGuildRosterCache()
    return Profesjonell.GuildRosterCache[name] ~= nil
end

function Profesjonell.IsOfficer(name)
    if not Profesjonell.GetGuildName() then return false end
    
    if not Profesjonell.UpdateGuildRosterCache() then
        return false
    end

    local info = Profesjonell.GuildRosterRankCache[name]
    if info then
        if info.rankIndex <= 1 or (info.rank and (string.find(string.lower(info.rank), "officer") or string.find(string.lower(info.rank), "master"))) then
            return true
        end
    end
    
    return false
end
