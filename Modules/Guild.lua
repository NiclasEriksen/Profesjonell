-- Guild.lua
-- Roster and Guild management
-- Ensure the global table exists
Profesjonell = Profesjonell or {}

if Profesjonell.Log then
    Profesjonell.Log("Guild.lua loading")
end

Profesjonell.GuildRosterCache = {}
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

    -- Throttle actual server requests
    if now - Profesjonell.LastRosterRequest > 60 then
        Profesjonell.Debug("Requesting GuildRoster from server")
        GuildRoster()
        Profesjonell.LastRosterRequest = now
    end
    
    -- If we have data and it's fresh (within 30s), just return true
    if now - Profesjonell.LastRosterUpdate < 30 and next(Profesjonell.GuildRosterCache) then
        return true
    end

    local showOffline = GetGuildRosterShowOffline()
    if not showOffline then
        SetGuildRosterShowOffline(1)
    end

    local num = GetNumGuildMembers()
    if num == 0 then
        if not showOffline then
            SetGuildRosterShowOffline(0)
        end
        return false
    end

    Profesjonell.GuildRosterCache = {}
    for i = 1, num do
        local name, _, _, _, class = GetGuildRosterInfo(i)
        if name then
            Profesjonell.GuildRosterCache[name] = class
        end
    end

    if not showOffline then
        SetGuildRosterShowOffline(0)
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
    
    local showOffline = GetGuildRosterShowOffline()
    if not showOffline then
        SetGuildRosterShowOffline(1)
    end
    
    local isOfficer = false
    for i = 1, GetNumGuildMembers() do
        local gName, rank, rankIndex = GetGuildRosterInfo(i)
        if gName == name then
            if rankIndex <= 1 or (rank and (string.find(string.lower(rank), "officer") or string.find(string.lower(rank), "master"))) then
                isOfficer = true
            end
            break
        end
    end
    
    if not showOffline then
        SetGuildRosterShowOffline(0)
    end
    
    return isOfficer
end
