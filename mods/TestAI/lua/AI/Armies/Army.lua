local Map = import('/mods/TestAI/lua/Map/Map.lua')
local Mapping = import('/mods/TestAI/lua/Map/MapMarkers.lua')
local Squad = import('/mods/TestAI/lua/AI/Armies/Squad.lua')

-- Initialization that applies to all armies.
-- Store everything in the brain, which will hopefully help with teams and such
function Init(brain)
    brain.TestAIRecruitThread = ForkThread(RecruitTroopsThread, brain)
    brain.Trash:Add(brain.TestAIRecruitThread)

    brain.TestAIArmiesInitialized = true
    brain.TestAIArmies = {}  -- Descending priority order
end

function NewArmy(brain, army)
    table.insert(brain.TestAIArmies, army)
    LOG("Added new army - there are now "..table.getn(brain.TestAIArmies))

    -- Just sort by priority.  If we ever have a lot, filtering by zone / category first might be better.
    -- TODO: Allow armies to have non-linear priority based on their size or desired unit composition
    table.sort(brain.TestAIArmies, function(a, b) return a.priority > b.priority end)
end

function RecruitTroopsThread(brain)
    local map = Map.GetMap(brain)
    WaitTicks(50)
    local tick = 0
    while not brain:IsDefeated() do
        -- TODO: Allow categories.COMMAND when I build SCUs
        local all_military = brain:GetListOfUnits(categories.MOBILE - categories.ENGINEER - categories.COMMAND - categories.UNSELECTABLE, false)
        for _, unit in all_military do
            if unit.TestAIArmy ~= nil then
                continue
            end
            -- We're getting here
            LOG("FirstSeen: "..repr(unit.TestAIFirstSeenTick))
            LOG("Dead: "..repr(unit.Dead))
            LOG("Complete: "..repr(unit:GetFractionComplete()))
            if not unit.TestAIFirstSeenTick and (not unit.Dead) and unit:GetFractionComplete() == 1 then  -- Don't remove ==false: unit.Dead gets set up in the OnCreated call
                unit.TestAIFirstSeenTick = tick
                -- Not here
                LOG("Adding tick")
                continue
            end
            -- But yes here
            LOG("RTT loop 3")
            if not unit.TestAIFirstSeenTick then
                continue  -- This is catching _EVERYTHING_  -- OK so this is supposed to be the one hit for incomplete units
                -- TODO: Have a skip on incomplete above this
            end
            -- But never hever
            LOG("RTT loop 4")

            -- TODO: Test this value (especially with land units)
            -- Allow 60 ticks of roll-off; and having no orders
            if unit.TestAIFirstSeenTick + 60 < tick and not unit.Dead and table.getn(unit:GetCommandQueue()) == 0 then
                -- The armies are in descending priority order: see if any are interested
                LOG("New unit being assigned to an army")
                for _, army in brain.TestAIArmies do
                    if army.recruit_zone then
                        LOG("Checking zone")
                        -- If we're limited to a zone, skip other units
                        local sq = map:GetSquare(unit:GetPosition())
                        -- TODO: Support zone restrictions other than land
                        if sq and sq.Zone.Land ~= army.recruit_zone then
                            LOG("Wrong zone")
                            continue
                        end
                    end
                    if EntityCategoryContains(army.unit_categories, unit) then
                        LOG("Entity category match")
                        -- Unit is ready
                        unit.TestAIArmy = army
                        local success, err = pcall(Army.UnitAddedBase, army, unit)
                        if not success then
                            LOG("Warning: failed adding unit: "..repr(err))
                        end
                        break
                    end
                end
            end
        end
        WaitTicks(17)
        tick = tick + 17
    end
end

-- Base class for an army
Army = Class({

    -- Recruit zone is optional
    New = function(self, brain, factory_categories, unit_categories, priority, recruit_zone)
        self.brain = brain

        self.units = {}  -- All the units in the army
        self.rallied_units = {}  -- Ones that have joined the main group
        self.rallying_units = {}  -- Ones that are on the way

        self.map = Map.GetMap(brain)
        self.old_map = Mapping.GetMap(brain)

        -- ConstructionManager uses these (and calls ChooseBuildUnit), but that should be moved to here.
        self.factory_categories = factory_categories
        self.unit_categories = unit_categories
        self.recruit_zone = recruit_zone
        self.priority = priority

        if not brain.TestAIArmiesInitialized then
            Init(brain)
        end
        NewArmy(brain, self)

    end,

    -- Grab units from other armies that have lower priorities
    -- near_position is optional
    RequestUnits = function(self, categories, count, near_position)

        -- Clear commands when reassigning units
    end,

    -- Returns {Unit=<unit BP list entry>, Priority=<number>}
    -- Priority should be independent of unit cost (i.e. contribution / cost)
    -- <0 will never be chosen
    -- If omitted, then this Army will never pick what factories build
    -- factory will always match the Army's factory_categories
    ChooseBuildUnit = function(self, factory)
        return {Unit=nil, Priority=-1}
    end,

    -- Callback when a unit is started (maybe following ChooseBuildUnit())
    -- TODO: Actually call this
    UnitStarted = function(self, unit)
        LOG("warning: Abstract method called: UnitStarted on ".. repr(self))
    end,

    -- Go through a list of units, and remove any that have died or been removed from the army
    -- Returns the filtered list, the total cost of died units, the total kills of the dead units, and the total kills of the live units
    -- This function must be used, otherwise performance isn't tracked properly
    UpdateUnitList = function(self, unit_list)
        local new_list = {}
        local total_lost = 0
        local total_killed_dead = 0
        local total_killed_living = 0
        for _, u in unit_list do
            -- These don't work when the unit dies I think
            local killed = u.Sync.totalMassKilledTrue or 0
            if u.Dead then
                -- Record performance of units
                local value = self.map.threat_map:GetBlueprintThreat(u.UnitId).V
                if u.TestAIArmy == self and u.Dead and not u.TestAIVeterancyCounted then
                    total_lost = total_lost + value
                    total_killed_dead = total_killed_dead + killed
                    u.TestAIVeterancyCounted = true
                end
                LOG("Unit died: removed from army")
            elseif u.TestAIArmy ~= self then
                LOG("Unit moved to different army")
            else
                total_killed_living = total_killed_living + killed
                table.insert(new_list, u)
            end
        end
        return new_list, total_lost, total_killed_dead, total_killed_living
    end,


    -- position might be provided by GetAveragePosition()
    -- Returns {distant units}, {not distant units}
    GetDistantUnits = function(self, units, position, max_distance)
        local near, far = {}, {}
        for _, u in units do
            if VDist3(u:GetPosition(), position) > max_distance then
                table.insert(far, u)
            else
                table.insert(near, u)
            end
        end
        return far, near
    end,

    -- Also worried about WaitTicks being used in the callback
    UnitAddedBase = function(self, unit)
        LOG("Base unit added")
        table.insert(self.units, unit)
        self:UnitAdded(unit)
    end,

    -- Notify an army that it's been given a new unit (already in the units list)
    -- WaitTicks must not be called in this thread
    -- If not overriden, then the unit will be send to the armies position
    UnitAdded = function(self, unit)
        -- If this function hasn't been overriden, just send the unit to the army's average position
        table.insert(self.rallying_units, unit)
    end,
    

    -- Notify an army that it's had a unit removed (already gone from the units list)
    -- WaitTicks must not be called in this thread
    UnitRemoved = function(self, unit)
        LOG("warning: Abstract method called: UnitRemoved on "..repr(self))
    end,

})


--[[
New design for armies:
- Want small flexible subgroups
- Monitor performance per subgroup, but allow the specific code to interpret
- Army requests resources and units

- I probably want a global air force
- Navy and land per zone
- Maybe a hover army?  Or is that a group?

- Standardize the unit lists within a group, and use groups for separating types of units and such

- Should a group be a class?  I guess so?
- Squads (name for a group) will operate in a single location.

]]