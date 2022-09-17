local BP = import('/mods/TestAI/lua/AI/Production/Task.lua').BP
local Task = import('/mods/TestAI/lua/AI/Production/Task.lua')
local Mapping = import('/mods/TestAI/lua/Map/MapMarkers.lua')

Recruiter = Class({
    New = function(self, brain)
        self.brain = brain
        self.map = Mapping.GetMap(brain)
        self.counts = {
            -- Names must match the BP table
            LandScoutT1 = {Current=0, Desired=0, InProgress=0, WIPStartTicks = {}},
            AAT1 = {Current=0, Desired=0, InProgress=0, WIPStartTicks = {}},
            TankT1 = {Current=0, Desired=0, InProgress=0, WIPStartTicks = {}},
            ArtyT1 = {Current=0, Desired=0, InProgress=0, WIPStartTicks = {}},
        }
        self.enemy_army_estimated_threat = 0 -- I think this will be useful to track, to help prioritize the army build requests
        self.tick = 0  -- Actually these are 1s

        self.recruitment_thread = ForkThread(Recruiter.RecruitmentThread, self)
        brain.Trash:Add(self.recruitment_thread)
    end,

    RecruitmentThread = function(self)
        local log_tick = 0
        while not self.brain:IsDefeated() do
            self.tick = self.tick + 1
            self:UpdateCurrentDesiredCounts()
            WaitTicks(10)
            log_tick = log_tick + 1
            if log_tick == 10 then
                log_tick = 0
                LOG("Recruiter updated counts: "..repr(self.counts))
            end
        end
    end,

    -- Look at our current army breakdown, work in progress and desired composition
    UpdateCurrentDesiredCounts = function (self)
        local brain = self.brain
        self.counts["LandScoutT1"].Current = table.getn(brain:GetListOfUnits(categories.LAND * categories.SCOUT * categories.MOBILE, false))
        self.counts["AAT1"].Current = table.getn(brain:GetListOfUnits(categories.LAND * categories.ANTIAIR * categories.MOBILE, false))
        self.counts["TankT1"].Current = table.getn(brain:GetListOfUnits(categories.LAND * categories.DIRECTFIRE * categories.MOBILE - categories.COMMAND, false))
        self.counts["ArtyT1"].Current = table.getn(brain:GetListOfUnits(categories.LAND * categories.INDIRECTFIRE * categories.MOBILE, false))
        -- TODO: Make sure that this function excludes incomplete units and includes moving ones

        -- This intentionally double counts units like the Nomads AA+Arty.
        -- This is necessary so we don't get stuck thinking we're good all round and not building anything.
        -- Actually, it seems like Tank Destroyers get built as "arty" (indirectfire) and AA/Arty as AA.
        -- I guess this is kinda fun?
        local total_army_size = 0
        for _, uc in self.counts do
            total_army_size = total_army_size + uc.Current
        end

        -- Army should be bigger than it is now.
        total_army_size = total_army_size + 10

        -- Would like to attach engineers to the army in future
        self.counts["LandScoutT1"].Desired = 3 + math.floor(total_army_size * 0.1)
        -- TODO: When we make planes, decrease AA mix
        self.counts["AAT1"].Desired = math.max(math.floor(total_army_size * 0.1) - 1, 0)  -- Ideally modify based on air situation
        if self.map.threat:GetStrengthRatio(6) > 1.2 then
            -- Make twice as much MAA if we aren't doing well on air
            self.counts["AAT1"].Desired = self.counts["AAT1"].Desired + math.floor(total_army_size * 0.1)
        end
        self.counts["ArtyT1"].Desired = math.max(math.floor(total_army_size * 0.1) - 2, math.floor(total_army_size * 0.2) - 10, 0)
        self.counts["TankT1"].Desired = total_army_size - self.counts["LandScoutT1"].Desired - self.counts["AAT1"].Desired - self.counts["ArtyT1"].Desired

        -- TODO: Maybe reinstate this, but I think it does more harm than good
        -- Remove the in progress units that have took too long (define this as 2000 ticks for land: 4x a percy's BT): maybe the factory was lost or something
        --[[
        for u, uc in self.counts do
            local still_wip_ticks = {}
            for _, wip_tick in uc.WIPStartTicks do
                if wip_tick + 2000 < self.tick then
                    table.insert(still_wip_ticks, wip_tick)
                else
                    LOG("Giving up on a "..u.." from "..wip_tick)
                end
            end
            uc.InProgress = table.getn(still_wip_ticks)
            uc.WIPStartTicks = still_wip_ticks
        end
        ]]

    end,

    -- Returns a Task
    RecruitUnit = function(self, factory)
        local worst_ratio = 1000000
        local worst_unit = nil  -- As long as counts isn't empty we'll always find something to make
        for unit, unit_counts in self.counts do
            -- This is a hokey attempt to have the most populous unit that's at or above ratio get built more if needed
            local ratio = (unit_counts.Current + unit_counts.InProgress + 0.1) / (unit_counts.Desired + 0.05)
            if ratio < worst_ratio then
                worst_ratio = ratio
                worst_unit = unit
            end
        end

        -- TODO: This is terrible; remove, but all this should be refactored to use Army anyway
        local bp = BP[worst_unit]
        if factory.techCategory == "TECH3" then
            if worst_unit == "TankT1" then
                bp = BP.RaiderT3
            elseif worst_unit == "ArtyT1" then
                bp = BP.RangeT3
            elseif worst_unit == "AAT1" then
                bp = BP.AAT3
            end
        elseif factory.techCategory == "TECH2" then
            if worst_unit == "TankT1" then
                bp = BP.TankT2
            elseif worst_unit == "ArtyT1" then
                bp = BP.MMLT2
            elseif worst_unit == "AAT1" then
                bp = BP.AAT2
            end
        end

        -- Build unit!
        table.insert(self.counts[worst_unit].WIPStartTicks, self.tick)
        self.counts[worst_unit].InProgress = self.counts[worst_unit].InProgress + 1

        local unit_done = function(success)
            LOG("Unit_done - modifying counts")
            self.counts[worst_unit].InProgress = self.counts[worst_unit].InProgress - 1
            table.remove(self.counts[worst_unit].WIPStartTicks, 1)  -- Assume it was the one started first
            -- Current counts updated separately, so don't care if succeeded or failed
        end
        return Task.CreateTask(self.brain, bp, unit_done, nil)
    end

    -- TODO: Actually feed back when a unit is done...  Kinda important
})
