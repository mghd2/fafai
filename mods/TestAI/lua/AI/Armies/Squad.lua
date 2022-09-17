local Map = import('/mods/TestAI/lua/Map/Map.lua')
local RandomFloat = import('/lua/utilities.lua').GetRandomFloat
local Army = import('/mods/TestAI/lua/AI/Armies/Army.lua')

-- TODO: Apparently this is faster than GetBlueprint() - should use it elsewhere too
local __blueprints = __blueprints

-- Leaving aside questions of squads and targets and stuff, where should units actually be?
-- Bad fights are terrible: having a 10 units in each of 5 places means you can lose to a smaller force.
-- If you have 2x, you can crush on offense; 0.5x you lose on defense.
-- Why not make one huge army somewhere?  Advance as you can, and dispatch units to block incursion?
-- All of this is "per surface" probably.  Big sparse maps need multiple armies too.
-- An incursion into unprotected territory is very strong / dangerous.
-- Probably the move is to combine armies if there's enough intel to still react to incursion?
-- In common 2 big expansions situations; want to send ACU to one and majority of units to other?
-- Need to keep ACU alive though
-- Need to keep units forwards where possible

-- A raiding team should be balanced?  Scout, 3 tank, arty, MAA?  Engineer probably worthwhile too.
-- Loses to 4 tanks though...



-- Micro a squad of units to attack a target
-- Do I want to have 1 squad per target?  Maybe I do?  Then they try and get a new target.
-- When they get the new target they can maybe split if overpowered.  Or even disband?
-- Want to be able to merge too.
-- When do I want multiple squads for 1 target?  Land + Air?

-- Say I make a Target for each mex / group of enemies
-- How do I prioritize what to attack?
-- Each one has a required investment; and a returned value; and a bonus for being on our side
-- Then I have units, but I need to reduce the priority of far away things
-- Also want to avoid churn.
-- Maybe churn is reduced by the boost from units being close?  Enough stability?

-- Given a [Target: Position, KillValue, StrengthNeeded], and [Unit: Strength, Position], what do we fund?
-- Maybe have a MinStrength, MaxStrength, OverStrengthDecay.  Value is 0 unless we can make Min; linear in units until Max, then Decay*more units after?
-- So defense might be low min, medium max, fast decay
-- Main invasion force might be high min, high max, slow decay
-- Raiding might be low min, low max, fast decay
-- For defensive value, want it higher towards the middle of the map
-- Let's say that Values decrease exponentially with time; and therefore distance between unit and Squad
-- We want to end up with fully funded Squads mostly
-- May want to steal units from other Squads if we have better priority

-- Assignment algorithm is ...complex...
-- For each unit; if we assume we'll make the min strengths that's good
-- We can always do the calculation slowly, so inefficient is maybe fine

-- Unit first approach:
-- Unit spawns: calculate best Squad/Target for it assuming it becomes funded and start moving
-- - If it doesn't get funded soon, bail?  Each Squad could have a staging area near the enemy?
-- - If a Squad wants 20 tanks near the base, it can borrow against production (diminishing returns),
--   and then steal from other squads?

-- Need to penalize bringing a squad below min significantly

-- If we just calculate each Squad with a minimum strength and a valueratio?
-- - Keeps it simple

-- Doing Squads based on targets is problematic if a target is on the way maybe?
-- I guess we could do like each bit of the map is a similarly valuable target
-- (maybe diminishing with distance from our base and increasing less with distance from theirs)

-- Maybe the Map class maintains a list of Targets.
-- Targets start as "enemy" but can become "ally" or "neutral"
-- If we move there and kill all enemies it becomes "ally"
-- If enemies come back it becomes ""
-- 
-- A Target becomes threatened if enemy troops are there

-- How do I want a Squad to work?
-- Give it units, and a target and such
-- It is so similar to a platoon in practice...
-- Units have a state within a squad, and the squad as a whole has a state too
-- Need to pick a rally point for a squad, where it will gather
-- Once a threshold (num units and a timeout) is met we can proceed
-- Units that didn't make the meeting point will continue moving to the squad
-- Probably want a few different threads based on role and units
-- This is of course completely analogous to a standard platoon
-- Or do I want to turn it around a bit, and have them request more units while operating?
-- Not really sure that makes sense?

local DEBUG = false

Squad = Class({
    -- targets is an array of positions (in order)
    -- size is the number of units the squad will wait for before proceeding
    New = function(self, army, name, zone)
        self.brain = army.brain
        self.map = Map.GetMap(self.brain)
        self.name = name
        self.army = army
        self.zone = zone -- Optional

        -- Just pick an initial target about a third of the way across the map
        -- It should be very unlikely that this can't find anywhere, but it will crash if it can't
        local value_fn = function(sq)
            return math.max(10 - 20 * math.pow(sq.Ratio - 0.3, 2) + RandomFloat(0, 1), 0.1)
        end
        self.target = self.map:FindBestSquareFrom(self.map:OurBase(), 20, "Land", value_fn, 200, nil).P

        self.units = {}  -- Units that are with the Squad
        self.moving_fraction = 0

        self.rallying_units = {}  -- Units on the way
        self.rally_pos = {unpack(self.target)}  -- Send units here

        self.performance = {0, 0, 0}  -- value lost, value killed by dead, value killed by living

        self.squad_thread = ForkThread(Squad.squadThread, self)
        self.brain.Trash:Add(self.squad_thread)
    end,

    -- Called regularly - do work for the squad here
    -- self.units, self.rallying_units and self.rallied_units will be updated before calling
    -- return false if the squad should be disbanded
    OnTick = function(self)
        return true
    end,

    VisualizeTarget = function(self, color)
        local t = ForkThread(
            function()
                while not self.brain:IsDefeated() do
                    DrawCircle(self.target, 3, color)
                    if self.rally_pos then
                        DrawLine(self.rally_pos, self.target, color)
                    end
                    WaitTicks(2)
                end
            end
        )
        self.brain.Trash:Add(t)
    end,

    -- Return a heading that faces the units towards the enemy
    -- S is 0, E is 90
    -- TODO: Think this is picking the wrong headings
    EnemyBaseHeading = function(self)
        local enemy = self.map:ClosestEnemyBase(self.target)
        local rad = math.atan2(enemy[1] - self.target[1], enemy[3] - self.target[3])
        local degrees = rad * (180 / math.pi)
        return degrees
    end,

    -- Run through all the units, update liveness, performance and check if they're moving or not
    UpdateUnits = function(self)
        -- Update unit lists and record performance
        local lu, kdu, klu, ru, rdu, rlu
        self.units, lu, kdu, klu = self.army:UpdateUnitList(self.units)
        self.rallying_units, ru, rdu, rlu = self.army:UpdateUnitList(self.rallying_units)
        self.performance = {
            self.performance[1] + lu + ru,
            self.performance[2] + kdu + rdu,
            klu + rlu  -- Live units only so no need to accumulate
        }

        -- Check for moving units
        local moving = 0
        local stationary = 0
        for _, u in self.units do
            if u.TestAISquadLastPosition then
                local pos = u:GetPosition()
                local dist = VDist2(u.TestAISquadLastPosition[1], u.TestAISquadLastPosition[3], pos[1], pos[3])
                LOG("Unit dist was "..dist)
                if dist < 1 then
                    stationary = stationary + 1
                else
                    moving = moving + 1
                end
            end
            u.TestAISquadLastPosition = {u:GetPositionXYZ()}
        end
        
        LOG(self.name.." recording moving fraction moving="..moving..", stationary="..stationary)
        self.moving_fraction = (moving + 0.0001) / (stationary + moving + 0.0001)
    end,

    -- Returns the fraction of the units that are in idle state or aren't moving
    -- Will be 0 if there are no units
    GetUnitStates = function(self)
        local idle = 0
        local total = table.getn(self.units)
        for _, u in self.units do
            if not u.Dead and u:IsIdleState() then
                idle = idle + 1
            end
        end
        LOG(self.name.." checking states: idle="..idle..", total="..total)
        local unit_state_idle =  (idle) / (total + 0.0001)
        if unit_state_idle < (1 - self.moving_fraction) then
            -- A FormMove has moving state on all units even if only 1 or 2 are repositioning
            LOG(self.name.." using movement progress result instead of unit states")
            LOG(self.name.." idle fraction is "..(1 - self.moving_fraction))
        end
        return math.max(unit_state_idle, (1 - self.moving_fraction))
    end,

    -- Get a pathable spot towards "to" by 20, or "to" if it's within 20
    GetPositionTowards = function(self, from, to)
        local dist = VDist2(from[1], from[3], to[1], to[3])
        local pos = {}
        if dist > 20 then
            pos[1] = MATH_Lerp(20/dist, from[1], to[1])
            pos[3] = MATH_Lerp(20/dist, from[3], to[3])
            pos[2] = GetTerrainHeight(pos[1], pos[3])
        else
            pos = to
        end
        local sq = self.map:GetSquareNearbyOnLayer(pos, "Land", self.zone)
        return sq.P
    end,

    squadThread = function(self)
        -- TODO: Offset all the squadThreads so they don't run simultaneously
        while not self.brain:IsDefeated() do
            local debug_start_time = 0
            if DEBUG then
                debug_start_time = GetSystemTimeSecondsOnlyForProfileUse()
            end

            self:UpdateUnits()

            -- Rally units to the army
            if next(self.units) then
                self.rally_pos = self:GetAveragePosition(self.units)
            end
            if next(self.rallying_units) then
                if not self.rally_pos then
                    self.rally_pos = self:GetAveragePosition(self.rallying_units)
                end
                local i = 1
                local n = table.getn(self.rallying_units)
                while i <= n do
                    local u = self.rallying_units[i]
                    if VDist3(u:GetPosition(), self.rally_pos) < 30 then
                        -- Unit has arrived
                        table.remove(self.rallying_units, i)
                        table.insert(self.units, u)
                        IssueClearCommands({u})
                        i = i - 1  -- Adjust the loop
                        n = n - 1
                        self:UnitArrivedBase(u)
                    elseif table.empty(u:GetCommandQueue()) then
                        IssueMove({u}, self:OffsetPosition(self.rally_pos, i))
                    elseif u.TestAILastPosition then
                        local moved = VDist3(u.TestAILastPosition, u:GetPosition())
                        if moved < 5 then
                            -- Maybe it's stuck
                            IssueClearCommands({u})
                            IssueMove({u}, self:OffsetPosition(self.rally_pos, i))
                        end
                    end
                    u.TestAILastPosition = {u:GetPositionXYZ()}
                    i = i + 1
                end
            end

            -- Let the derived class actually do some work
            -- Intentionally call even if there are no units in case it wants to change the rally point
            if not self:OnTick() then
                LOG("Terminating squad "..self.name)
                break
            end

            -- NB: Our cost include E and BP and kills don't; so 1.0 is actually really good
            LOG("Squad "..self.name.." performance so far: dead units at "..self.performance[2].."/"..self.performance[1].."="..(self.performance[2]/(self.performance[1] + 0.0001))..", live units killed total "..self.performance[3])

            if DEBUG then
                local debug_end_time = GetSystemTimeSecondsOnlyForProfileUse()
                LOG("Debug: Squad "..self.name.." thread time was "..(debug_end_time - debug_start_time))
            end
            WaitTicks(23)
        end
    end,

    -- Get a position for the unit to move to that's close to the target
    OffsetPosition = function(self, position, unit_index)
        local index = math.sqrt(unit_index/3 - 0.05) - 0.5000001
        local r = 2 * math.ceil(index)
        local theta = 2 * math.pi * (index - r) + r
        local x = r * math.cos(theta) + position[1]
        local z = r * math.sin(theta) + position[3]
        local y = GetTerrainHeight(x, z)
        return {x, y, z}
    end,

    -- UpdateUnitList must be called first
    -- Returns nil if there are no units
    GetAveragePosition = function(self, units)
        local sx, sz, n = 0, 0, 0
        for _, u in units do
            local x, _, z = u:GetPositionXYZ()
            sx = sx + x
            sz = sz + z
            n = n + 1
        end
        if n > 0 then
            local x = sx / n
            local z = sz / n
            return {x, GetTerrainHeight(x, z), z}
        else
            return nil
        end
    end,

    UnitArrivedBase = function(self, unit)
        -- TODO: run in thread
        self:UnitArrived(unit)
    end,

    -- Notify an army that a new unit has arrived (already in the units list)
    -- This will be called in a per-unit thread; so WaitTicks can be used
    UnitArrived = function(self, unit)
        LOG("warning: Abstract method called: UnitArrived on "..repr(self))
    end,

    -- Currently this uses total kills / deaths
    -- TODO Weight the results of the dead units higher, or include the total cost of the living?
    GetPerformance = function(self)
        return (self.performance[2] + self.performance[3]) / (self.performance[1] + 1)
    end,

    AddUnit = function(self, unit)
        table.insert(self.rallying_units, unit)
        if self.rally_pos then
            IssueMove({unit}, self:OffsetPosition(self.rally_pos, table.getn(self.rallying_units)))
        end
    end,


















    -- Old below here

    NeedsUnits = function(self)
        if table.getn(self.units) < self.min_strength then
            return true
        end
        return false
    end,

    -- Notify squad it won't get more units
    NoMoreUnits = function(self)
        self.min_strength = 0
    end,

    -- Get rid of the squad; hopefully it doesn't leak
    Destroy = function(self)
        self.terminate = true
        for _, u in self.units do
            u.Squad = nil
        end
    end,

    -- Eventually probably want to add nearby units not distant ones
    AddUnitOld = function(self, unit)
        unit.Squad = self
        if table.getn(self.units) == 0 then
            -- Use near the first target as the rally point
            -- TODO Make sure it's free and accessible
            local tries = 0
            local candidate_position = nil
            while tries < 10 do
                local x = self.targets[1][1] + RandomFloat(-30, 30)
                local z = self.targets[1][3] + RandomFloat(-30, 30)
                local y = GetSurfaceHeight(x, z)
                candidate_position = {x, y, z}
                --if self.map:IsAreaFree(candidate_position) then (Removed function!)
                --    tries = 999
                --end
                tries = tries + 1
            end
            self.squad_position = candidate_position
            LOG("Squad gather position is "..repr(self.squad_position).." after "..tries.." tries")

            -- Micro thread struggles if there are no units
            self.state = "Gathering"
            self.micro_thread = ForkThread(Squad.MicroThread, self)
            self.brain.Trash:Add(self.micro_thread)
        end

        IssueClearCommands({unit})
        IssueAggressiveMove({unit}, self.squad_position)  -- Not sure if attack move is best

        table.insert(self.units, unit)
        table.insert(self.ungathered_units, unit)
    end,

    -- Pick a spot for the unit relative to move position
    CalculateUnitPosition = function(self, unit_index, move_position)
        -- TODO Space the units out; don't shift-G
        return move_position
    end,

    -- Issue move orders, unit by unit.
    -- I intended this to do a formation move for the gathered units, and individual
    -- moves for the distant units.  I may want to make it be that later.
    IssueMoves = function(self, units, move_position, attack)
        local xoff = 0
        local zoff = 0

        for _, u in units do
            local pos = {move_position[1] + xoff, 0, move_position[3] + zoff}
            pos[2] = GetTerrainHeight(pos[1], pos[3])

            if attack then
                IssueAggressiveMove({u}, pos)
            else
                IssueMove({u}, pos)
            end

            -- Spacing of 2; reaching a square at 25 units
            xoff = xoff + 2
            if xoff == 10 then
                xoff = 0
                zoff = zoff + 2
            end
        end
    end,

    CalculateStrengthNearby = function(self)
        local strength = 0
        for _, u in self.units do
            if not u.Dead then
                local bpeco = __blueprints[u.UnitId].Economy
                strength = strength +
                    bpeco.BuildCostMass +
                    bpeco.BuildCostEnergy / 20 +
                    bpeco.BuildTime / 30

            end
        end
        return strength
    end,

    -- What would a good simple implementation be?
    -- Attempt to gather somewhere with a time maximum (or all units) - using individual orders
    -- Everyone that got their moves to the next target together; rest individual move
    -- Do I want to stop accepting reinforcements at the end of gathering?

    MicroThread = function(self)
        local brain = self.brain
        local tick = 0
        while not brain:IsDefeated() and not self.terminate do
            -- Remove dead units from squad
            local alive_units = {}
            for _, unit in self.units do
                if not unit.Dead then
                    table.insert(alive_units, unit)
                end
            end
            self.units = alive_units
            if table.getn(self.units) == 0 then
                LOG("Squad ran out of units - terminating")
                self:Destroy()
                continue
            end

            -- Identify units that are gathered



            -- For each target, try moving the gathered units there en masse, then individually
            -- Then skip on to the next





            -- Is this all something I should represent in an FSM?

            -- Unit FSM:
            -- States>      1:Gathering     2:Gathered
            -- Added        1 M             -
            -- Arrived      2               -
            -- Lost         -               1 M





            -- Squad FSM:
            -- States>      1:Readying      2:Active    3:Stuck
            -- AtStrength   2 F
            -- NoProgress                   3 I         2 S, F
            -- AtTarget                     2 F         2 F
            -- EnemySight   1 A             2 A         3 A

            -- Input notes:
            -- NoProgress means most of the Squad hasn't moved towards its target for 15s (except if attacking)

            -- Actions:
            -- F = Formation move all gathered units, individual move all gathering units; reset progress counter
            -- I = Individual move all units; reset progress counter
            -- A = Attack enemy and reset progress counter
            -- S = Skip to next target and reset progress counter


            -- TODO Is this actually useful?  Maybe just issuing the form attack move will gather them anyway
            -- Move units to the squad
            local units_present = 0
            if self.state == "Gathering" then
                for i, unit in self.units do
                    local distance = VDist3(unit:GetPosition(), self.squad_position)
                    --LOG("Unit is "..distance.." away")
                    if distance > 25 then
                        -- Trying to not mess around so much
                        --IssueClearCommands({unit})  -- TODO: Does this make the units move inefficiently?
                        local u_move_pos = self:CalculateUnitPosition(i, self.squad_position)
                        --LOG("Issuing gathering attack move for "..repr(u_move_pos))
                        -- Seem to get game hangs from this order; but not when I log move pos
                        IssueAggressiveMove({unit}, u_move_pos)  -- Not sure if attack move is best
                    else
                        units_present = units_present + 1
                    end
                end
                LOG("Gathering squad has "..units_present.." units gathered")

                -- Abandon gathering after a minute
                if tick > 600 then
                    LOG("Units didn't arrive fast enough, going anyway")
                    self.min_strength = 0
                end
            end

            -- If we think we're stuck, just move all units to gathering state


            local unit_target = math.max(self.min_strength, table.getn(self.units))
            LOG("Squad in state "..self.state.." has "..units_present.." units gathered, needs "..unit_target)

            -- Send squad to attack target
            if self.state == "Gathering" and units_present >= unit_target then
                LOG("Squad making attack")
                self.state = "Attacking"
                IssueClearCommands(self.units)
                for _, target in self.targets do
                    -- TODO: Heading towards the next target
                    IssueFormAggressiveMove(self.units, target, "AttackFormation", 180)
                end
            end

            -- Shift-G if it's been another minute
            -- TODO: Actually monitor for progress
            if self.state == "Attacking" and tick > 1200 then
                self.state = "Attacking2"  -- This is lazy of me
                local num_moves_left = table.getn(self.units[1]:GetCommandQueue())
                local target_index = table.getn(self.targets) + 1 - num_moves_left
                if target_index < 1 or target_index > table.getn(self.targets) then
                    -- Maybe I messed with them in obs or something
                    target_index = table.getn(self.targets)
                end

                IssueClearCommands(self.units)
                self:IssueMoves(self.units, self.targets[target_index], true)
                for i, target in self.targets do
                    if i > target_index then
                        IssueFormAggressiveMove(self.units, target, "AttackFormation", 180)
                    end
                end

                -- Stop requesting more units once we advance
                --self.min_strength = 0

                -- This is not good, but this all needs replacing...

            end

            -- TODO Retreat from stronger enemies

            WaitTicks(13)
            tick = tick + 13
        end
    end,




})