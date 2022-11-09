-- I want to manage my eco balance
-- The EcoAllocator can return the mass:energy ratio that we'd invest in
-- Can I put mexes and stuff through the EA?  Not sure...
-- How about a modified EA, where we have regular tasks with a priority and mex+pgen with infinite priority

-- Examples (numbers fabricated):
-- Mex = 20s travel time then -3/t, -24/t for 12s total 36, 360; then +2/t, 0
-- Radar = -4/t, -30/t for 10s total 40, 300; then 0, -20/t
-- Factory = -4/t, -30/t for 40s total 160, 1200; then -4/t, -20/t
-- T1 engy = <build costs>; very different if base builder, expander or reclaimer

-- Overall priorities:
-- 1. Don't stall E in the predictable future (ideally target a set amount of overflow that changes over time)
-- 2. Don't stall M much in the predictable future (ideally target a set amount of mass in the bank)
-- 3. Create buildpower when it's usable (this is not a total priority though: need some tanks - so not too much)
-- 4. Expand when possible
-- 5. Build eco / army according to strategy
-- 6. Prioritize increasing whichever of E / M / BP is in shortest supply (may need to include predicted future M?)

-- Strategy priorities:
-- 1. Be able to assign a target percentage of eco to various activites and stick close to that
-- 2. Distinguish between reclaim and ongoing income, and make appropriate BP (facs) investments
-- ?: Should expansion be included as a strategy?  Maybe

---@class EcoManager2
EcoManager2 = ClassSimple({
    __init = function(self, brain)
        self.brain = brain
    end,

    DetermineEcoAvailable = function(self)

    end,


})

-- Possible approach:
-- - Take current eco stats, and maybe include some basic stats from planned expansion / construction
-- - Project stall times and BP coverage
-- - If we have x mass and v mass/second trajectory; we want to get x down to say <100 and v to 0; needing a mass draw of (v+x/t) to do it in t.


-- Can I simplify stuff a bit?
-- Make more use of the actual stats and less of calculation
-- Use predicted impacts to modify the current state and trend?
-- Awkward is that we want to reduce factory count when hitting T2 or T3 potentially

-- I do want early BOs to be largely handled using the same code as later balance






-- An EcoImpact describes the economic effect of an task that has been funded
-- The purpose is to maintain eco balance
-- They aren't suitable for calculating the cost benefit of various tasks: that must happen before
-- Most EcoImpacts may start with an initial delay (for travel) with no economic effect
-- Building a PD then looks like a certain drain during construction, then nothing
-- Building a factory looks like a certain drain during construction, then a different drain during usage
-- - Where a factory has varying drain (e.g. T3 air: engies vs ASF), the factory should express the base (engy) drain only
-- - Building an engineer then might have no EcoImpact; but an ASF EcoImpact expresses the additional E cost
-- - This helps balance eco and transition to T3 air / power
-- A reclaiming engineer is a series of bursts of income
---@class EcoImpact
EcoImpact = ClassSimple({
    ---@param times table Each entry is {ticks after adding, mass/tick, energy/tick starting from that tick}; sorted by tick
    __init = function(self, times)
        self.times = times
        self.startTick = 0
        -- e.g. a factory build in 5s by 1 engy is: {{0, 0, 0}, {50, -6, -60}, {450, -4, -30}}
        -- The last entry carries on forever
    end,

    -- Total net mass impact to a point in time
    ---@param fromTick integer The first tick to count from (excluded)
    ---@param toTick integer The tick to count up to (included)
    ---@return integer Mass consumed in this tick
    ---@return integer Energy consume in this tick
    ResourceNet = function(self, fromTick, toTick)
        local mass, energy = 0, 0
        for _, time in self.times do  -- Actually this is annoying; need to look at the next one as well
            if fromTick >= self.startTick + time[1] then
                -- TODO various cases
                
            end
        end
        return 0, 0
    end,

    -- TODO: Update EcoImpacts for adjacency savings

    ---@param tick integer The tick to check the resource delta in
    ---@return integer Mass consumed in this tick
    ---@return integer Energy consume in this tick
    ResourceDelta = function(self, tick)
        for _, time in self.times do
            if tick >= self.startTick + time[1] then
                return time[2], time[3]
            end
        end
        return 0, 0
    end,

    ---@param tick integer The current tick, used as the start for this EcoImpact
    Start = function(self, tick)
        self.startTick = tick
    end,
})

---@class EcoManager
---@field tick integer
EcoManager = ClassSimple({
    __init = function(self, brain)
        self.tick = 1
        self.brain = brain
        self.ecoImpacts = {}  -- {EcoImpact=true}
        self.predicted_eco = {}  -- {tick={mass, energy}}
    end,

    predictionLoop = function(self)
        local brain = self.brain
        while not brain:IsDefeated() do
            local ticksToStallMass = 99999
            local ticksToStallEnergy = 99999
            local mass = brain:GetEconomyStored('MASS')
            local energy = brain:GetEconomyStored('ENERGY')
            -- That way we use prior team mass overflow by always trying to get to zero mass in 1 minute

            self.predicted_eco[self.tick] = {}



            -- We mustn't build factories if we can't afford the M/E drain
            -- Probably should do that in the Allocator side too

            self.tick = self.tick + 1
            WaitTicks(1)
        end
    end,

    -- Let the root EcoAllocator know that we have available resources
    notifyAvailableResources = function(self, massTick, energyTick)
        -- Decide on the recurring amounts by looking at projected reclaim and constant income
        -- Extra amounts should be income this tick - the projected amount

        local rootAllocator = nil

        rootAllocator:GiveResources()
    end,

    ---@param self EcoManager
    ---@param oldImpact EcoImpact The previous (unmodified) EcoImpact to be updated, or nil if it's new
    ---@param newImpact EcoImpact The new EcoImpact to update to, or nil if we're deleting it
    -- TODO: Make this easier to call
    UpdateEcoImpact = function(self, oldImpact, newImpact)
        -- TODO: Maybe not needed; current implementation just does a full recalc
        newImpact:Start(self.tick)
        -- Add to list
    end,

})





-- Old below

-- The eco manager projects income and expenditure, and requests construction of economy.
-- It's not responsible for getting reclaim or expansion.
-- It monitors other builders and assigns them resources

local Task = import('/mods/TestAI/lua/AI/Production/Task.lua')
local BP = import('/mods/TestAI/lua/AI/Production/Task.lua').BP
local CompareBPUnit = import('/mods/TestAI/lua/AI/Production/Task.lua').CompareBPUnit
local Mapping = import('/mods/TestAI/lua/Map/MapMarkers.lua')

-- TODO: Looks like maybe things get stuck when we hit unit cap?
EcoManager = Class({
    New = function(self, brain)
        self.brain = brain
        self.tasks = {}  -- {what, builders, projected_completion}
        self.eco_stats_smooth = {m_gen=0.0, e_gen=0.0, m_req=0.0, e_req=0.0, m_use=0.0, e_use=0.0, m_rec=0.0, e_rec=0.0}
        self.structures = {FactoryLandT1 = 0, PgenT1=0, estorage=0, FactoryAirT1 = 0}  -- TODO Make this common with Recruiter
        -- If I change this, the ConstructionManager depends on FactoryLandT1^^
        self.structures_to_build = {FactoryLandT1=0, FactoryAirT1=0, PgenT1=0}
        self.structures_wip = {FactoryLandT1={}, FactoryAirT1={}, PgenT1={}}  -- Each is a Task
        self.engineer_activity_queue = {} -- Each element is a task (reclaim / build)
        -- Available engineers will pull tasks from the queue


        -- Each builder is {Builder=<the Builder>, }
        self.builders = {}


        -- If we have one thing with 100 prio and another with 200, we'll assign 2 mass to the latter for each 1 for the former
        -- I guess builders should have a minimum?
        -- Should I be trying to save up mass to go T2 with?  Better than idling factories during the upgrade

        -- Record our upgrade state, so we don't make 2 HQs
        self.land_hq_tech = 1
        self.land_hq_tech_wip = 1
        self.land_sp_upgrading_count = 0
        self.land_hq = nil  -- The upgrading HQ - used for assisting

        self.engineers_wip = 0

        self.eco_monitor_thread = ForkThread(EcoManager.MonitorEconomyThread, self)
        self.brain.Trash:Add(self.eco_monitor_thread)

        self.allocate_thread = ForkThread(EcoManager.AllocateEconomyThread, self)
        self.brain.Trash:Add(self.allocate_thread)

        self.map = Mapping.GetMap(brain)

    end,
    -- TODO: Move most of this logic out of here.  Allocate resources only.

    -- Given the draw of a base is fairly consistent from the factories (except T3 air has engy / air modes)
    -- But engies draw very differently building (lots) assisting ground (cheap) or assisting air (quite lots E)
    
    -- Since a manager needs to handle teching up anyway probably, can just add T3 pgen as an extra stage to T3 air

    -- What's the most practical way to do an economy projection?
    -- Factories should request what they need.
    -- But T3 Air probably needs a T3 pgen, so it should ...initially request engineer funding,
    --     and then switch to ASF (etc) funding once an engy is out?
    -- What about other bumpy stuff, like ACU upgrades?
    -- Probably don't want to go T2 before getting an upgrade on a small map?
    -- Maybe the strategy can handle ACU upgrades: just request a storage and some extra energy
    -- Engineers are tricky: I guess for expanders we can predict arrival times etc

    -- It takes 38s for a T1 pgen to repay

    -- What's the spend of a T1 engineer assisting factories vs building something?
    -- T1 engy uses (3.7, 33) building, (1, 5) assisting LF, (0.5, 23) assisting AF

    -- If a base has a composition of 10+1 factories, and 10 engineers; then my eco flexibility range is:
    -- LFs = (40, 200); AFs = (2, 92); EB = (37, 330), EAL = (10, 50), EAA = (5, 230)
    -- Max = (79, 622); Min not idle = (52, 342)

    -- Aiming to have a good amount of AF assistance will allow them to be pulled off to build power

    -- Say we build power to not stall in 40s time (hard to rush a T3 pgen that fast though).
    -- What about of variation do we need to deal with?  If we go to -100 out of +1000, then
    --     40s means we need 4000 banked; at that income we'd have spent 3750M on pgens, so maybe 500M in storage is good?
    --     So 14k stored 
    -- If we want to be able to absorb a draw of -20%; we need to store 8x our income.
    -- Just funding that -20% would mean spending 750M (at 1k); storaging would cost 450Mish

    -- Let's say that the pacing through the game is a target based on the draw; with enough storage to buffer

    -- Ein < 200: Not going to stall in next 45s; 0 storages
    -- Ein < 500: Not going to stall in 45s if draw was 10% higher; 1 storage
    -- Ein < 1000:
    -- Ein < 3000:
    -- Ein < 6000:

    -- Given a "don't stall in 45s if draw is y higher than expected x", how many storage and pgens is optimal?
    -- Beyond the required pgens for the expected draw, we see that
    -- Stall in 45s at draw of x+y means 45y = stored
    -- Given the draw curve is bumpy, it's not obvious what the best construction order is

    -- Do we ever want to intentionally run down storage?  Kinda complicated though...





    -- T2 Land HQ costs 1410 mass total
    -- 240 is already paid for
    -- 240 is just equivalent to the BP of another T1 LF
    -- T2 pgens are more efficient by 675M per 500E
    -- Assuming we reclaim existing T1 pgens (with some time discounting), the value of units needs to be > 930 - Ein
    -- So really we probably want to make the move when we hit like +300-400E?
    -- Say at +40M we tech up?  Put half our eco into it; then it takes 1 minute

    -- T3 Land HQ costs 5220 mass
    -- 1410 is already paid for
    -- 725 is equivalent to BP of 1.25 more T2 LFs
    -- Per 2500E T3 pgens over T2 save 2760M...
    -- Probably want to go T3 at about 1500E at the latest?
    -- Value of units needs to beat 3085 - (some Ein thing: if we need a whole pgen that's basically grounds alone)
    -- Maybe go at 1000E?  Call it 80-100M?

    -- Probably never want to skip making T1 units in 1v1, but maybe in team games
    -- Other thing is good human players OC T2 units, so initially they're best used away from the ACU



    -- Replace the standard one as well
    -- Do I care about Usage or Requested?
    MonitorEconomyThread = function(self)
        local brain = self.brain
        local m_reclaim_total = 0
        local e_reclaim_total = 0
        local tick_count = 1
        while not brain:IsDefeated() do
            -- Monitor eco
            local m_reclaim_new = brain:GetArmyStat("Economy_Reclaimed_Mass", 0.0).Value
            local e_reclaim_new = brain:GetArmyStat("Economy_Reclaimed_Energy", 0.0).Value
            self.eco_stats_smooth = {
                -- 0.05 means 40% of the value is from the last second and 92% from the last 5s
                -- 0.02 means 18% of the value is from the last second and 64% from the last 5s
                -- 0.01 means 10% of the value is from the last second and 40% from the last 5s
                -- Values reported are for the last second; not 0.1s; so the last multiples are 10xed
                m_gen = self.eco_stats_smooth.m_gen * 0.95 + brain:GetEconomyIncome('MASS') * 0.5,
                e_gen = self.eco_stats_smooth.e_gen * 0.95 + brain:GetEconomyIncome('ENERGY') * 0.5,
                m_req = self.eco_stats_smooth.m_req * 0.95 + brain:GetEconomyRequested('MASS') * 0.5,
                e_req = self.eco_stats_smooth.e_req * 0.95 + brain:GetEconomyRequested('ENERGY') * 0.5,
                m_use = self.eco_stats_smooth.m_use * 0.95 + brain:GetEconomyUsage('MASS') * 0.5,
                e_use = self.eco_stats_smooth.e_use * 0.95 + brain:GetEconomyUsage('ENERGY') * 0.5,

                -- Looks like the eco tracker can't handle having a full bar (which reduces the "in")-Supreme Scoreboard suggests that Income - Requested should be the overflow number...
                -- These are absolute numbers for the game
                m_rec = self.eco_stats_smooth.m_rec * 0.99 + (m_reclaim_new - m_reclaim_total) * 0.01,
                e_rec = self.eco_stats_smooth.e_rec * 0.99 + (e_reclaim_new - e_reclaim_total) * 0.01,
            }
            m_reclaim_total = m_reclaim_new
            e_reclaim_total = e_reclaim_new

            WaitTicks(1)
            if tick_count == 100 then
                tick_count = 0
                LOG("Eco smooth tracker: "..repr(self.eco_stats_smooth))
            end
            tick_count = tick_count + 1
        end
    end,

    -- TODO: I could use GetCurrentUnits() to get the number of pgens etc maybe?

     AllocateEconomyThread = function(self)
        -- First we make buildpower and energy
        -- Then we split up what's left based on what we want
        -- Want to be continuous, in case we use it to predict the future E balance
        -- Do I want to separate out expanding from eco?
        local brain = self.brain
        local acus = brain:GetListOfUnits(categories.COMMAND,false)
        local acu = acus[1]
        while not brain:IsDefeated() do
            -- TODO: Modify eco balance so that it works when we're cheating
            -- This is super dangerous, because if we have 20 engineers and were good, they all try and make a pgen almost at once (each to balance out the previous)
            local target_pgens = math.floor(self.eco_stats_smooth.e_req / 16) -- This is fine and all, but it does request power for all builders to run full time, which is a little excessive
            local target_estorages = math.floor(self.eco_stats_smooth.e_gen / 200)
            -- Roughly one factory per 5 m_gen, but always at least 1 and reduce the number a little initially
            -- Also add one per 10 m_rec
            -- TODO: This isn't a great use of reclaim really^^ - Want to also have future reclaim for a while locked in.
            local target_factories = math.ceil(self.eco_stats_smooth.m_gen / 7) +
                math.floor(self.eco_stats_smooth.m_rec / 16)
            -- TODO Slightly reduce number of early game factories to fuel expansion
            -- I've reduced this to help fund teching up

            -- TODO: Actually tech properly
            local lfs = brain:GetListOfUnits(categories.FACTORY * categories.LAND, false)
            for _, lf in lfs do
                if lf.techCategory == "TECH3" then
                    target_factories = target_factories - 3
                elseif lf.techCategory == "TECH2" then
                    target_factories = target_factories - 1
                end
            end

            -- TODO: Self-destruct excess factories

            local target_airfacs = math.floor((target_factories + 1) / 4)  -- Completely made up...

            -- TODO :Update current counts to allow for structures dying

            -- TODO: This doesn't work at all when there are things that draw E but not M (e.g. radar / shields)
            -- Those structures need to be given a special allowance
            -- Cap power generation to one plus 50% more than what we can afford mass-wise (including reclaim)
            local e_cap = 1.5
            if brain:GetEconomyStored('MASS') < 100 then
                e_cap = 1.0
            end
            local energy_mass_ratio = self.eco_stats_smooth.e_req / self.eco_stats_smooth.m_req
            local e_req_limit = e_cap * energy_mass_ratio * (self.eco_stats_smooth.m_gen + self.eco_stats_smooth.m_rec)
            if self.eco_stats_smooth.e_req > e_req_limit then
                LOG("Limiting energy production target from "..self.eco_stats_smooth.e_req.." to "..e_req_limit)
                target_pgens = 1 + math.floor(e_req_limit / 16)  -- Added the one here for early game
            end

            -- TODO Account for stuff being destroyed (GetCurrentUnits?)

            -- TODO Recruiter has that code to time out old jobs but Eco doesn't...
            self.structures_to_build.FactoryAirT1 = math.max(target_airfacs - self.structures.FactoryAirT1 - table.getn(self.structures_wip.FactoryAirT1), 0)
            self.structures_to_build.FactoryLandT1 = math.max(target_factories - self.structures.FactoryLandT1 - table.getn(self.structures_wip.FactoryLandT1), 0)
            self.structures_to_build.PgenT1 = math.max(target_pgens - self.structures.PgenT1 - table.getn(self.structures_wip.PgenT1), 0)
            
            --LOG("Have: "..repr(self.structures))
            --LOG("WIP: "..repr(self.structures_wip))
            --LOG("To build: "..repr(self.structures_to_build))

            WaitTicks(2)
        end
    end,

    -- Returns a bool indicating whether to upgrade and callback for when the upgrade finishes
    NeedFactoryUpgrade = function(self, factory)
        -- T2 Land HQ
        if self.land_hq_tech == 1 and self.land_hq_tech_wip == 1 and CompareBPUnit(BP.FactoryLandT1, factory) then
            if (self.eco_stats_smooth.m_gen + self.eco_stats_smooth.m_rec) > 40 and self.eco_stats_smooth.e_gen > 200 then
                LOG("Going T2 land")
                self.land_hq_tech_wip = 2
                local callback = function(success)
                    if success then
                        LOG("T2 HQ upgrade succeeded")
                        WaitTicks(10)
                        self.land_hq_tech = 2
                    else
                        LOG("T2 HQ upgrade failed")
                        self.land_hq_tech_wip = 1
                    end
                end
                return true, callback
            end
        end

        -- T3 Land HQ
        if self.land_hq_tech == 2 and self.land_hq_tech_wip == 2 and CompareBPUnit(BP.FactoryLandT2HQ, factory) then
            if (self.eco_stats_smooth.m_gen + self.eco_stats_smooth.m_rec) > 70 and self.eco_stats_smooth.e_gen > 500 then
                LOG("Going T3 land")
                self.land_hq_tech_wip = 3
                local callback = function(success)
                    if success then
                        WaitTicks(10)
                        self.land_hq_tech = 3
                    else
                        -- Actually we might have lost our HQ entirely.
                        -- TODO: Set the current HQ level based on what actually exists
                        self.land_hq_tech_wip = 2
                    end
                end
                return true, callback
            end
        end

        -- Support factories (rate limited to half at once)
        if (self.land_hq_tech == 2 and CompareBPUnit(BP.FactoryLandT1, factory)) or
            (self.land_hq_tech == 3 and CompareBPUnit(BP.FactoryLandT2SP, factory)) then
            local factory_count = table.getn(self.brain:GetListOfUnits(categories.FACTORY * categories.LAND, false))
            if self.land_sp_upgrading_count < factory_count / 2 then
                LOG("Adding support factory")
                self.land_sp_upgrading_count = self.land_sp_upgrading_count + 1
                local callback = function(success)
                    LOG("Finished support factory "..repr(success))
                    self.land_sp_upgrading_count = self.land_sp_upgrading_count - 1
                end
                return true, callback
            end
        end

        return false, nil
    end,

    -- Returns a Task or nil.  The Task must be :Build()ed, or the tracking gets wrong.
    EconomicUnitNeeded = function(self)
        local structure = ""

        -- Prioritize pgens over factories.  Could do this better really.
        if self.structures_to_build.PgenT1 > 0 then
            structure = "PgenT1"
        elseif self.structures_to_build.FactoryLandT1 > 0 then
            structure = "FactoryLandT1"
        elseif self.structures_to_build.FactoryAirT1 > 0 then
            structure = "FactoryAirT1"
        else
            return nil
        end

        -- Set up the build task and tracking
        self.structures_to_build[structure] = self.structures_to_build[structure] - 1
        local next_index = table.getn(self.structures_wip[structure]) + 1
        local build_done = function(success)
            if success then
                self.structures[structure] = self.structures[structure] + 1
            end
            table.remove(self.structures_wip[structure], next_index)
        end
        local task = Task.CreateTask(self.brain, BP[structure], build_done, nil)
        self.structures_wip[structure][next_index] = task
        return task
    end,

    -- Returns a Task that could use the engineer's assistance; or nil if it's not worthwhile.
    EconomicAssistNeeded = function(self, engineer)
        -- TODO Have a real system for sorting tasks by priority
        if table.getn(self.structures_wip.PgenT1) > 0 then
            LOG("Have "..table.getn(self.structures_wip.PgenT1).." pgens in progress")
            local epos = engineer:GetPosition()
            local best_assist_value = 0.0
            local best_assist_task = nil
            for _, task in self.structures_wip.PgenT1 do
                -- We can assume that Task:Build was called, so location is set
                local move_time = VDist2(epos[1], epos[3], task.location[1], task.location[2]) / 2  -- TODO Use actual move speed
                -- TODO Finish
            end


        end



        return nil
    end,

    -- Return a task for an engineer, if we want another
    -- TODO: The rate limit might be bad if we lose factories as implemented currently
    -- TODO: I think I can probably trust the callback happening: add a bool param to it to
    --       distinguish success, and then selectively update the stats.
    RecruitEngineer = function(self, rate_limit, factory)
        if self.engineers_wip >= rate_limit then
            return nil
        end

        -- TODO Need to look at unit.isFinishedUnit to check they're done
        local num_engies = table.getn(self.brain:GetListOfUnits(categories.ENGINEER, true, false))
        if num_engies > 80 then
            return nil
        end

        -- TODO: This calculation sucks: ignore lots of important factors
        local want_engies = 80
        --    4 * self.structures_to_build.FactoryLandT1 +
        --    2 * self.structures_to_build.PgenT1 +
        --    table.getn(mexes)

        if want_engies - num_engies - self.engineers_wip > 0 then
            self.engineers_wip = self.engineers_wip + 1
            local engy_done = function()
                self.engineers_wip = self.engineers_wip - 1
            end
            return Task.CreateTask(self.brain, BP.EngyT1, engy_done, nil)
        end
        return nil
    end,

    -- Incorporate current build power, assist ETA, % progress and so on
    UpdateFinishProjections = function(self)

    end,

    -- Predict if we'll stall; returning {'Mass': 12, 'Energy': 60} meaning number of seconds to stall.
    PredictStall = function(self, additionalMassDrain, additionalEnergyDrain)


    end,


    PauseEnergyConsumers = function(self)

    end,

    -- Is it better to run an economy based on stall projections, or on a mass projection with an energy ratio?
    -- Probably stall prediction is best at the start, and then move to a ratio?
    -- How do you handle something like "Go T3 Air, make engy and pgen to afford running the factory"?  Shouldn't pre-eco for the factory.

})