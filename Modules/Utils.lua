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
