
local Task = import('/mods/TestAI/lua/AI/Production/Task.lua')
local BP = import('/mods/TestAI/lua/AI/Production/Task.lua').BP
local Recruiter = import('/mods/TestAI/lua/AI/Armies/Recruiter.lua')
local EcoManager = import('/mods/TestAI/lua/AI/Production/EcoManager.lua')
local Expander = import('/mods/TestAI/lua/AI/Production/Expander.lua')
local Map = import('/mods/TestAI/lua/Map/Map.lua')

-- Construction todolist:
-- - Assist jobs when possible
-- - When do we want factories outside the base?  When it's a difficult to reach (far / plateau / island) expn.

ConstructionManager = Class({
    New = function(self, brain)
        self.brain = brain
        self.map = Map.GetMap(brain)

        self.acus = {}
        self.engies = {}
        self.factories = {}
        
        self.recruiters = {}  -- Elements are {Army=<Army>, Categories=<categories on factories>, Zone=<zone or nil>}

        self.recruiter = Recruiter.Recruiter()  -- This is the legacy land only one.  TODO: Remove
        self.recruiter:New(brain)

        self.eco_manager = EcoManager.EcoManager()
        self.eco_manager:New(brain)

        self.expander = Expander.Expander()
        self.expander:New(brain)
        self.num_expanding = 0

        self.factory_orders_thread = ForkThread(ConstructionManager.FactoryOrdersThread, self)
        self.brain.Trash:Add(self.factory_orders_thread)
        
        self.engy_orders_thread = ForkThread(ConstructionManager.EngineerOrdersThread, self)
        self.brain.Trash:Add(self.engy_orders_thread)
        
        self.cdr_orders_thread = ForkThread(ConstructionManager.CommanderOrdersThread, self)
        self.brain.Trash:Add(self.cdr_orders_thread)

        -- TODO Run the UpdateBuildersThread, once it actually does something
    end,

    -- TODO: Use this for land too
    RegisterUnitRecruiter = function(self, army, factory_categories, recruit_zone)
        table.insert(self.recruiters, {Army=army, Categories=factory_categories, Zone=recruit_zone})
    end,

    -- Reconcile our list of engineers and factories with what we have
    -- Not currently in use
    UpdateBuildersThread = function(self)
        local brain = self.brain
        while not brain:IsDefeated() do
            -- TODO Probably bad bool params too
            self.acus = brain:GetListOfUnits(categories.COMMAND, false)
            self.engies = brain:GetListOfUnits(categories.ENGINEER, false)
            self.factories = brain:GetListOfUnits(categories.FACTORY, false)

            -- TODO: Check GetFractionComplete() == 1 on the units

            -- TODO Reassign tasks whose engineers died
            -- TODO Make emergency things, like MAA

            WaitTicks(5)
        end
    end,

    -- Maybe I want to test something in a more controller scenario
    -- Comment this out if not wanted
    DebugMaybeDontBuildAnything = function(self)
        --WaitTicks(1000000)
    end,

    -- For testing ACU usage
    -- Comment this out if not wanted
    -- Returns true if the commander should keep building
    DebugCommanderKeepBuilding = function(self)
        local keep_building = true
        local facs = self.brain:GetListOfUnits(categories.FACTORY, true, false)
        -- Comment this line out to have the ACU stay and build forever
        --keep_building = (not facs) or table.getn(facs) < 3
        return keep_building
    end,

    CommanderOrdersThread = function(self)
        self:DebugMaybeDontBuildAnything()
        local brain = self.brain
        while not brain:IsDefeated() do
            local cdrs = brain:GetListOfUnits(categories.COMMAND, true, false)
            for _, cdr in cdrs do
                if cdr and not cdr.Dead and not cdr.TestAITask and table.getn(cdr:GetCommandQueue()) < 1 and self:DebugCommanderKeepBuilding() then
                    LOG("Getting order for idle ACU")
                    local got_order = self:IssueEngineerOrder(cdr, 9999)
                end
            end
            WaitTicks(2)
        end
    end,

    EngineerOrdersThread = function(self)
        self:DebugMaybeDontBuildAnything()
        local brain = self.brain
        local current_tick = 0
        local last_reclaim_weight = 1.2  -- First engineer slightly prefers reclaim to mexes
        while not brain:IsDefeated() do
            local num_expanding = 0
            current_tick = current_tick + 5  -- Should match the wait at the end
            local engies = brain:GetListOfUnits(categories.ENGINEER - categories.COMMAND, false, false)
            -- Obviously terrible, but I'm worried we're somehow catching it before it's ready for an order
            for _, engy in engies do
                if engy.Dead or engy:GetFractionComplete() ~= 1 then
                    continue
                end
                if engy.IsExpander then
                    num_expanding = num_expanding + 1
                end
                if not engy.FirstSeenTick then
                    engy.FirstSeenTick = current_tick
                    continue
                end
                -- Still experimenting a bit with the tick timing
                if engy and engy.FirstSeenTick + 40 < current_tick and not engy.Dead and not engy.TestAITask then
                    if not engy.LeftFactory then
                        -- We haven't tried to do anything with this engy, so clear the move command to the rally
                        engy.LeftFactory = true
                        IssueClearCommands({engy})
                        -- At most 2/3 the engies can expand
                        if self.num_expanding < 0.666 * table.getn(engies) then
                            engy.IsExpander = true
                            -- Make some engineers prefer mexes and some reclaim
                            -- Need to build mexes even on high reclaim maps, and get reclaim even with open mexes (e.g. because they're guarded)
                            last_reclaim_weight = last_reclaim_weight - 0.2
                            if last_reclaim_weight < 0.1 then
                                last_reclaim_weight = 2.0
                            end
                            engy.ReclaimWeight = last_reclaim_weight
                        end
                    end
                    self:IssueEngineerOrder(engy, table.getn(engies))
                end
            end
            self.num_expanding = num_expanding
            WaitTicks(5)
        end
    end,

    -- Engineer must be alive and ready and so on
    -- Returns whether any orders were issued
    IssueEngineerOrder = function(self, engy, num_engies)
        if engy.IsExpander then
            -- Try and expand
            local expand_done = function(success)
                self.num_expanding = self.num_expanding - 1
            end
            local task = self.expander:Expand(engy, expand_done, engy.ReclaimWeight, 10000)
            if task then
                engy.TestAITask = task  -- Redundant
                self.num_expanding = self.num_expanding + 1
                task:Build(nil, {engy})
                return true
            end
        else
            local task = self.eco_manager:EconomicUnitNeeded()
            if task then
                engy.TestAITask = task
                task:Build(nil, {engy})
            else
                -- Try and build a nearby mex
                task = self.expander:Expand(engy, nil, 0.1, 15)
                if task then
                    engy.TestAITask = task
                    task:Build(nil, {engy})
                end
            end
            return true
        end
        -- No other engy will be able to do anything either
        LOG("Nothing for engineers to do")
        return false
    end,

    FactoryOrdersThread = function(self)
        self:DebugMaybeDontBuildAnything()
        local brain = self.brain
        while not brain:IsDefeated() do
            local factories = brain:GetListOfUnits(categories.FACTORY, true, false)
            -- This is not very efficient with many armies
            for _, factory in factories do
                if factory and not factory.Dead and factory:GetFractionComplete() == 1 and table.getn(factory:GetCommandQueue()) < 2 then
                    LOG("Factory ready for orders "..factory.UnitId)
                    local best_priority = 0
                    local request = nil
                    for _, recruiter in self.recruiters do
                        LOG("Checking recruiter")
                        if EntityCategoryContains(recruiter.Categories, factory) then
                            LOG("Category match")
                            if recruiter.Zone then
                                -- If we're limited to a zone, skip other units
                                local sq = self.map:GetSquare(factory:GetPosition())
                                if sq and sq.Zone.Land ~= recruiter.Zone then
                                    LOG("Zone wrong")
                                    continue
                                end
                            end
    
                            -- We have an idle factory of the right category and zone for the recruiter
                            request = recruiter.Army:ChooseBuildUnit(factory)
                            best_priority = math.max(best_priority, request.Priority)
                        end
                    end
    
                    -- Upgrade
                    local do_upgrade, callback = self.eco_manager:NeedFactoryUpgrade(factory)
                    if do_upgrade then
                        local task = Task.CreateTask(brain, nil, callback, nil, true)
                        factory.TestAITask = task
                        task:Build(factory, {})
                        -- TODO: Revamp priorities and decision making
                        -- For now just always prioritize upgrades
                        best_priority = 0
                    end

                    if best_priority > 0 then
                        -- An army wants a unit
                        -- TODO: Add done() callback and WIP tracking for all armies
                        local task = Task.CreateTask(brain, request.Unit, nil, nil)
                        factory.TestAITask = task  -- TODO Remove: we queue up multiple anyway...?  Useful as "exists" maybe?
                        -- TODO: Understand refcounts^^ I think the task survives anyway?  Saved by its own thread?
                        task:Build(factory, {})
                    end

                end
            end
            WaitTicks(3)

            -- TODO: Remove legacy land only code that follows
            -- Must do if there's any overlap with the above
            -- Comments on this are misleading around the bool params
            -- Trying setting false on the first param
            -- Have settled for the if tests below
            local idle_factories = brain:GetListOfUnits(categories.FACTORY * categories.LAND, true, false)
            local num_factories = table.getn(idle_factories)  -- Actually do need the non-idle ones here
            for _, factory in idle_factories do
                -- Finished factories with build queues shorter than 2 only
                if factory and not factory.Dead and factory:GetFractionComplete() == 1 and table.getn(factory:GetCommandQueue()) < 2 then
                    LOG("Getting orders for near idle factory")
                    -- TODO Might want to skip factories in weird islands etc

                    -- Engineer production rate limit: 0.5 factories if we have 1 factory, then 2 factories max
                    local rate_limit = 4 + math.floor(num_factories / 2)
                    -- Special exception to allow 4 starting engies
                    if num_factories < 2 and table.getn(brain:GetListOfUnits(categories.ENGINEER - categories.COMMAND, true, false)) > 1 then
                        rate_limit = 1
                    elseif num_factories == 2 then
                        rate_limit = 3
                    end
                    local task = self.eco_manager:RecruitEngineer(rate_limit, factory)
                    if not task then  -- Rate limited
                        task = self.recruiter:RecruitUnit(factory)
                    end

                    -- TODO Now that I'm queuing orders, this is getting replaced, but it seems fine...  Not really sure how the refcounting works.
                    factory.TestAITask = task
                    task:Build(factory, {})
                end
            end
            WaitTicks(3)
        end
    end,

})