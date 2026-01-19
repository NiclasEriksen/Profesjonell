-- Profesjonell.lua
-- Main entry point
-- Ensure the global table exists
Profesjonell = Profesjonell or {}

if Profesjonell.Log then
    Profesjonell.Log("Profesjonell.lua loading")
end

-- Logic has been moved to Modules/
-- The .toc file ensures all modules are loaded before this file.