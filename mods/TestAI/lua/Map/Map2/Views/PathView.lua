-- Design for Map v2

-- Pathing should be shared between players (or even different AIs)
-- Marker generation: maybe there should be a few options?

local LAND = 1
local AMPHIB = 2
local NAVY = 3
local HOVER = 4
local AIR = 5

local CONN = 5  -- Added to the zone to get the connectivity list

local pathLayer = nil

-- TODO: How to merge with the Class metatable
local pathMeta = {
    __index = function(map, x, z)
        -- TODO: Set this up in init?

    end
}

---@class PathView
---@field SomeUserField string
PathView = ClassSimple({
    __init = function(self, map)
        -- Initialize AI specific data
        self.markers = {}

        -- Use pre-initialized shared data
        if pathLayer then
           self.grid1 = pathLayer.grid1
           self.grid5 = pathLayer.grid5
           self.grid25 = pathLayer.grid25
           return
        end

        -- Can I use a bitmask for layers?  We have XOR only; so maybe if I store impassibility
        -- I'm currently storing path, conn and zone
        -- I could use a zone of 0 to represent impathable

        local startTime = GetSystemTimeSecondsOnlyForProfileUse()

        -- Initialize shared data
        self.grid1 = {}  -- [floor(x)][floor(z)] = {<zones or 0>, <{<connected grids} by zone>}
        self.grid5 = {}  -- [floor(x/5)][floor(z/5)] = {}
        self.grid25 = {}  -- [floor(x/25)][floor(z/25)] = {}

        -- Path nodes may be sparser
        -- If I do only "edge" nodes (less than 4 neighbors); and use approximate contraction hierarchies in open spaces?
        self.pathNodes25 = {}

        self:calcGrid1x1()

        -- Save shared data (and AI specific data, but that just won't be copied)
        pathLayer = self

        local endTime = GetSystemTimeSecondsOnlyForProfileUse()
        LOG("Pathing pre-calculations completed in "..(endTime - startTime))
    end,

    calcGrid1x1 = function(self)
        -- Pathability conditions based on those by Balthazar; except for hover which I've made up
        local max, abs = math.max, math.abs
        local GTH, GSH, GTT = GetTerrainHeight, GetSurfaceHeight, GetTerrainType
        local function canPathSlope(x,z,t) local a,b,d = GTH(x-1,z-1),GTH(x-1,z),GTH(x,z-1) return max(abs(a-b), abs(b-t), abs(t-d), abs(d-a)) <= 0.75 end
        -- This^^ makes 4x as many GTH calls as needed
        -- Also is it right to use -1?  If we're going to use floor to map positions to this grid shouldn't it be +1?
        local function canPathTerrain(x,z) local t = GTT(x,z) return t ~= 'Dirt09' and t ~= 'Lava01' end

        local slopeMap = {}



    end,

    getGrid1x1 = function(self, position, layer)

    end,

    -- Get the nearest marker to a position on a given layer
    GetNearestMarker = function(self, position, layer)

    end,

    ---@param self PathLayer
    ---@param source table The source, as a position {x, _, z}
    ---@param destination table The destination, as a position {x, _, z}
    ---@param layer integer The layer to path on: one of LAND, AMPHIB, NAVY, HOVER, AIR
    ---@param pathWide boolean (Optional) require wide pathing clearance: useful for large units or groups
    ---@return number
    GetApproxDistanceTo = function(self, source, destination, layer, pathWide)

    end,

    GetPathTo = function(self, source, destination, layer, pathWide)

    end,

    CanPathTo = function(self, source, destination, layer, pathWide)
        if pathWide then
            return false
        end
        local sourceZone = self:getGrid1x1(source)[layer]
        local destZone = self:getGrid1x1(destination)[layer]
        return (sourceZone ~= 0) and (sourceZone == destZone)
    end,

    -- How to build pathing that considers threat (or other things)?
    -- Or build an expansion path?

    GetExpansionPath = function(self, source, layer, valueFn, filterFn, maxLength)

    end,

    -- Can you get close enough to shoot or build somewhere?
    CanPathToWithin = function(self, source, destination, layer, pathWide, range, arc)

    end,



})

-- Pathing calculation:
-- Want to be able to do it fast: say I pre-compute paths between all the markers?
-- Then do a search which is source to nearby marker (maybe consider 5x5 markers centred on the source),
-- to marker nearest the dest?  Can I do a kinda bidirectional search considering 5x5 at both ends?
-- Maybe that's too much (40x40 markers means 2.5M paths)

-- Say I do contraction hierarchies on a 40x40 grid on a flat map - is that terrible?
-- We pick a node to contract that minimizes the number of added edges.
-- Say we pick an edge in the middle of stuff: we remove the 4 immediate edges, and add loads of shortcuts
-- So we don't contract at all...

-- How about considering only points near barriers and points of interest?
-- Running a pathing calc on them and the source + dest is quite good
-- Hugely efficient on flat
-- Trouble is how do you determine which points the source can reach?
-- Would probably be quite good to reduce the map to "points in the center of 3x3 or 5x5 pathable squares with
--     at most three of their neighbors (also 3x3/5x5) being pathable"

-- Try and divide the map into convex zones?

-- How do you make a convex space?  Say we have a square grid of pathability made (maybe different size squares).

-- Really I should probably skip pathing for now...