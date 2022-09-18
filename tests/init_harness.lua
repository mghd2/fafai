-- Make various fixes to file paths
-- TODO: Linux requires different fixes
local old_require = require
require = function(path, ...)
    local new_path = path
    while new_path:sub(1, 3) == "../" do
        new_path = new_path:sub(4)
    end
    if new_path:sub(1, 1) == "/" then
        new_path = new_path:sub(2)
    end
    new_path = string.gsub(new_path, "/", "\\")
    return old_require(new_path, unpack(arg))
end
doscript = require  -- Actually it's not the same; it puts the globals from the file into its second param

-- Simplified import function
local imports = {}  -- Map from name (lowercase) to the module
__module_metatable = {
    __index = _G
}
function import(name)
    if imports[name:lower()] then
        return imports[name:lower()]
    end
    local module = {}
    setmetatable(module, __module_metatable)
    imports[name:lower()] = module  -- Need to do this first to prevent infinite recursion
    local ok, msg = pcall(doscript, name, module)
    if not ok then
        WARN(msg)
        error("Error importing '" .. name .. "'", 2)
        imports[name:lower()] = nil
    else
        LOG("Importing module "..name)
        LOG("We got given "..repr(msg))
        LOG("We got meta "..repr(getmetatable(msg)))
    end
    return module
end

LOG = print
WARN = print
SPEW = print

-- Below is lua/globalInit.lua
---@declare-global
-- Copyright © 2005 Gas Powered Games, Inc.  All rights reserved.
--
-- This is the top-level lua initialization file. It is run at initialization time
-- to set up all lua state.

-- Uncomment this to turn on allocation tracking, so that memreport() in /lua/system/profile.lua
-- does something useful.
-- debug.trackallocations(true)

-- Set up global diskwatch table (you can add callbacks to it to be notified of disk changes)
__diskwatch = {}

-- Set up custom Lua weirdness
--doscript '/lua/system/config.lua'

-- Take the important bits from /lua/system/config.lua; the rest is unnecessary or segfaults
--local globalsmeta = {
--    __index = function(table, key)
--        error("access to nonexistent global variable "..repr(key),2)
--    end
--}
--setmetatable(_G, globalsmeta)

--function iscallable(f)
--    local tt = type(f)
--    if tt == 'function' or tt == 'cfunction' then
--        return f
--    end
--    if tt == 'table' and getmetatable(f).__call then
--        return f
--    end
--end

-- Load system modules
-- Skip out using the complicated import function because:
-- - it struggles with case sensitivity on Linux, and
-- - it messes around with various globals this lua doesn't have.
--doscript '/lua/system/import.lua'
function notimport(name)
    local trimmed_name = name
    if name:sub(1, 1) == '/' then
        trimmed_name = trimmed_name:sub(2)
    end
    local module = {}
    if false then
        -- This code was an attempt to make things work on Linux, but it failed
        -- Unfortunately many files in fa/ have incorrect import cases
        local handle = io.popen("find . -type f -iwholename */fa/"..trimmed_name)
        local found_name = handle:read("*a")
        if found_name != "" then
            LOG("Found case name "..found_name..".")
            trimmed_name = found_name:sub(6)  -- Remove leading "./fa/"
            LOG("Fixed case to "..trimmed_name)
        end
        handle:close()
    end

    LOG("1st try reading "..trimmed_name)
    local ok, msg = pcall(doscript, trimmed_name, module)
    if not ok then
        -- we failed: report back
        WARN(msg)
        error("Error importing '" .. trimmed_name .. "'", 2)
    end
    return module
end

doscript '/lua/system/utils.lua'
doscript '/lua/system/repr.lua'
doscript '/lua/system/class.lua'
doscript '/lua/system/trashbag.lua'
--doscript '/lua/system/Localization.lua'
doscript '/lua/system/MultiEvent.lua'
doscript '/lua/system/collapse.lua'

-- flag used to detect duplicates
InitialRegistration = true

-- load buff blueprints
doscript '/lua/system/BuffBlueprints.lua'

-- Commenting out from here, because I'm having trouble with import

--import('/lua/sim/BuffDefinitions.lua')

-- load AI builder systems
--doscript '/lua/system/GlobalPlatoonTemplate.lua'
--doscript '/lua/system/GlobalBuilderTemplate.lua'
--doscript '/lua/system/GlobalBuilderGroup.lua'
--doscript '/lua/system/GlobalBaseTemplate.lua'

InitialRegistration = false

-- Classes exported from the engine are in the 'moho' table. But they aren't full
-- classes yet, just lists of exported methods and base classes. Turn them into
-- real classes.
--for name,cclass in moho do
--    ConvertCClassToLuaSimplifiedClass(cclass)
--end

-- Import the C function prototypes (although they don't do anything)
import('/engine/Core.lua')
moho = {}
moho.entity_methods = import('/engine/Sim/Entity.lua')
--moho.aibrain_methods = 


-- Create the ScenarioInfo
ScenarioInfo = {
    Options = {},


}

-- All the categories I could easily find in the repo
local next_category = 1
local known_categories = {
    "ABILITYBUTTON",
    "AEON",
    "AIR",
    "AIRSTAGINGPLATFORM",
    "ALLPROJECTILES",
    "ALLUNITS",
    "ANTIAIR",
    "ANTIMISSILE",
    "ANTINAVY",
    "ARTILLERY",
    "BATTLESHIP",
    "BOMBER",
    "BOT",
    "BUBBLESHIELDSPILLOVERCHECK",
    "CARRIER",
    "COMMAND",
    "CONSTRUCTION",
    "CONSTRUCTIONSORTDOWN",
    "COUNTERINTELLIGENCE",
    "CRUISER",
    "CYBRAN",
    "DEFENSE",
    "DEFENSIVEBOAT",
    "DESTROYER",
    "DIRECTFIRE",
    "DRAGBUILD",
    "DUMMYUNIT",
    "ECONOMIC",
    "ENERGYPRODUCTION",
    "ENGINEER",
    "ENGINEERSTATION",
    "EXPERIMENTAL",
    "FACTORY",
    "FIELDENGINEER",
    "FRIGATE",
    "GATE",
    "GROUNDATTACK",
    "HYDROCARBON",
    "INDIRECTFIRE",
    "INSIGNIFICANTUNIT",
    "INTELLIGENCE",
    "LAND",
    "LIGHTBOAT",
    "MASSEXTRACTION",
    "MASSFABRICATION",
    "MASSPRODUCTION",
    "MISSILE",
    "MOBILE",
    "MOBILESONAR",
    "NAVAL",
    "NAVALCARRIER",
    "NEEDMOBILEBUILD",
    "NOMADS",
    "NUKE",
    "NUKESUB",
    "OMNI",
    "OPERATION",
    "OPTICS",
    "ORBITALSYSTEM",
    "OVERLAYCOUNTERINTEL",
    "OVERLAYINDIRECTFIRE",
    "OVERLAYMISC",
    "OVERLAYOMNI",
    "OVERLAYRADAR",
    "OVERLAYSONAR",
    "POD",
    "PODSTAGINGPLATFORM",
    "PROJECTILE",
    "RADAR",
    "REPAIR",
    "SATELLITE",
    "SCOUT",
    "SERAPHIM",
    "SHIELD",
    "SHOWQUEUE",
    "SILO",
    "SNIPER",
    "SONAR",
    "SORTCONSTRUCTION",
    "SORTDEFENSE",
    "SORTECONOMY",
    "SORTINTEL",
    "SORTOTHER",
    "SORTSTRATEGIC",
    "STATIONASSISTPOD",
    "STRATEGIC",
    "STRUCTURE",
    "SUBCOMMANDER",
    "SUBMERSIBLE",
    "SUPPORTFACTORY",
    "TACTICALMISSILEPLATFORM",
    "TORPEDO",
    "TRANSPORTATION",
    "TRANSPORTFOCUS",
    "UEF",
    "UNSELECTABLE",
    "UNSPAWNABLE",
    "UNTARGETABLE",
    "VOLATILE",
    "WALL",
}
categories = {}
for i, c in known_categories do
    categories[c] = math.pow(i, 2)
end
