-- Database.lua
-- Database operations and queries
-- Ensure the global table exists
Profesjonell = Profesjonell or {}

if Profesjonell.Log then
    Profesjonell.Log("Database.lua loading")
end

Profesjonell.PendingReplies = Profesjonell.PendingReplies or {}
Profesjonell.SyncNewRecipesCount = Profesjonell.SyncNewRecipesCount or 0
Profesjonell.SyncSources = Profesjonell.SyncSources or {}
Profesjonell.SyncSummaryTimer = Profesjonell.SyncSummaryTimer or nil

local tooltip = CreateFrame("GameTooltip", "ProfesjonellTooltip", nil, "GameTooltipTemplate")
tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local nameCache = {}

function Profesjonell.GetNameFromKey(key)
    if nameCache[key] then return nameCache[key] end
    if not string.find(key, ":") then return key end
    
    local _, _, type, id = string.find(key, "([^:]+):(%d+)")
    if not type or not id then return key end

    -- Handle items
    if type == "item" or type == "i" then
        local name = GetItemInfo(id)
        if name then 
            nameCache[key] = name
            return name 
        end
    end
    
    -- Handle spells and enchants
    local fullTypes = {
        s = "spell",
        spell = "spell",
        e = "enchant",
        enchant = "enchant"
    }
    local fullType = fullTypes[type] or type
    
    local toTry = {}
    if fullType == "spell" then
        table.insert(toTry, "spell:" .. id)
    elseif fullType == "enchant" then
        -- Enchants in 1.12 are often spells, try both
        table.insert(toTry, "spell:" .. id)
        table.insert(toTry, "enchant:" .. id)
    else
        table.insert(toTry, fullType .. ":" .. id)
    end

    for _, link in ipairs(toTry) do
        tooltip:ClearLines()
        if pcall(tooltip.SetHyperlink, tooltip, link) then
            local textObj = _G["ProfesjonellTooltipTextLeft1"]
            local name = textObj and textObj:GetText()
            if name and name ~= "" and name ~= "Unknown" then 
                nameCache[key] = name
                return name 
            end
        end
    end
    
    return "Unknown (" .. key .. ")"
end

function Profesjonell.GetLinkFromKey(key)
    local name = Profesjonell.GetNameFromKey(key)
    if not name or string.find(name, "^Unknown") then return nil end
    
    local _, _, type, id = string.find(key, "([^:]+):(%d+)")
    if type == "i" or type == "item" then
        local nameFromAPI, link, rarity = GetItemInfo(id)
        if link then 
            if string.find(link, "|H") then
                return link
            else
                -- Raw item string like "item:7078:0:0:0", wrap it
                local color = "|cffffffff"
                if rarity and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[rarity] then
                    color = ITEM_QUALITY_COLORS[rarity].hex
                end
                return color .. "|H" .. link .. "|h[" .. (nameFromAPI or name) .. "]|h|r"
            end
        end
        -- Fallback construction if link is not yet in cache
        -- Vanilla 1.12 uses 3 segments: item:id:enchant:suffix:unique
        return "|cffffffff|Hitem:" .. id .. ":0:0:0|h[" .. name .. "]|h|r"
    elseif type == "s" or type == "spell" then
        return "|cff71d5ff|Hspell:" .. id .. "|h[" .. name .. "]|h|r"
    elseif type == "e" or type == "enchant" then
        return "|cff71d5ff|Henchant:" .. id .. "|h[" .. name .. "]|h|r"
    end
    return nil
end

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
    
    local foundSet = {}
    local partialMatchesSets = {}
    local exactMatchName = nil
    local exactMatchLink = nil
    local partialLinks = {}
    
    if ProfesjonellDB then
        for rKey, holders in pairs(ProfesjonellDB) do
            local rName = Profesjonell.GetNameFromKey(rKey)
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
                local link = Profesjonell.GetLinkFromKey(rKey)
                for charName, _ in pairs(holders) do
                    if not rosterReady or (Profesjonell.GuildRosterCache and Profesjonell.GuildRosterCache[charName]) then
                        if isExact then
                            exactMatchName = cleanRName
                            exactMatchLink = link
                            foundSet[charName] = true
                        else
                            if not partialMatchesSets[cleanRName] then partialMatchesSets[cleanRName] = {} end
                            partialLinks[cleanRName] = link
                            partialMatchesSets[cleanRName][charName] = true
                        end
                    end
                end
            end
        end
    end

    local found = {}
    for charName in pairs(foundSet) do
        table.insert(found, charName)
    end
    table.sort(found)

    local partialMatches = {}
    for rName, charSet in pairs(partialMatchesSets) do
        partialMatches[rName] = {}
        for charName in pairs(charSet) do
            table.insert(partialMatches[rName], charName)
        end
        table.sort(partialMatches[rName])
    end

    return found, (exactMatchName or cleanName), partialMatches, exactMatchLink, partialLinks
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
    local charHashes = Profesjonell.GenerateCharacterHashes()
    if not charHashes then return nil end

    local sortedChars = {}
    for charName, _ in pairs(charHashes) do
        table.insert(sortedChars, charName)
    end
    table.sort(sortedChars)
    
    local hash = 0
    for _, charName in ipairs(sortedChars) do
        local charHashStr = charName .. ":" .. charHashes[charName]
        for i = 1, string.len(charHashStr) do
            hash = math.mod(hash * 33 + string.byte(charHashStr, i), 4294967296)
        end
    end
    return string.format("%x", hash)
end

function Profesjonell.GenerateCharacterHashes()
    if not Profesjonell.UpdateGuildRosterCache or not Profesjonell.UpdateGuildRosterCache() then
        return nil
    end

    local charEntries = {}
    if ProfesjonellDB then
        for key, holders in pairs(ProfesjonellDB) do
            for charName, _ in pairs(holders) do
                -- Only include characters currently in the guild to ensure sync consistency
                if Profesjonell.GuildRosterCache[charName] then
                    if not charEntries[charName] then charEntries[charName] = {} end
                    table.insert(charEntries[charName], key)
                end
            end
        end
    end
    
    local results = {}
    for charName, entries in pairs(charEntries) do
        table.sort(entries)
        local hash = 0
        for _, entry in ipairs(entries) do
            for i = 1, string.len(entry) do
                hash = math.mod(hash * 33 + string.byte(entry, i), 4294967296)
            end
        end
        results[charName] = string.format("%x", hash)
    end
    return results
end

function Profesjonell.MigrateDatabase()
    if not ProfesjonellDB then return end
    Profesjonell.Debug("Starting database migration...")
    local migratedCount = 0
    local removedCount = 0
    
    -- 1. Convert old prefixes to new ones (item: -> i:, spell: -> s:, enchant: -> e:)
    local oldKeys = {}
    for key, _ in pairs(ProfesjonellDB) do
        if string.find(key, ":") then
            local _, _, type, id = string.find(key, "([^:]+):(%d+)")
            if type == "item" or type == "spell" or type == "enchant" then
                table.insert(oldKeys, key)
            end
        end
    end
    
    for _, oldKey in ipairs(oldKeys) do
        local _, _, type, id = string.find(oldKey, "([^:]+):(%d+)")
        local newType = type
        if type == "item" then newType = "i"
        elseif type == "spell" then newType = "s"
        elseif type == "enchant" then newType = "e"
        end
        local newKey = newType .. ":" .. id
        
        if newKey ~= oldKey then
            Profesjonell.Debug("Converting prefix: " .. oldKey .. " -> " .. newKey)
            if not ProfesjonellDB[newKey] then ProfesjonellDB[newKey] = {} end
            for charName, _ in pairs(ProfesjonellDB[oldKey]) do
                ProfesjonellDB[newKey][charName] = true
            end
            ProfesjonellDB[oldKey] = nil
            migratedCount = migratedCount + 1
        end
    end

    -- 2. Use existing ID entries to purge name entries
    local idToName = {}
    for key, _ in pairs(ProfesjonellDB) do
        if string.find(key, ":") then
            local name = Profesjonell.GetNameFromKey(key)
            if name and not string.find(name, "^Unknown") then
                idToName[key] = name
            end
        end
    end
    
    for id, name in pairs(idToName) do
        if ProfesjonellDB[name] then
            Profesjonell.Debug("Merging name entry '" .. name .. "' into ID '" .. id .. "'")
            for charName, _ in pairs(ProfesjonellDB[name]) do
                if not ProfesjonellDB[id] then ProfesjonellDB[id] = {} end
                ProfesjonellDB[id][charName] = true
            end
            ProfesjonellDB[name] = nil
            migratedCount = migratedCount + 1
        end
    end
    
    -- 3. Try to resolve remaining name entries
    local keysToMigrate = {}
    for key, _ in pairs(ProfesjonellDB) do
        if not string.find(key, ":") then
            table.insert(keysToMigrate, key)
        end
    end
    
    for _, name in ipairs(keysToMigrate) do
        local _, link = GetItemInfo(name)
        if link then
            local id = Profesjonell.GetIDFromLink(link)
            if id then
                Profesjonell.Debug("Resolved name '" .. name .. "' to ID '" .. id .. "'")
                if not ProfesjonellDB[id] then ProfesjonellDB[id] = {} end
                for charName, _ in pairs(ProfesjonellDB[name]) do
                    ProfesjonellDB[id][charName] = true
                end
                ProfesjonellDB[name] = nil
                migratedCount = migratedCount + 1
            else
                Profesjonell.Debug("Could not get ID for '" .. name .. "', removing.")
                ProfesjonellDB[name] = nil
                removedCount = removedCount + 1
            end
        else
            -- If we can't resolve it now, we remove it to ensure only IDs remain
            Profesjonell.Debug("Could not resolve name '" .. name .. "' to ID, removing.")
            ProfesjonellDB[name] = nil
            removedCount = removedCount + 1
        end
    end

    -- 4. Final strict sweep: remove anything that doesn't look like a valid ID
    local finalKeys = {}
    for key, _ in pairs(ProfesjonellDB) do
        table.insert(finalKeys, key)
    end
    for _, key in ipairs(finalKeys) do
        if not string.find(key, ":") or not string.find(key, "^%a+:%d+$") then
            Profesjonell.Debug("Final sweep: Removing invalid key '" .. key .. "'")
            ProfesjonellDB[key] = nil
            removedCount = removedCount + 1
        end
    end

    if migratedCount > 0 or removedCount > 0 then
        Profesjonell.Print("Database migration complete.")
        if migratedCount > 0 then
            Profesjonell.Print("Merged/Converted " .. migratedCount .. " entries to ID-based storage.")
        end
        if removedCount > 0 then
            Profesjonell.Print("Removed " .. removedCount .. " unresolvable name-based entries.")
        end
    end
end
