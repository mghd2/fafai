local Targets = import('/mods/TestAI/lua/Map/Targets.lua')
-- TODO: ^^ Trying a new way of splitting the class between files
local Threat = import('/mods/TestAI/lua/Map/Threat.lua')

local NewMap = import('/mods/TestAI/lua/Map/Map.lua')

local RandomFloat = import('/lua/utilities.lua').GetRandomFloat

local DEFAULT_BORDER = 4
local PLAYABLE_AREA = {}

local TESTAIMARKERS = {}

GameMap = Class({
    New = function(self, brain)
        self.brain = brain
        self.markers = {}
        for i, v in TESTAIMARKERS do
            table.insert(self.markers, {Marker=v, State='Unclaimed', ClaimTick=0, Index=i})
        end
        LOG("Created markers "..repr(self.markers))

        self.enemy_bases = {}  -- List of {x, y, z}
        for _, a in ListArmies() do
            local b = GetArmyBrain(a)
            if b and IsEnemy(b:GetArmyIndex(), brain:GetArmyIndex()) then
                local e_x, e_z = b:GetArmyStartPos()
                local e_y = GetTerrainHeight(e_x, e_z)
                table.insert(self.enemy_bases, {e_x, e_y, e_z})
            end
        end
        local our_x, our_z = brain:GetArmyStartPos()
        local our_y = GetTerrainHeight(our_x, our_z)
        self.our_base = {our_x, our_y, our_z}
        
        self.observed_threats = {}  -- Indexed by unit id

        self.target_radius = (PLAYABLE_AREA[3] + PLAYABLE_AREA[4] - PLAYABLE_AREA[1] - PLAYABLE_AREA[2]) / 4
        self.old_targets = {}  -- DOUBLE ARRAY [i] then [j]
        -- Each Target is: Position={x, y, z}
        --                 Threat={Location=a, Enemies=b}  -- Enemies gets updated regularly
        --                 Control=Ally|Enemy|Neutral
        --                 LocationValueModifier=0.3 to 1.5 ish.
        --                 RelativeDistance=0 to 1.  0 means our base, 1 means enemy; constant gradient along the line between

        self.targets = {}
        Targets.NewTargets(self)

        self.threat = Threat.ThreatMap()
        self.threat:New(brain, PLAYABLE_AREA)

        -- Give the new map a reference to the threatmap for now
        self.new_map = NewMap.GetMap(brain)
        self.new_map.threat_map = self.threat

    end,

    -- TODO: Args
    GetAttackPath = function(self)
        return Targets.GetAttackPath(self)
    end,

    OurBase = function(self)
        return self.our_base
    end,

    EnemyBases = function(self)
        return self.enemy_bases
    end,

    DistanceBetweenPoints = function(self, source, dest, layer, threatLimit, approachDistance)
        -- TODO: Consider actual travel distance, and cache common results / optimize a lot
        return VDist2(source[1], source[3], dest[1], dest[3])
    end,

    -- How to maintain and spread threat around?
    -- Challenge is realizing threat in place B came from A.
    -- Is it practical to just set up such good scouting that we can work with what's true without moving threat around?
    -- Probably need to record the source sightings for threat
    -- Need to properly count kills and such
    -- Probably worth building a cheating version (basically omni), so I can log errors and such

    -- If we detect a structure, then obviously it doesn't move
    -- 


    -- Intel gathering: what's fair / useful?
    -- GetUnitsAroundPoint(..., 'Enemy')
    --    - Only returns units we have a blip for, but gives full data on that unit (not fair).
    --    - May also need to be filtered down (e.g. is done, not dead and such)
    --    - Not sure what happens with navy / subs; probably blip based still
    -- GetBlip() is probably the answer
    --    - Yes, this is exactly right.
    --    - IsOnRadar() doesn't seem that useful, but I guess it's something.
    --    - IsSeenEver() tells if we've seen it, so I guess we can just inspect the units actual type.
    --    - Is there a way I can look at the unit type (plane / structure / tank)?  That seems fair.
    --    - Don't understand jamming though: when the jammed unit is near the edge of radar blips appear; some aren't even in radar range.
    --    - Even with jamming disabled, the unit doesn't appear until it's a little way inside radar
    --    - When we lose previous radar, we lose the blip, even if it's a structure (that's probably still there)
    --    - Can call GetBlueprint().BlueprintId on a blip, but that returns exactly what it is.
    --    - It's fair to work out if it's structure, land, air or navy though (different icons)
    -- Do want to find a "cheating" function, for comparison purposes (report differences to log)

    -- From the blueprint, Weapon is an array of tables.  Those contain MaxRadius and MinRadius.

    -- - From the blueprint, can look at LayerCategory (=LAND).  Categories (list) and CategoriesHash (map->true) also available (block caps e.g. TECH1).

    --    - Looking at units in the game UI; radar doesn't seem perfectly consistent: it sometimes doesn't show units until a bit too late...


    -- What's an efficient way to calculate threat?
    -- I'll have sources of threat marked at a location.  There may be up to a couple of thousand such locations.
    -- Could break the map into chunks and calculate for each one?  Might be best


})


function BeginSession()
    -- TODO: Detect if a map is required (inc versioning?)
    PLAYABLE_AREA = { DEFAULT_BORDER, DEFAULT_BORDER, ScenarioInfo.size[1], ScenarioInfo.size[2] }
    NewMap.BeginSession()
end

-- Create map if needed
function GetMap(brain)
    if not brain.TestAIMapOld then
        brain.TestAIMapOld = GameMap()
        brain.TestAIMapOld:New(brain)
    end
    return brain.TestAIMapOld
end

function CreateMarker(t, x, y, z, size)
    LOG("Recording marker "..repr(t).." at "..x..","..y..","..z)
    table.insert(TESTAIMARKERS, {type=t, position={x, y, z}})
    NewMap.CreateMarker(t, x, y, z, size)
end

-- I'm unclear what it is that makes this necessary: it's from DilliDalli
function SetPlayableRect(x0, z0, x1, z1)
    -- "Fields of Isis is a bad map, I hate to be the one who has to say it." - Softles
    PLAYABLE_AREA = {x0, z0, x1, z1}
    NewMap.SetPlayableRect(x0, z0, x1, z1)
end

--[[
FindMostAdjacentPlaceForSize(withinBuildRangeOfStart, adjacentToMexes, size=4)
    -- ACU wants to build first factory (size 4) with best adjacency
    mexes = [{x, z}] -- Only the ones within buildrange + factorySize
    -- For a mex to be adjacent, it needs X1 = X2 +-4 (Xn being X of mex n) and Z1 close to Z2; or the same with X/Z flipped; and also the spot for the factory be buildable
    -- Realistically, it's unusual for a map to allow more than 2 adjacent; so probably OK to limit to that
    mexesXmod4 = [] -- mex X coord mod 4: to be double adjacent to a factory must be multiple in one group for this or Zmod4
    mexesZmod4 = []
    mexesXrem4
    mexesZrem4
    -- To have double adjacency we need either 2 in mexesXmod4[k] or 2 in mexesZmod4[k]; with the other value being within 3
    -- Might be smarter to just walk through all the spots in build range - it's not _that_ many...

]]