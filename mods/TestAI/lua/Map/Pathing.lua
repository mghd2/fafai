local GetRandomInt = import('/lua/utilities.lua').GetRandomInt

-- TODO: Useful to have a canpathto function for units that includes "or nearby" (in which case it might not be the same layer).  Allows ranged raiding.

-- TODO: Known reachability problems.
-- Craftious Maximus: not considering 1x1 links makes the ramps look unusable
-- Rusted Iron Roundel from slot 1: left most of the mexes on the overlook near our base is ignored
-- Sweepwing Sanctum: mexes in the dips at the side are attempted but unreachable
-- Festea VIII: both mexes on plateaus on the bottom are believed reachable but aren't.
-- I fixed some bugs, so I think most of these should be fixed

-- Fill out the Path fields on a map square
-- The square must be 100% pathable to count (so may miss small passageways)
-- TODO: Consider partially pathable squares (say with at least 10 usable 1x1 squares)
function CalculatePathing(square, size, cx, cz)
    -- Pathability conditions based on those by Balthazar; except for hover which I've made up
    local max, abs = math.max, math.abs
    local GTH, GSH, GTT = GetTerrainHeight, GetSurfaceHeight, GetTerrainType
    
    local function canPathSlope(x,z,t) local a,b,d = GTH(x-1,z-1),GTH(x-1,z),GTH(x,z-1) return max(abs(a-b), abs(b-t), abs(t-d), abs(d-a)) <= 0.75 end
    -- This^^ makes 4x as many GTH calls as needed
    local function canPathTerrain(x,z) local t = GTT(x,z) return t ~= 'Dirt09' and t ~= 'Lava01' end

    -- Whether the entire square is pathable at a layer
    local land, amphib, naval, hover = true, true, true, true

    for i = 1, size do
        for j = 1, size do
            local x = cx + i - 1
            local z = cz + j - 1

            if not canPathTerrain(x, z) then
                land = false
                amphib = false
                naval = false
                hover = false
                break
            end

            local s, t = GSH(x, z), GTH(x, z)
            local path_slope = canPathSlope(x, z, t)
            land = land and s == t and path_slope
            hover = hover and (s > t or path_slope)  -- Don't know if this is right, but it seems plausible
            amphib = amphib and t + 25 > s and path_slope
            naval = naval and s - 1.5 > t
        end
        if not (land or amphib or naval or hover) then
            break
        end
    end
    square.Path.Land = land
    square.Path.Amphib = amphib
    square.Path.Naval = naval
    square.Path.Hover = hover
    square.Path.Air = true
end

-- Calculate neighbors
function CalculateConnectivity(map)
    for i = 1, map.maxi do
        for j = 1, map.maxj do
            local sq = map.grid[i][j]
            sq.Conn.Land = {}
            sq.Conn.Amphib = {}
            sq.Conn.Naval = {}
            sq.Conn.Hover = {}
            sq.Conn.Air = {}
            for _, pos in {{i-1, j}, {i+1, j}, {i, j-1}, {i, j+1}} do
                local i2s = map.grid[pos[1]]
                if i2s then
                    local adj = map.grid[pos[1]][pos[2]]
                    if adj then
                        -- Got an adjacent square - work out if it's connected
                        if sq.Path.Land and adj.Path.Land then
                            table.insert(sq.Conn.Land, adj)
                        end
                        if sq.Path.Amphib and adj.Path.Amphib then
                            table.insert(sq.Conn.Amphib, adj)
                        end
                        if sq.Path.Naval and adj.Path.Naval then
                            table.insert(sq.Conn.Naval, adj)
                        end
                        if sq.Path.Hover and adj.Path.Hover then
                            table.insert(sq.Conn.Hover, adj)
                        end
                        table.insert(sq.Conn.Air, adj)
                    end
                end
            end
        end
    end
end

local function calculateZonesLayer(map, start, layer)
    local initial_zone_to_square = {}
    -- Assign zone 1 to our starting point if it's pathable
    if start.Path[layer] then
        start.Zone[layer] = 1
        initial_zone_to_square[1] = start
    end

    -- Assign a unique zone to each pathable square
    local next_zone = 2
    for _, sqs in map.grid do
        for _, sq in sqs do
            if sq.Path[layer] and sq.Zone[layer] == nil then
                sq.Zone[layer] = next_zone
                initial_zone_to_square[next_zone] = sq
                next_zone = next_zone + 1
            end
        end
    end

    -- Go through and expand each zone in turn
    -- Because we fully expand the smallest numbered zones first, we only need to look at higher zoned neighbors
    for zone = 1, next_zone - 1 do
        local initial_square = initial_zone_to_square[zone]
        if initial_square then
            local updated_list = {initial_square}
            local num_updated = 1
            while num_updated > 0 do
                num_updated = 0
                local newly_updated_list = {}
                for _, sq in updated_list do
                    for _, adj in sq.Conn[layer] do
                        local adj_zone = adj.Zone[layer]
                        if adj_zone > zone then
                            -- This neighbor is in a greater numbered zone - assimilate them
                            initial_zone_to_square[adj_zone] = nil
                            adj.Zone[layer] = zone
                            table.insert(newly_updated_list, adj)
                            num_updated = num_updated + 1
                        end
                    end
                end
                updated_list = newly_updated_list
            end
        end
    end
end

function CalculateZones(map, start)
    calculateZonesLayer(map, start, "Land")
    calculateZonesLayer(map, start, "Naval")
    calculateZonesLayer(map, start, "Amphib")
    calculateZonesLayer(map, start, "Hover")
    for _, sqs in map.grid do
        for _, sq in sqs do
            sq.Zone.Air = 1
        end
    end
end









local function visualizePathingThread(map)
    local zone_cols = {'aaffffff'}  -- Make zone 1 white
    while not map.brain:IsDefeated() do
        for _, sqs in map.grid do
            for _, sq in sqs do

                -- Randomly color the Hover Zones
                if sq.Zone.Hover then
                    if not zone_cols[sq.Zone.Hover] then
                        zone_cols[sq.Zone.Hover] = 'aa'..GetRandomInt(1, 9)..GetRandomInt(1, 9)..GetRandomInt(1, 9)..GetRandomInt(1, 9)..GetRandomInt(1, 9)..GetRandomInt(1, 9)
                    end
                    DrawCircle(sq.P, 2, zone_cols[sq.Zone.Hover])
                end

                -- Display pathing for this square
                local color = 'aa'
                if sq.Path.Land then  -- Land is Red
                    color = color..'ff'
                else
                    color = color..'00'
                end
                if sq.Path.Naval then  -- Naval is Green
                    color = color..'ff'
                else
                    color = color..'00'
                end
                if sq.Path.Hover then  -- Hover is Blue
                    color = color..'ff'
                else
                    color = color..'00'
                end
                DrawCircle(sq.P, 3, color)

                -- Display its neighbors (data format isn't great for doing this...)
                local neighs = {}  -- <square> -> color
                for _, adj in sq.Conn.Land do
                    neighs[adj] = 'aaff'
                end
                for _, adj in sq.Conn.Naval do
                    if neighs[adj] then
                        neighs[adj] = neighs[adj]..'ff'
                    else
                        neighs[adj] = 'aa00ff'
                    end
                end
                for adj, n in neighs do
                    if string.len(n) < 6 then
                        neighs[adj] = neighs[adj]..'00'
                    end
                end
                for _, adj in sq.Conn.Hover do
                    if neighs[adj] then
                        neighs[adj] = neighs[adj]..'ff'
                    else
                        neighs[adj] = 'aa0000ff'
                    end
                end
                for adj, n in neighs do
                    if string.len(n) < 8 then
                        neighs[adj] = neighs[adj]..'00'
                    end
                end
                for adj, col in neighs do
                    DrawLine(sq.P, adj.P, col)
                end
            end
        end
        WaitTicks(2)
    end
end

function VisualizePathing(map)
    map.visualize_pathing_thread = ForkThread(visualizePathingThread, map)
    map.brain.Trash:Add(map.visualize_pathing_thread)
end