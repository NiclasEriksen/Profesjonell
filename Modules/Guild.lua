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
Profesjonell.PendingShowOfflineRestore = nil -- value to restore after GUILD_ROSTER_UPDATE

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
        -- Defer ShowOffline restore until GUILD_ROSTER_UPDATE fires
        if showOffline ~= 1 then
            Profesjonell.PendingShowOfflineRestore = showOffline
        end
    end

    -- If we have data and it's somewhat fresh (within 30s), just return true without re-parsing
    if now - Profesjonell.LastRosterUpdate < 30 and next(Profesjonell.GuildRosterCache) then
        -- Only restore immediately if we didn't just send a GuildRoster() request above
        if showOffline ~= 1 and not Profesjonell.PendingShowOfflineRestore then
            SetGuildRosterShowOffline(showOffline)
        end
        return true
    end

    -- Cache is stale, rebuild it
    -- Only rebuild if ShowOffline was already enabled; otherwise the API still
    -- returns the old (online-only) list.  The full roster will arrive via
    -- GUILD_ROSTER_UPDATE after the server responds to GuildRoster().
    if showOffline ~= 1 then
        -- We just toggled ShowOffline on and requested a server refresh above.
        -- Return whatever we have (possibly stale) and let OnGuildRosterUpdate
        -- rebuild with the complete roster once the data arrives.
        return next(Profesjonell.GuildRosterCache) ~= nil
    end

    local num = GetNumGuildMembers()
    if num == 0 then
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

    Profesjonell.LastRosterUpdate = now
    return true
end

-- Called when GUILD_ROSTER_UPDATE fires: rebuild cache with fresh data and restore ShowOffline
function Profesjonell.OnGuildRosterUpdate()
    local guildName = Profesjonell.GetGuildName()
    if not guildName then return end

    -- Ensure ShowOffline is enabled so GetNumGuildMembers returns the full roster
    local showOffline = GetGuildRosterShowOffline()
    local pendingRestore = Profesjonell.PendingShowOfflineRestore
    if showOffline ~= 1 and pendingRestore == nil then
        -- ShowOffline was turned off externally; skip this update
    else
        if showOffline ~= 1 then
            -- We still haven't received the full-roster update; re-enable and wait
            SetGuildRosterShowOffline(1)
            return
        end

        local num = GetNumGuildMembers()
        if num > 0 then
            Profesjonell.GuildRosterCache = {}
            Profesjonell.GuildRosterRankCache = {}
            for i = 1, num do
                local name, rank, rankIndex, _, class = GetGuildRosterInfo(i)
                if name then
                    Profesjonell.GuildRosterCache[name] = class
                    Profesjonell.GuildRosterRankCache[name] = { rank = rank, rankIndex = rankIndex }
                end
            end
            Profesjonell.LastRosterUpdate = GetTime()
            Profesjonell.Debug("Guild roster updated: " .. num .. " members (ShowOffline=1)")
        end
    end

    -- Now that we've consumed the roster data, restore the user's ShowOffline preference
    if pendingRestore ~= nil then
        SetGuildRosterShowOffline(pendingRestore)
        Profesjonell.PendingShowOfflineRestore = nil
    end
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
