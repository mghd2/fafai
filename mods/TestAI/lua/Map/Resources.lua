local function squareUpdateReclaim(map, square)
    local x = map.offsetx + square.I * map.square_size
    local z = map.offsetz + square.J * map.square_size
    local recs = GetReclaimablesInRect(x, z, x + map.square_size, z + map.square_size)
    local total_mass = 0
    local total_energy = 0
    local total_time = 0
    if recs then
        for _, rec in recs do
            -- At least 5 per object
            local time = 0
            -- Note: changes to this condition (>3) must be reflected in Task.lua as well
            if rec.MaxMassReclaim and rec.MaxMassReclaim * rec.ReclaimLeft > 3  then
                -- TODO: Why do I have to check for nilness of MaxMassReclaim?  (On Winter Duel)
                -- Maybe it was a unit?
                total_mass = total_mass + rec.MaxMassReclaim * rec.ReclaimLeft
                time = total_mass / 25  -- Just use a T1 engy's buildpower
            end
            if rec.MaxEnergyReclaim and rec.MaxEnergyReclaim * rec.ReclaimLeft > 9  then
                total_energy = total_energy + rec.MaxEnergyReclaim * rec.ReclaimLeft
                time = math.max(time, total_energy / 50)
            end
            total_time = total_time + time
        end
    end

    if total_mass < 10 and total_energy < 50 then
        -- Not worth it
        total_mass = 0
        total_energy = 0
        total_time = 0
    end

    square.Reclaim.M = total_mass
    square.Reclaim.E = total_energy
    square.Reclaim.T = total_time
end

local function monitorReclaimThread(map)
    local brain = map.brain
    while not brain:IsDefeated() do
        for i = 1, map.maxi do
            for j = 1, map.maxj do
                local sq = map.grid[i][j]
                squareUpdateReclaim(map, sq)
            end
            if math.floor(i / 4) == i / 4 then
                -- Check 4 slices of 7 per tick.
                -- That way an 81x81 map will take ~15s to refresh, and a 10x10 ~2s
                WaitTicks(1)
                if brain:IsDefeated() then
                    return
                end
            end
        end
    end
end

function MonitorReclaim(map)
    map.reclaim_thread = ForkThread(monitorReclaimThread, map)
    map.brain.Trash:Add(map.reclaim_thread)
end

-- TODO: This doesn't work for underwater mexes - an engineer just gets stuck trying to build one I've already built
local function squareUpdateResourceState(map, square)
    square.MexesFree = {}
    for _, mpos in square.Mexes do
        local mexes = map.brain:GetUnitsAroundPoint(categories.STRUCTURE * categories.MASSEXTRACTION, mpos, 0.1, "Ally")
        if not mexes or table.empty(mexes) then
            table.insert(square.MexesFree, mpos)
        end
    end
    square.HydrosFree = {}
    for _, hpos in square.Hydros do
        local hydros = map.brain:GetUnitsAroundPoint(categories.STRUCTURE * categories.HYDROCARBON, hpos, 0.1, "Ally")
        if not hydros or table.empty(hydros) then
            table.insert(square.MexesFree, hpos)
        end
    end
end

-- Monitor all the mex and hydros to see which are built by allies or not
local function syncResourceStateThread(map, mexes, hydros)
    local function updateResources(all_resources, free_field, category)
        local free_resources = {}  -- "x/z" = <position>
        for _, res in all_resources do
            free_resources[res[1].."/"..res[3]] = res
            local sq = map:GetSquare(res)
            sq[free_field] = {}
        end
        local ally_resources = map.brain:GetUnitsAroundPoint(categories.STRUCTURE * category, {100, 0, 100}, 100000, "Ally")
        for _, res in ally_resources do
            local rpos = res:GetPosition()
            free_resources[rpos[1].."/"..rpos[3]] = nil
        end
        LOG("Free resources of type "..free_field.." is "..table.getn(free_resources))
        for _, res in free_resources do
            local sq = map:GetSquare(res)
            table.insert(sq[free_field], res)
        end
    end

    while not map.brain:IsDefeated() do
        updateResources(mexes, "MexesFree", categories.MASSEXTRACTION)
        updateResources(hydros, "HydrosFree", categories.HYDROCARBON)
        WaitTicks(29)
    end
end

-- Add the mex and hydro markers into the map, and claim built ones
function SyncResources(map, mexes, hydros)
    for _, mex in mexes do
        local sq = map:GetSquare(mex)
        if sq then
            table.insert(sq.Mexes, mex)
            table.insert(sq.MexesFree, mex)
        else
            LOG("TestAI warning: ignoring mex outside map at "..repr(mex))
        end
    end
    for _, hydro in hydros do
        local sq = map:GetSquare(hydro)
        if sq then
            table.insert(sq.Hydros, hydro)
            table.insert(sq.HydrosFree, hydro)
        else
            LOG("TestAI warning: ignoring mex outside map at "..repr(mex))
        end
    end
    map.sync_resource_state_thread = ForkThread(syncResourceStateThread, map, mexes, hydros)
    map.brain.Trash:Add(map.sync_resource_state_thread)
end

-- Immediately update the resource data for a square (usually because it's just been built on / reclaimed)
function UpdateSquareAndNeighbors(map, square)
    squareUpdateReclaim(map, square)
    squareUpdateResourceState(map, square)

    -- Update the neighbors' reclaim as well: objects can overlap multiple squares
    for _, neigh in square.Conn.Hover do
        squareUpdateReclaim(map, neigh)
    end
end