-- Utils.lua
-- Helper functions
-- Ensure the global table exists
Profesjonell = Profesjonell or {}

if Profesjonell.Log then
    Profesjonell.Log("Utils.lua loading")
end

function Profesjonell.GetPlayerName()
    return UnitName("player")
end

function Profesjonell.GetGuildName()
    return GetGuildInfo("player")
end

function Profesjonell.StripPrefix(s)
    if not s then return nil end
    local prefixes = {"Recipe: ", "Pattern: ", "Plans: ", "Schematic: ", "Manual: ", "Formula: "}
    local lowerS = string.lower(s)
    for _, p in ipairs(prefixes) do
        local lowerP = string.lower(p)
        if string.sub(lowerS, 1, string.len(lowerP)) == lowerP then
            return string.sub(s, string.len(p) + 1)
        end
    end
    return s
end

function Profesjonell.GetItemNameFromLink(link)
    if not link then return nil end
    local _, _, name = string.find(link, "%[(.+)%]")
    return name or link
end

function Profesjonell.GetIDFromLink(link)
    if not link then return nil end
    local _, _, type, id = string.find(link, "|H(%a+):(%d+)")
    if type and id then
        if type == "item" then type = "i"
        elseif type == "spell" then type = "s"
        elseif type == "enchant" then type = "e"
        end
        return type .. ":" .. id
    end
    return nil
end

function Profesjonell.CompareVersions(v1, v2)
    local _, _, maj1, min1 = string.find(v1 or "0", "(%d+)%.(%d+)")
    local _, _, maj2, min2 = string.find(v2 or "0", "(%d+)%.(%d+)")
    
    maj1, min1 = tonumber(maj1 or v1 or 0), tonumber(min1 or 0)
    maj2, min2 = tonumber(maj2 or v2 or 0), tonumber(min2 or 0)
    
    if maj1 > maj2 then return 1 end
    if maj1 < maj2 then return -1 end
    if min1 > min2 then return 1 end
    if min1 < min2 then return -1 end
    return 0
end

local classColors = {}
function Profesjonell.GetClassColor(className)
    if not next(classColors) and RAID_CLASS_COLORS then
        for class, color in pairs(RAID_CLASS_COLORS) do
            local localized = getglobal(class)
            if localized then
                classColors[localized] = string.format("%02x%02x%02x", color.r*255, color.g*255, color.b*255)
            end
        end
        -- Fallback for common English names if localized globals aren't what we expect
        local fallbacks = {
            ["Warrior"] = "C79C6E", ["Mage"] = "69CCF0", ["Rogue"] = "FFF569",
            ["Druid"] = "FF7D0A", ["Hunter"] = "ABD473", ["Paladin"] = "F58CBA",
            ["Priest"] = "FFFFFF", ["Shaman"] = "0070DE", ["Warlock"] = "9482C9"
        }
        for k, v in pairs(fallbacks) do
            if not classColors[k] then classColors[k] = v end
        end
    end
    return classColors[className]
end

function Profesjonell.ColorizeName(name)
    if not name then return nil end
    local class = Profesjonell.GuildRosterCache[name]
    if class then
        local color = Profesjonell.GetClassColor(class)
        if color then
            return "|cff" .. color .. name .. "|r"
        end
    end
    return name
end

function Profesjonell.ColorizeList(list)
    if not list then return nil end
    local colorized = {}
    for _, name in ipairs(list) do
        table.insert(colorized, Profesjonell.ColorizeName(name))
    end
    return colorized
end
