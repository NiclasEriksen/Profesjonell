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

if not ProfesjonellConfig then ProfesjonellConfig = {} end
ProfesjonellConfig.tooltipRecipeCache = ProfesjonellConfig.tooltipRecipeCache or {}
ProfesjonellConfig.tooltipCacheEpoch = ProfesjonellConfig.tooltipCacheEpoch or 0

Profesjonell.TooltipRecipeCache = ProfesjonellConfig.tooltipRecipeCache
Profesjonell.TooltipCacheEpoch = ProfesjonellConfig.tooltipCacheEpoch

local tooltip = CreateFrame("GameTooltip", "ProfesjonellTooltip", nil, "GameTooltipTemplate")
tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

Profesjonell.NameCache = {}
local nameCache = Profesjonell.NameCache
local tooltipLineMax = 30
local fullTypes = {
    s = "spell", spell = "spell",
    e = "enchant", enchant = "enchant",
    i = "item", item = "item"
}

function Profesjonell.InvalidateTooltipCache()
    Profesjonell.TooltipRecipeCache = {}
    ProfesjonellConfig.tooltipRecipeCache = Profesjonell.TooltipRecipeCache
    Profesjonell.NameCache = {}
    nameCache = Profesjonell.NameCache
    Profesjonell.TooltipCacheEpoch = (Profesjonell.TooltipCacheEpoch or 0) + 1
    ProfesjonellConfig.tooltipCacheEpoch = Profesjonell.TooltipCacheEpoch
    if Profesjonell.InvalidateProfessionCache then
        Profesjonell.InvalidateProfessionCache()
    end
end

local function CacheResolvedKeys(cacheKey, keys)
    if not cacheKey then return end
    Profesjonell.TooltipRecipeCache[cacheKey] = {
        keys = keys or {},
        epoch = Profesjonell.TooltipCacheEpoch
    }
end

local function GetCachedKeys(cacheKey)
    local entry = cacheKey and Profesjonell.TooltipRecipeCache[cacheKey]
    if entry and entry.epoch == Profesjonell.TooltipCacheEpoch then
        if entry.keys and table.getn(entry.keys) > 0 then
            return entry.keys
        end
        return nil
    end
    return nil
end

local function NormalizeTooltipLink(link)
    if not link then return nil end
    local _, _, normalized = string.find(link, "|H([^|]+)|h")
    if normalized then return normalized end
    return link
end

local function GetTooltipLinesForLink(link)
    if not link then return nil end
    tooltip:ClearLines()
    local normalized = NormalizeTooltipLink(link)
    if not pcall(tooltip.SetHyperlink, tooltip, normalized) then
        return nil
    end

    local lines = {}
    for i = 1, tooltipLineMax do
        local textObj = _G["ProfesjonellTooltipTextLeft" .. i]
        if not textObj then break end
        local text = textObj:GetText()
        if not text or text == "" then break end
        table.insert(lines, text)
    end
    return lines
end

local function ExtractTeachOrCreateName(lines)
    if not lines then return nil, nil end
    local teachName, createdByName
    for _, text in ipairs(lines) do
        local stripped = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
        stripped = string.gsub(stripped, "|r", "")
        stripped = string.gsub(stripped, "^%s+", "")
        local _, _, useTeach = string.find(stripped, "^Use:%s*Teaches you how to%s+(.+)$")
        if not teachName then
            local _, _, teachA = string.find(stripped, "^Teaches:?%s*(.+)$")
            local _, _, teachB = string.find(stripped, "^Teaches you how to create:?%s*(.+)$")
            teachName = teachA or teachB
        end
        if not teachName and useTeach then
            teachName = useTeach
        end
        if not createdByName then
            local _, _, created = string.find(stripped, "^Created by:?%s*(.+)$")
            createdByName = created
        end
        if teachName and createdByName then break end
    end
    return teachName, createdByName
end

local function NormalizeTeachName(text)
    if not text then return nil end
    local cleaned = string.gsub(text, "%.$", "")
    local lower = string.lower(cleaned)
    if string.find(lower, "^enchant%s+your%s+") then
        local target = string.gsub(cleaned, "^[Ee]nchant%s+[Yy]our%s+", "")
        return "Enchant " .. target
    end
    if string.find(lower, "^enchant%s+") then
        return cleaned
    end
    
    local oldCleaned
    repeat
        oldCleaned = cleaned
        cleaned = string.gsub(cleaned, "^[Cc]reate%s+", "")
        cleaned = string.gsub(cleaned, "^[Mm]ake%s+", "")
        cleaned = string.gsub(cleaned, "^[Cc]raft%s+", "")
        cleaned = string.gsub(cleaned, "^[Cc]ook%s+", "")
        cleaned = string.gsub(cleaned, "^[Aa]n?%s+", "")
        cleaned = string.gsub(cleaned, "^[Ss]ome%s+", "")
    until oldCleaned == cleaned
    
    return cleaned
end

function Profesjonell.FindRecipeKeysByExactName(name)
    if not name then return {} end
    local cleanName = Profesjonell.StripPrefix(name)
    local searchName = string.lower(cleanName)
    local keys = {}
    if ProfesjonellDB then
        for rKey, _ in pairs(ProfesjonellDB) do
            local rName = Profesjonell.GetNameFromKey(rKey)
            local cleanRName = Profesjonell.StripPrefix(rName)
            local lowerRName = string.lower(cleanRName)
            if lowerRName == searchName then
                table.insert(keys, rKey)
            end
        end
    end
    return keys
end

function Profesjonell.BuildKnownByLine(keys)
    if not keys or table.getn(keys) == 0 then return nil end
    if not ProfesjonellDB then return nil end

    local holderSet = {}
    for _, key in ipairs(keys) do
        local holders = ProfesjonellDB[key]
        if holders then
            for charName, _ in pairs(holders) do
                holderSet[charName] = true
            end
        end
    end

    local names = {}
    for charName in pairs(holderSet) do
        table.insert(names, charName)
    end

    local count = table.getn(names)
    if count == 0 then return nil end
    if count > 3 then
        return "Known by " .. count .. " guild members"
    end

    local rosterReady = false
    if Profesjonell.UpdateGuildRosterCache then
        rosterReady = Profesjonell.UpdateGuildRosterCache()
    end

    if rosterReady and Profesjonell.GuildRosterCache then
        local filtered = {}
        for _, name in ipairs(names) do
            if Profesjonell.GuildRosterCache[name] then
                table.insert(filtered, name)
            end
        end
        names = filtered
        count = table.getn(names)
        if count == 0 then return nil end
    end

    table.sort(names)
    return "Known by: " .. table.concat(Profesjonell.ColorizeList(names), ", ")
end

function Profesjonell.ResolveRecipeKeysFromLink(link)
    if not link then return nil end
    local normalizedLink = NormalizeTooltipLink(link)
    local cached = GetCachedKeys(normalizedLink)
    if cached then return cached end

    local key = Profesjonell.GetIDFromLink(normalizedLink)
    if not key then
        CacheResolvedKeys(normalizedLink, nil)
        return nil
    end

    local _, _, type, id = string.find(key, "([^:]+):(%d+)")
    if type == "s" or type == "e" then
        if ProfesjonellDB and ProfesjonellDB[key] then
            CacheResolvedKeys(normalizedLink, {key})
            return {key}
        end
        local altKey
        if type == "s" then altKey = "e:" .. id else altKey = "s:" .. id end
        if ProfesjonellDB and ProfesjonellDB[altKey] then
            CacheResolvedKeys(normalizedLink, {altKey})
            return {altKey}
        end
        CacheResolvedKeys(normalizedLink, nil)
        return nil
    elseif type ~= "i" then
        CacheResolvedKeys(normalizedLink, nil)
        return nil
    end

    if ProfesjonellDB and ProfesjonellDB[key] then
        CacheResolvedKeys(normalizedLink, {key})
        return {key}
    end

    local itemName = Profesjonell.GetItemNameFromLink(link)
    if itemName and (itemName == link or string.find(itemName, "^item:")) then
        local nameFromAPI = GetItemInfo(id)
        if nameFromAPI then
            itemName = nameFromAPI
        end
    end
    local _, _, _, _, _, itemType = GetItemInfo(id)
    local keys = {}

    local isRecipeItem = (itemType == "Recipe")
    if not isRecipeItem and itemName then
        local stripped = Profesjonell.StripPrefix(itemName)
        if stripped and stripped ~= itemName then
            isRecipeItem = true
        end
    end

    if isRecipeItem then
        local lines = GetTooltipLinesForLink(link)
        local teachName = ExtractTeachOrCreateName(lines)
        local normalizedTeach = NormalizeTeachName(teachName)
        local targetName = Profesjonell.GetItemNameFromLink(normalizedTeach or teachName or itemName)
        keys = Profesjonell.FindRecipeKeysByExactName(targetName)
        if not keys or table.getn(keys) == 0 then
            local baseName = Profesjonell.StripPrefix(itemName or "")
            if baseName and baseName ~= "" then
                local variants = { baseName }
                if string.find(baseName, "^Transmute%s") and not string.find(baseName, "^Transmute:%s") then
                    local withColon = string.gsub(baseName, "^Transmute%s+", "Transmute: ")
                    table.insert(variants, withColon)
                end
                for _, variant in ipairs(variants) do
                    keys = Profesjonell.FindRecipeKeysByExactName(variant)
                    if keys and table.getn(keys) > 0 then break end
                end
            end
        end
    else
        local lines = GetTooltipLinesForLink(link)
        local _, createdByName = ExtractTeachOrCreateName(lines)
        if createdByName then
            keys = Profesjonell.FindRecipeKeysByExactName(Profesjonell.GetItemNameFromLink(createdByName))
        else
            local allowTypes = {
                ["Consumable"] = true,
                ["Armor"] = true,
                ["Weapon"] = true,
                ["Trade Goods"] = true
            }
            if itemType and allowTypes[itemType] then
                keys = Profesjonell.FindRecipeKeysByExactName(itemName)
            end
        end
    end

    if keys and table.getn(keys) > 0 then
        CacheResolvedKeys(normalizedLink, keys)
        return keys
    end

    CacheResolvedKeys(normalizedLink, nil)
    return nil
end

function Profesjonell.ResolveRecipeKeysFromTooltip(tooltip)
    if not tooltip or not tooltip.GetName or not Profesjonell.FindRecipeKeysByExactName then return nil end
    local tooltipName = tooltip:GetName()
    if not tooltipName then return nil end

    local lines = {}
    local numLines = tooltip:NumLines() or 0
    for i = 1, numLines do
        local textObj = _G[tooltipName .. "TextLeft" .. i]
        local text = textObj and textObj:GetText()
        if text and text ~= "" then
            table.insert(lines, text)
        end
    end

    if table.getn(lines) == 0 then return nil end

    local teachName, createdByName = ExtractTeachOrCreateName(lines)
    if teachName then
        local normalizedTeach = NormalizeTeachName(teachName)
        local targetName = Profesjonell.GetItemNameFromLink(normalizedTeach or teachName)
        local keys = Profesjonell.FindRecipeKeysByExactName(targetName)
        if keys and table.getn(keys) > 0 then return keys end
    end

    if createdByName then
        local keys = Profesjonell.FindRecipeKeysByExactName(Profesjonell.GetItemNameFromLink(createdByName))
        if keys and table.getn(keys) > 0 then return keys end
    end

    local title = lines[1]
    if not title then return nil end

    local isRelevant = false
    for _, text in ipairs(lines) do
        if string.find(text, "^Reagents:?") or string.find(text, "^Requires") or string.find(text, "^Use:") then
            isRelevant = true
            break
        end
    end

    if not isRelevant then
        local stripped = Profesjonell.StripPrefix(title)
        if stripped and stripped ~= title then
            isRelevant = true
        end
    end

    if not isRelevant then return nil end

    local keys = Profesjonell.FindRecipeKeysByExactName(title)
    if keys and table.getn(keys) > 0 then return keys end

    local strippedTitle = Profesjonell.StripPrefix(title)
    if strippedTitle ~= title then
        keys = Profesjonell.FindRecipeKeysByExactName(strippedTitle)
        if keys and table.getn(keys) > 0 then return keys end
    end

    if string.find(title, "^Transmute%s") and not string.find(title, "^Transmute:%s") then
        local withColon = string.gsub(title, "^Transmute%s+", "Transmute: ")
        keys = Profesjonell.FindRecipeKeysByExactName(withColon)
        if keys and table.getn(keys) > 0 then return keys end
    end

    return nil
end

function Profesjonell.GetNameFromKey(key)
    if nameCache[key] then return nameCache[key] end
    if not string.find(key, ":") then return key end
    
    local _, _, type, id = string.find(key, "([^:]+):(%d+)")
    if not type or not id then return key end

    local nameFound = nil

    -- Handle items
    if type == "item" or type == "i" then
        nameFound = GetItemInfo(id)
    end
    
    if not nameFound then
        -- Handle spells and enchants via tooltip
        local fullType = fullTypes[type] or type
        local toTry = {}
        if fullType == "spell" then
            table.insert(toTry, "spell:" .. id)
        elseif fullType == "enchant" then
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
                if name and name ~= "" and name ~= "Unknown" and not string.find(name, "Retrieving") then 
                    nameFound = name
                    break
                end
            end
        end
    end

    local result = nameFound or ("Unknown (" .. key .. ")")
    if nameFound then
        nameCache[key] = result
    end
    return result
end

function Profesjonell.GetLinkFromKey(key)
    local name = Profesjonell.GetNameFromKey(key)
    if not name or string.find(name, "^Unknown") then return nil end
    
    local _, _, type, id = string.find(key, "([^:]+):(%d+)")
    local fType = fullTypes[type] or type
    if fType == "item" then
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
    elseif fType == "spell" then
        return "|cff71d5ff|Hspell:" .. id .. "|h[" .. name .. "]|h|r"
    elseif fType == "enchant" then
        return "|cff71d5ff|Henchant:" .. id .. "|h[" .. name .. "]|h|r"
    end
    return nil
end

function Profesjonell.FindRecipeHolders(name)
    local foundSet = {}
    local partialMatchesSets = {}
    local exactMatchName = nil
    local exactMatchLink = nil
    local partialLinks = {}
    
    local cleanName = Profesjonell.GetItemNameFromLink(name)
    cleanName = Profesjonell.StripPrefix(cleanName)
    local searchName = string.lower(cleanName)

    local rosterReady = false
    if Profesjonell.UpdateGuildRosterCache then
        rosterReady = Profesjonell.UpdateGuildRosterCache()
    end

    -- If name looks like a link, try to resolve it to specific keys first
    local linkKeys = nil
    if string.find(name, "|H") then
        linkKeys = Profesjonell.ResolveRecipeKeysFromLink(name)
    end

    if linkKeys and table.getn(linkKeys) > 0 then
        for _, key in ipairs(linkKeys) do
            local holders = ProfesjonellDB[key]
            if holders then
                local rName = Profesjonell.GetNameFromKey(key)
                local link = Profesjonell.GetLinkFromKey(key)
                exactMatchName = Profesjonell.StripPrefix(rName)
                exactMatchLink = link
                for charName, _ in pairs(holders) do
                    if not rosterReady or (Profesjonell.GuildRosterCache and Profesjonell.GuildRosterCache[charName]) then
                        foundSet[charName] = true
                    end
                end
            end
        end
    else
        local words = {}
        local gfindFunc = string.gfind or string.gmatch
        for word in gfindFunc(searchName, "%S+") do
            table.insert(words, word)
        end
        
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

function Profesjonell.WipeDatabaseIfGuildChanged()
    local currentGuild = Profesjonell.GetGuildName()
    if not currentGuild then return end

    if not ProfesjonellConfig then ProfesjonellConfig = {} end
    
    if ProfesjonellConfig.lastGuild and ProfesjonellConfig.lastGuild ~= currentGuild then
        if ProfesjonellDB and next(ProfesjonellDB) then
            Profesjonell.Print("Guild changed from " .. ProfesjonellConfig.lastGuild .. " to " .. currentGuild .. ". Wiping recipe database to prevent cross-guild leaking.")
            ProfesjonellDB = {}
            Profesjonell.BroadcastHash()
            if Profesjonell.InvalidateTooltipCache then
                Profesjonell.InvalidateTooltipCache()
            end
        end
    end
    
    ProfesjonellConfig.lastGuild = currentGuild
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
