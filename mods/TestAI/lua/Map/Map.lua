-- New map class: mostly pull the good stuff from MapMarkers

local Pathing = import('/mods/TestAI/lua/Map/Pathing.lua')
local Resources = import('/mods/TestAI/lua/Map/Resources.lua')
local Eco = import('/mods/TestAI/lua/Utils/Eco.lua')

local DEFAULT_BORDER = 4
local PLAYABLE_AREA = {}
local MEXES = {}
local HYDROS = {}
local SQUARE_SIZE = 7

-- The Map is responsible for all things map related: expansion, intel, finding good fights.
-- It's based on a recursive grid of squares.
-- There's an inner 1x1 grid used for pathing.
-- Then a 7x7 grid (equivalent to what a T1 engineer can reach with a reclaim from one spot).
-- Then a 49x49 grid for higher level summaries
-- - a 20x20 map is thus 21x21*(7x7*(7x7))
-- But do I want to scale up slower?  Maybw
-- For doing best path type stuff, being able to summarize frequently is good?
-- I'll want to implement a "distance weighted get best score" efficiently.
-- The idea I had there was to have some cached layers?

-- For pathing, I should never put intermediate points in partially pathable squares.

Map = Class({
    New = function(self, brain)
        self.brain = brain
        local GTH = GetTerrainHeight

        -- The offset needed to align the grid to the playable area, first index 1
        self.square_size = SQUARE_SIZE
        self.offsetx = PLAYABLE_AREA[1] - SQUARE_SIZE
        self.offsetz = PLAYABLE_AREA[2] - SQUARE_SIZE

        -- The square index of the far corner
        self.maxi = math.floor((PLAYABLE_AREA[3] - self.offsetx) / SQUARE_SIZE)
        self.maxj = math.floor((PLAYABLE_AREA[4] - self.offsetz) / SQUARE_SIZE)

        LOG("Map size:")
        LOG("Playable area = "..repr(PLAYABLE_AREA))
        LOG("Offsets = "..self.offsetx..", "..self.offsetz)
        LOG("Maxes = "..self.maxi..", "..self.maxj)

        -- Base location info
        local our_x, our_z = brain:GetArmyStartPos()
        self.our_base = {our_x, GTH(our_x, our_z), our_z}
        self.enemy_bases = {}  -- List of {x, y, z}
        self.ally_bases = {}  -- ^^
        for _, a in ListArmies() do
            local b = GetArmyBrain(a)
            if b and IsEnemy(b:GetArmyIndex(), brain:GetArmyIndex()) then
                local e_x, e_z = b:GetArmyStartPos()
                table.insert(self.enemy_bases, {e_x, GTH(e_x, e_z), e_z})
            elseif b and IsAlly(b:GetArmyIndex(), brain:GetArmyIndex()) then
                local a_x, a_z = b:GetArmyStartPos()
                table.insert(self.ally_bases, {a_x, GTH(a_x, a_z), a_z})
            end
        end

        -- Currently this is set up by the old MapMarkers class
        self.threat_map = nil

        self.grid = {}  -- The main map info, at 7x7 resolution
        for i = 1, self.maxi do
            self.grid[i] = {}
            for j = 1, self.maxj do
                local x = self.offsetx + SQUARE_SIZE * (i + 0.5)
                local z = self.offsetz + SQUARE_SIZE * (j + 0.5)

                local us_dist = VDist2(self.our_base[1], self.our_base[3], x, z)
                local ally_dist = us_dist
                for _, a in self.ally_bases do
                    ally_dist = math.min(ally_dist, VDist2(a[1], a[3], x, z))
                end
                local them_dist = 99999
                for _, e in self.enemy_bases do
                    them_dist = math.min(them_dist, VDist2(e[1], e[3], x, z))
                end
                -- Use a blend of distance from us and distance from allies
                local blend_dist = math.min(us_dist, (us_dist + ally_dist)/2)
                local mr = blend_dist / (blend_dist + them_dist + 0.1)

                self.grid[i][j] = {
                    I = i,
                    J = j,
                    P = {x, GTH(x, z), z},  -- The middle of the square
                    Ratio = mr,
                    Reclaim = {M=0, E=0, T=0},
                    Mexes = {},  -- Array of positions
                    Hydros = {},
                    MexesFree = {},  -- Array of positions not built by an ally
                    HydrosFree = {},
                    Claims = {R=0, M=0, H=0, F=0},
                    Zone = {},  -- .Land/Naval/Amphib/Hover/Air: 1 for our base
                    Conn = {},  -- .Land/Naval/Amphib/Hover/Air: {neighboring squares}
                    Path = {},  -- .Land/Naval/Amphib/Hover/Air: true if pathable
                }
                Pathing.CalculatePathing(self.grid[i][j], SQUARE_SIZE, self.offsetx + i * SQUARE_SIZE, self.offsetz + j * SQUARE_SIZE)
            end
        end

        -- Calculate neighbors
        Pathing.CalculateConnectivity(self)

        -- Calculate zones
        local start = self:GetSquare(self.our_base)  -- This shouldn't fail...
        Pathing.CalculateZones(self, start)

        -- Monitor reclaim on the map
        Resources.MonitorReclaim(self)

        -- Record all claims made
        -- Each is id={F=<fraction claimed>, S=<square>, T=<type>, R=<last refresh tick>}
        self.claims = {}
        self.claim_tick = 1
        self.claim_id_next = 2  -- Mustn't be an array
        self.expire_claims_thread = ForkThread(Map.ExpireClaimsThread, self)
        self.brain.Trash:Add(self.expire_claims_thread)

        -- Add the resource markers
        Resources.SyncResources(self, MEXES, HYDROS)

        -- Quick value lookup tables
        -- One per type of relevant value (terrain, mexes, reclaim, ...)

        -- Pathing.VisualizePathing(self)  -- Draw the zones for debugging

    end,

    OurBase = function(self)
        return self.our_base
    end,

    -- Return the position of the nearest enemy base
    -- TODO: Skip dead enemies, or use threat / zones of control more?  e.g. deal with island contesting
    ClosestEnemyBase = function(self, from_position)
        local dist = 99999999
        local base = self.our_base
        for _, b in self.enemy_bases do
            if VDist2(b[1], b[3], from_position[1], from_position[3]) < dist then
                base = b
            end
        end
        return base
    end,

    -- Will return nil if square is outside the playable area
    GetSquare = function(self, pos)
        local i = math.floor((pos[1] - self.offsetx) / SQUARE_SIZE)
        local j = math.floor((pos[3] - self.offsetz) / SQUARE_SIZE)
        local mid = self.grid[i]
        if mid then
            return mid[j]
        else
            return nil
        end
    end,

    -- Try and find a square near pos that's in a specified zone
    -- layer or zone may be nil, in which case this is just GetSquare()
    GetSquareNearbyOnLayer = function(self, pos, layer, zone)
        local sq = self:GetSquare(pos)
        if layer and zone and sq.Zone[layer] ~= zone then
            if zone and zone > 0 then
                -- Consider direct neighbors if unpathable
                for _, air_sq in sq.Conn.Air do
                    if air_sq.Zone[layer] == zone then
                        sq = air_sq
                        break
                    end
                end
            end
        end
        return sq
    end,

    -- Return the total enemy threat near a square
    -- Looks for all enemies that are in range of about 20 from the center
    -- Returns {V={<value by layer>}, HP={<HP by layer>}, DS={<DPS single target by layer>}, DA={<AoE>}}
    EnemyThreatNearby = function(self, square)
        local threat_sq = self.threat_map:GetSquareFromPos(square.P)
        if threat_sq then
            return self.threat_map:GetThreatInRangeOfSquare(threat_sq, false)
        else
            local zeros = {0, 0, 0, 0, 0, 0}
            return {V=zeros, DS=zeros, DA=zeros, HP=zeros}
        end
    end,

    FightSquareValue = function(self, square, our_threat)
        local threat_sq = self.threat_map:GetSquareFromPos(square.P)
        if threat_sq then
            return self.threat_map:FightValue(threat_sq, our_threat)
        else
            return 0
        end
    end,

    -- Like FightSquareValue, but the results are scaled down so that 1 is the value of our army
    FightSquareValueRatio = function(self, square, our_threat)
        local our_value = 1
        for _, v in our_threat.V do
            our_value = our_value + v
        end
        return self:FightSquareValue(square, our_threat) / our_value
    end,

    GetUnitsThreat = function(self, units)
        return self.threat_map:GetCombinedThreat(units)
    end,

    -- Claims must be refreshed every 28s or they expire
    -- type can be R (esources), or F (ight)
    -- fraction (default 1) allows only making a partial claim - the other portion will remain available
    -- Returns the claim (actually a claim id)
    GetClaim = function(self, square, type, fraction)
        if not fraction then
            fraction = 1
        end

        -- Clamp overcommits at 1: something probably is stuck without Releasing
        if square.Claims[type] + fraction > 1 then
            LOG("Attempt to overclaim a square: type "..type)
        end
        square.Claims[type] = math.min(square.Claims[type] + fraction, 1)

        local claim = {F=fraction, T=type, S=square, R = self.claim_tick}
        local claim_id = self.claim_id_next
        self.claim_id_next = self.claim_id_next + 1
        self.claims[claim_id] = claim
        return claim_id
    end,

    RefreshClaim = function(self, claim_id)
        local claim = self.claims[claim_id]
        if claim then
            claim.R = self.claim_tick
        end
    end,

    ReleaseClaim = function(self, claim_id)
        local claim = self.claims[claim_id]
        if claim then
            claim.S.Claims[claim.T] = math.max(claim.S.Claims[claim.T] - claim.F, 0)
            self.claims[claim_id] = nil
            
            -- Update the resource values in this square (and adjacent ones)
            Resources.UpdateSquareAndNeighbors(self, claim.S)
        end
    end,

    ExpireClaimsThread = function(self)
        while not self.brain:IsDefeated() do
            self.claim_tick = self.claim_tick + 1
            WaitTicks(283)

            -- TODO: Claim all built mexes

            -- Supposedly it's safe to =nil while iterating
            for claim_id, claim in self.claims do
                if claim.R < self.claim_tick then
                    LOG("Claim expired: type "..claim.T)
                    self:ReleaseClaim(claim_id)
                end
            end
        end
    end,

    -- Find a short route from a point that maximises the sum(value_fn)
    -- Filter 
    -- It doesn't anticipate the effect of previous steps, so value_fn = fight_value may not work well.
    -- (Because most nearby squares will be assessed as having the same fights)
    -- Many possible routes will not be considered
    FindBestRouteFrom = function(self, source, speed, layer, value_fn, filter_fn)
        -- TODO: Defaulting to 1 is bad, but because we don't map partial squares we might start from an unzoned square
        local zone = self:GetSquare(source).Zone[layer] or 1

        -- This is very similar to the expansion path calculator...

        local checkStraightLine = function(start, finish)
            -- Next square along line
            local sq = nil


            if layer and not (sq.Path[layer] and (zone == nil or zone == sq.Zone[layer])) then
                -- Not pathable on this layer or in the wrong zone
                return false
            end

            if filter_fn and not filter_fn(sq) then
                return false
            end
            return true
        end

        local routes = {}

        local best_route = nil
        local best_value = 0

        -- Just try out some intermediate points.
        -- Let's say we try some spaced out points covering down to a 90degree angle in the middle


    end,


    -- Trying to initially replace FindClosestResourcesOfType for reclaim
    -- source is a position
    -- layer can be nil or Land / Hover / Naval / Amphib.  Only targets in the same zone will be considered.
    -- value_fn(square) returns the value (not considering arrival time)
    -- filter_fn(square) optional returns true if the square should be considered
    -- Returns square, value
    FindBestSquareFrom = function(self, source, speed, layer, value_fn, max_distance, filter_fn)
        local basei = math.max(math.floor((source[1] - self.offsetx - max_distance) / SQUARE_SIZE), 1)
        local basej = math.max(math.floor((source[3] - self.offsetz - max_distance) / SQUARE_SIZE), 1)
        local maxi = math.min(math.floor((source[1] - self.offsetx + max_distance) / SQUARE_SIZE), self.maxi)
        local maxj = math.min(math.floor((source[3] - self.offsetz + max_distance) / SQUARE_SIZE), self.maxj)

        local best_square = nil
        local best_value = 0
        -- TODO: Defaulting to 1 is bad, but because we don't map partial squares we might start from an unzoned square
        local zone = self:GetSquare(source).Zone[layer] or 1
        LOG("FBSF Source zone is "..zone)
        -- TODO: Maybe use the nearby square stuff - deals with using an average position of an army
        -- TODO: Or maybe would be better to actually use a median position (so it's really pathable)?
        -- Closest unit to the average say

        for i = basei, maxi do
            for j = basej, maxj do
                local sq = self.grid[i][j]
                if layer and not (sq.Path[layer] and (zone == nil or zone == sq.Zone[layer])) then
                    -- Not pathable on this layer or in the wrong zone
                    continue
                end

                if filter_fn and not filter_fn(sq) then
                    continue
                end

                local dist = VDist2(source[1], source[3], sq.P[1], sq.P[3])
                if dist > max_distance then
                    continue
                end
                local base_value = value_fn(sq) or 0
                -- TODO: Controllable half lives: want like 30s for combat, 100s for expansion and 300s for ecoing
                local value = Eco.ValueFn(base_value, 0, dist / speed)

                if value > best_value then
                    best_value = value
                    best_square = sq
                end
            end
        end
        return best_square, best_value
    end,

    -- Returns a square or nil
    -- source is a position
    -- filter_fn takes a square and returns true if it should be considered (optional)
    FindBestFightFrom = function(self, source, speed, layer, units, filter_fn)
        local fixed_filter_fn = nil
        if filter_fn then
            fixed_filter_fn = function(sq)  -- The old threat gets a new sq, but doesn't check pathing
                local new_sq = sq
                if source then
                    new_sq = self:GetSquareNearbyOnLayer(new_sq.P, layer, source.Zone[layer])
                end
                return filter_fn(new_sq)
            end
        end
        local old_square = self.threat_map:GetBestFight(units, nil, source, fixed_filter_fn)
        local new_square = nil
        if old_square then
            new_square = self:GetSquare(old_square.POS)
            if source then
                new_square = self:GetSquareNearbyOnLayer(new_square.P, layer, source.Zone[layer])
            end
        end
        return new_square
    end,

    -- This is very inefficient still...
    FindBestPathFrom = function(self, source, speed, layer, zone, value_fn, max_distance)
        -- Get the best squares in the area as candidates



        -- Optimize the initial path by searching along it
    end,






    -- To really make use of this I need to combine all the different maps (reclaim, mexes, threat, pathability)
    -- I should also be able to separately count certain threat and uncertain threat (moving units)
    -- I should also be able to view economic threat separately (to find mexes and stuff)
    -- I want to be able to record claims of several types (trying to kill unit / claim mex / reclaim / threaten enemies)

    -- If I implement A* using a function that prioritizes distance from a target, then I have a lot of options
    -- Expansion paths doesn't have a target, but 
    -- I need to make sure I have a metric?  Maybe?
    -- filter can rule out certain nodes (e.g. different landmass, too far away etc)
    -- I need a way to define cost (time)
    -- valuation function specifies the value of a node; this will be exponentially scaled for time
    -- Can I use valuation as an A* style heuristic somehow?  An A* heuristic is basically max_value.
    -- Do I need to have a separate thing to maximise (mass) and minimize (time)?
    -- The expansion calculator needs to have a maximum possible heuristic
    -- A simple path calc is then (filter: landzone==1, valuation=1/distance-to-target, max_val=1/distance-to-target)
    -- Expansion might be ()
    -- I need a limit too (e.g. 60s) - will it ever be something other than time?
    -- I could either use a path valuation (with v(X) <= v(X then Y)) or a point valuation function with exp time decay?
    AStar = function(start, destination, metric, filter, valuation)

    end,

    -- Return the rough distance between squares.  Eventually upgrade to allow threat limits.
    RoughDistance = function(self, a, b)

    end,

    -- Dijkstra expands the node with the lowest path-cost
    -- A* expands the point with the lowest path-cost + heuristic
    -- I expand the node with the highest min (i.e. best), but also some bad nodes
    -- On some maps tanks might need to move for several minutes, so a 1 minute max could be a problem.

    -- Because I skip squares, I can't really do a threat test.  I could maybe do that separately, keeping the AtoB distances up to date?

    -- Can I express a simple path find using my min / max algorithm?
    -- Make the +max the A* heuristic somehow?

    -- How about some more practical problems?
    -- Find something to raid?
    -- Dispatch interceptors?
    -- Defend with bombers?

    -- A thing that's different to a simple path calc is that this can skip squares basically
    -- This is actually quite a big difference
    -- Makes it more like a path calc where the graph is {0}->{1a..Na}->{1b..Nb}\{the a visited}->{1c..Nc}\{the a and b}

    -- I need to be able to calculate the time spent in a square

    -- filter 
    -- valuation takes two parameters: path, and square.  
    -- Do I want to calculate time internally?







})

-- Would be useful to be able to specify "path from here to here"; i.e. incorporate A*

PathCalculator = Class({
    New = function(self, map, start)
        self.map = map
        self.start = start  -- A square

        -- Limits the calculation to a given rectangle
        self.mini = 1
        self.minj = 1
        self.maxi = map.maxi
        self.maxj = map.maxj

    end,

    -- Distance in range units; is actually treated as a rectangle though
    RangeLimit = function(self, max_distance)
        local squares = math.floor((max_distance + 16) / 32)
        self.mini = math.max(1, self.start.I - squares)
        self.minj = math.max(1, self.start.J - squares)
        self.maxi = math.min(self.maxi, self.start.I + squares)
        self.maxj = math.min(self.maxj, self.start.J + squares)
    end,


    -- TODO: When I track predicted eco income, include as an output scaling down the value of reclaim if it is likely to overflow

    -- TODO: Test with range limiting it to only 1 square
    -- Maybe I can do a soft time cutoff?  Start being very picky about the acceptable squares
    -- filter_fn(square) (optional) returns true if the square should be skipped
    -- value_fn(square) returns the value of the square at the current time; only >= 5 will be considered, and all will be time scaled
    FindBestPath = function(self, speed, metric, filter_fn, value_fn, max_time)
        local start_time = GetSystemTimeSecondsOnlyForProfileUse()
        local expanded_count = 0
        local map = self.map
        local grid = map.grid

        -- Prepare the possible squares, considering filters, range limits and calculate the value at t=0
        local possible_squares = {}
        for i = self.mini, self.maxi do
            for j = self.minj, self.maxj do
                local sq = grid[i][j]
                if not filter_fn or not filter_fn(sq) then
                    local value = value_fn(sq)
                    if value > 5 then
                        -- TODO Consider claims
                        -- TODO Calculate time to get squares value separately?
                        -- This is complex, because it might be optimal to partly exploit a square^^
                        table.insert(possible_squares, sq)
                    end
                end
            end
        end

        -- Possible optimization:
        -- Store things more hierarchically - the operation we want is kinda like "get really good stuff far, and good stuff close"
        -- A square has value v, and say that d is the distance (in squares) that halves value considering speed and the value decay fn
        -- We want to find the maximal v/2^t; so how about we have separate sparse arrays for many different v's?
        -- grid[floor(log(value))][floor(i/d)][floor(j/d)] as a sparse array containing {<squares that fit>} or nil?
        -- Then we can find "good" expansions by going through the values descending, but decreasing the search radius each step
        -- A downside of this is that it'll skip out worth-it-on-the-way squares

        -- New gradient based approach
        -- A square has a value v, and also travel time across the square of t
        -- A 2x2 of squares we can calculate which ones are best to hit I think?
        -- But how well does this translate to an expansion path?

        -- A challenge of being able to do "get things that will be a nice boost" 
        -- Maybe I follow up with a filling in process?

        -- Grouping approach?
        -- If there are nearby good squares, combine them?

        local paths = {}  -- {<start time>, <end time>, <min value>, <max value>, <last square>, {10000*<square.I>+<square.J>=<count in path>}}
        while true do  -- TODO: Change, and add counting and speedups
            -- Determine expansion parameters
            local threshold_min = 3  -- Expand minimum over this
            local threshold_max = 5  -- Expand maximum over this

            -- Expansion phase
            for _, path in paths do
                if path[3] > threshold_min or path[4] > threshold_max then
                    for _, t in possible_squares do
                        if path[6][10000*t.I+t.J] ~= nil then
                            -- Square is already in the path
                            continue
                        end




                        local travel_time = map:RoughDistance(path[5], t) / speed
    
                        
                        expanded_count = expanded_count + 1



                    end
                end
            end

            -- Termination conditions
            -- Terminate if highest min is within 20% of highest max
            -- Calculate the thresholds for the next iteration

        end


        local elapsed_time = GetSystemTimeSecondsOnlyForProfileUse() - start_time
        LOG("Expansion path calculated in "..expanded_count.." taking "..elapsed_time)

        -- Produce output list

    end,

})


function BeginSession()
    -- TODO: Detect if a map is required (inc versioning?)
    PLAYABLE_AREA = { DEFAULT_BORDER, DEFAULT_BORDER, ScenarioInfo.size[1], ScenarioInfo.size[2] }
end

-- Create map if needed
function GetMap(brain)
    if not brain.TestAIMap then
        brain.TestAIMap = Map()
        brain.TestAIMap:New(brain)
    end
    return brain.TestAIMap
end

function CreateMarker(t, x, y, z, size)
    LOG("Recording marker "..repr(t).." at "..x..","..y..","..z)
    if t == "Mass" then
        table.insert(MEXES, {x, y, z})
    else
        table.insert(HYDROS, {x, y, z})
    end
end

-- I'm unclear what it is that makes this necessary: it's from DilliDalli
function SetPlayableRect(x0, z0, x1, z1)
    -- "Fields of Isis is a bad map, I hate to be the one who has to say it." - Softles
    PLAYABLE_AREA = { x0, z0, x1, z1 }
end
