-- Database.lua
-- Database operations and queries
-- Ensure the global table exists
Profesjonell = Profesjonell or {}

if Profesjonell.Log then
    Profesjonell.Log("Database.lua loading")
end

Profesjonell.PendingReplies = {}
Profesjonell.SyncNewRecipesCount = 0
Profesjonell.SyncSources = {}
Profesjonell.SyncSummaryTimer = nil

function Profesjonell.FindRecipeHolders(name)
    local cleanName = Profesjonell.GetItemNameFromLink(name)
    cleanName = Profesjonell.StripPrefix(cleanName)
    local searchName = string.lower(cleanName)
    
    local words = {}
    local gfindFunc = string.gfind or string.gmatch
    for word in gfindFunc(searchName, "%S+") do
        table.insert(words, word)
    end
    
    local rosterReady = false
    if Profesjonell.UpdateGuildRosterCache then
        rosterReady = Profesjonell.UpdateGuildRosterCache()
    end
    
    local found = {}
    local partialMatches = {}
    local exactMatchName = nil
    
    if ProfesjonellDB then
        for rName, holders in pairs(ProfesjonellDB) do
            local cleanRName = Profesjonell.StripPrefix(rName)
            local lowerRName = string.lower(cleanRName)
            
            local isExact = (lowerRName == searchName)
            local isPartial = false
            if not isExact and table.getn(words) > 0 then
                isPartial = true
                for _, word in ipairs(words) do
                    if not string.find(lowerRName, word, 1, true) then
                        isPartial = false
                        break
                    end
                end
            end
            
            if isExact or isPartial then
                for charName, _ in pairs(holders) do
                    if not rosterReady or (Profesjonell.GuildRosterCache and Profesjonell.GuildRosterCache[charName]) then
                        if isExact then
                            exactMatchName = cleanRName
                            table.insert(found, charName)
                        else
                            if not partialMatches[cleanRName] then partialMatches[cleanRName] = {} end
                            table.insert(partialMatches[cleanRName], charName)
                        end
                    end
                end
            end
        end
    end
    table.sort(found)
    return found, (exactMatchName or cleanName), partialMatches
end

function Profesjonell.WipeDatabaseIfNoGuild()
    local guildName = Profesjonell.GetGuildName()
    if not guildName then
        if Profesjonell.Frame.enteredWorldTime and GetTime() - Profesjonell.Frame.enteredWorldTime > 30 then
            if ProfesjonellDB and next(ProfesjonellDB) then
                ProfesjonellDB = {}
                Profesjonell.Print("You are no longer in a guild. The database has been wiped for security/privacy.")
            end
        end
    end
end

function Profesjonell.GenerateDatabaseHash()
    if Profesjonell.UpdateGuildRosterCache then
        Profesjonell.UpdateGuildRosterCache()
    end
    local guildName = Profesjonell.GetGuildName()
    
    local entries = {}
    if ProfesjonellDB then
        for recipeName, holders in pairs(ProfesjonellDB) do
            for charName, _ in pairs(holders) do
                if not guildName or (Profesjonell.GuildRosterCache and Profesjonell.GuildRosterCache[charName]) then
                    table.insert(entries, recipeName .. ":" .. charName)
                end
            end
        end
    end
    
    if not entries or table.getn(entries) == 0 then
        return "0"
    end

    table.sort(entries)
    
    local hash = 0
    for _, entry in ipairs(entries) do
        for i = 1, string.len(entry) do
            hash = math.mod(hash * 33 + string.byte(entry, i), 4294967296)
        end
    end
    -- Use string.format with %x
    return string.format("%x", hash)
end
