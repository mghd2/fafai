local AIBuildStructures = import('/lua/AI/aibuildstructures.lua')
local AIUtils = import('/lua/AI/aiutilities.lua')
local Map = import('/mods/TestAI/lua/Map/Map.lua')

-- Task enhancements we need:
-- What does ExecuteBuildStructure do?
-- We've already got picking the BP and location
-- Then it's AddToBuildQueue like we are
-- EngineerTryReclaimCaptureArea (there's also a Sorian version); might be better to issue a move and then this when we're close
-- So we can see / get more recent stuff
-- brain:BuildStructure (C function; doesn't return the task)


-- TODO: Make sure that I never set a variable on a unit that another TestAI might want to set on.

-- TODO: Use subclasses not these silly optional parameters
Task = Class({
    -- (Optional) blueprint is required unless it's a resource or an upgrade
    -- (Optional) callback takes one bool: true iff build succeeded - intended to be a closure.  Always false for Reclaim.
    -- (Optional) resource is for mexes, hydros and reclaim.  It is a square (from the Map)
    -- (Optional) upgrade (bool) is true if this is upgrading a structure
    -- Note that this function isn't allowed to immediately call the callback.  It has to return first so the caller can set stuff up.
    New = function(self, brain, blueprint, callback, resource, upgrade)
        self.brain = brain
        self.location = nil  -- Build location (x, y, z)
        self.blueprint = blueprint
        self.blueprint_id = ""  -- Filled in later.  "" if not building.
        self.callback = callback
        self.resource = resource
        self.status = "NotStarted"  -- NotStarted | InProgress | Complete
        self.map = Map.GetMap(brain)
        self.upgrade = upgrade or false
    end,

    -- Factory can be nil; required for upgrades
    Build = function(self, factory, engineers)
        LOG("Doing build")
        self.factory = factory
        self.engineers = engineers -- These need to be the brains unit class (whatever that actually is called)
        for _, engy in engineers do
            engy.TestAITask = self
        end

        if self.upgrade then
            local faction = factory.factionCategory
            local layer = factory.layerCategory
            local tech = factory.techCategory
            local next_tech = "TECH3"
            local tech_suffix = "T3"
            if tech == "TECH1" then
                next_tech = "TECH2"
                tech_suffix = "T2"
            end
            local bp_name
            if self.brain:CountHQs(faction, layer, next_tech) > 0 then
                -- Make a support factory
                bp_name = "Factory"..LAYER_SUFFIX[layer]..tech_suffix.."SP"
            else
                -- Make an HQ
                bp_name = "Factory"..LAYER_SUFFIX[layer]..tech_suffix.."HQ"
            end
            self.blueprint_id = BP[bp_name][faction]
        elseif factory then
            self.blueprint_id = self.blueprint[factory.factionCategory]
        elseif self.blueprint ~= "" then
            self.blueprint_id = self.blueprint[engineers[1].factionCategory]
        end
        self.build_thread = ForkThread(self.BuildThread, self)
        self.brain.Trash:Add(self.build_thread)
    end,

    -- Build must have been called
    GetETA = function(self)
        if self.status == "InProgress" then
            -- TODO: Calculate
            return 20.0
        end
        return 0.0
    end,

    AddEngineers = function(self, engineers)
        LOG("Want to add an engineer")

    end,

    -- Build a resource square (reclaim / mexes / hydros)
    -- Get reclaim first, then build hydros, then mexes
    -- Returns whether it succeeded
    EngineerBuildResource = function(self)
        -- TODO: Maybe if there's a lot of value there, put in a claim less than 1
        -- Would be interesting if a second engineer running the same code could end up assisting construction
        -- Would need to add assist logic though.
        local claim = self.map:GetClaim(self.resource, "R", 1)

        -- Move to the square
        self.location = self.resource.P
        if not self:EngineerMove(claim) then
            return false
        end

        -- Reclaim or capture everything in the square; waiting for the capture if there's something to grab
        local reclaiming = AIUtils.EngineerTryReclaimCaptureArea(self.brain, self.engineers[1], self.location)
        if reclaiming and not self:EngineerWaitUntilDone(claim) then
            return false
        end
        
        local recs = GetReclaimablesInRect(self.location[1]-3.5, self.location[3]-3.5, self.location[1]+3.5, self.location[3]+3.5)
        if recs then
            LOG("Found "..table.getn(recs).." reclaimables")
            for _, rec in recs do
                -- Note: changes here must be reflected in EngineerMove and Resources.lua
                if rec and rec.MaxMassReclaim and rec.MaxMassReclaim * rec.ReclaimLeft > 3 then
                    IssueReclaim({self.engineers[1]}, rec)
                end
            end
        end

        -- Build hydros
        local blueprint_id = BP.Hydro[self.engineers[1].factionCategory]
        for _, hydro_pos in self.resource.HydrosFree do
            IssueBuildMobile({self.engineers[1]}, hydro_pos, blueprint_id, {})
        end

        -- Build mexes
        blueprint_id = BP.MexT1[self.engineers[1].factionCategory]
        for _, mex_pos in self.resource.MexesFree do
            IssueBuildMobile({self.engineers[1]}, mex_pos, blueprint_id, {})
        end

        if not self:EngineerWaitUntilDone(claim) then
            return false
        end
        self.map:ReleaseClaim(claim)
        return true
    end,

    -- Move to self.location if necessary
    -- claim is optional, for resources only.  Will be maintained during movement.
    -- Returns true once the engineer has arrived, or false if it died
    EngineerMove = function(self, claim)
        local bp = self.engineers[1]:GetBlueprint()
        local build_radius = 5
        if bp then
            build_radius = bp.Economy.MaxBuildDistance
        end
        local approach_distance = build_radius
        if claim then
            local recs = GetReclaimablesInRect(self.location[1]-3.5, self.location[3]-3.5, self.location[1]+3.5, self.location[3]+3.5)
            local no_recs = true
            if recs then
                no_recs = table.empty(recs)
                if not no_recs then
                    -- We only really care about reclaimables with at least 4 mass
                    no_recs = true
                    for _, rec in recs do
                        -- Note: changes here must be reflected in EngineerBuildResource
                        if rec and rec.MaxMassReclaim and rec.MaxMassReclaim * rec.ReclaimLeft > 3 then
                            no_recs = false
                        end
                    end
                end
            end
            local mex_count = table.getn(self.resource.MexesFree)
            local hydro_count = table.getn(self.resource.HydrosFree)
            -- Change location to the single marker in the square, so we can build from max range
            if mex_count == 1 and hydro_count == 0 and no_recs then
                self.location = self.resource.MexesFree[1]
            elseif mex_count == 0 and hydro_count == 1 and no_recs then
                self.location = self.resource.HydrosFree[1]
            else
                -- Need to go to the center of the square
                approach_distance = math.max(0, approach_distance - 5)
            end
        end

        -- TODO: Add a portion of the skirt size or something - can build factories further away (unless reclaiming)
        local eng_pos = self.engineers[1]:GetPosition()
        local distance = VDist2(self.location[1], self.location[3], eng_pos[1], eng_pos[3])
        if approach_distance < distance then
            -- TODO: Might be better to move further than needed to save moving for future tasks
            -- TODO: Consider pathability; and share this function with find point at max range type code
            local move_position = {
                MATH_Lerp(approach_distance / distance, self.location[1], eng_pos[1]),
                0,
                MATH_Lerp(approach_distance / distance, self.location[3], eng_pos[3])
            }
            move_position[2] = GetTerrainHeight(move_position[1], move_position[3])

            local mcmd = IssueMove({self.engineers[1]}, move_position)
            LOG("Move needed: command was "..repr(mcmd))  -- This works

            -- Wait a bit for the move
            -- TODO: Move can actually be nil.  Not sure when, but it can.
            -- TODO Should we retry, or just give up?
            if mcmd then
                while (not self.brain:IsDefeated()) and self.engineers[1] and (not self.engineers[1].Dead) and not IsCommandDone(mcmd) do
                    if claim then
                        self.map:RefreshClaim(claim)
                    end
                    WaitTicks(5)
                end
                LOG("Move complete")
            end
        end

        if self.brain:IsDefeated() or self.engineers[1].Dead then
            return false
        end
        return true
    end,

    -- Wait for all the engineer's queued commands to complete
    -- claim is optional, for resources only.  Will be maintained during construction.
    -- Returns true once the engineer is finished, or false if it died
    EngineerWaitUntilDone = function(self, claim)
        -- Maybe the build command is the last thing in the build queue?  Not sure if that's reliable though.
        -- Seems like it would probably work; and should allow for queuing multiple builds
        -- TODO^^
        local success = false
        local ticks_spent = 5
        WaitTicks(5)  -- Wait for the commands to register with GetCommandQueue()
        while (not self.brain:IsDefeated()) and self.engineers[1] and (not self.engineers[1].Dead) and (not success) do
            if table.empty(self.engineers[1]:GetCommandQueue()) then
                success = true
                break
            end
            if claim then
                self.map:RefreshClaim(claim)
            end
            ticks_spent = ticks_spent + 5
            WaitTicks(5)
            -- TODO: Probably add a timeout?  Maybe do it as something like no progress rather than a time limit?
        end
        LOG("Finished after "..ticks_spent.." ticks")
        return success
    end,

    EngineerBuild = function(self)
        -- TODO: Check engineer is alive (don't think I need it currently though)
        --IssueClearCommands(self.engineers)
        if not self.location then
            local b_pos = self.engineers[1]:GetPosition()
            self.location = self:FindPlaceToBuildSpiral(self.blueprint_id, b_pos)
        end

        if not self:EngineerMove() then
            return false
        end

        IssueBuildMobile({self.engineers[1]}, self.location, self.blueprint_id, {})
        -- Maybe I can get the build command from the build queue, or from the unit somehow?

        if not self:EngineerWaitUntilDone() then
            return false
        end

        local units = self.brain:GetUnitsAroundPoint(categories.STRUCTURE + categories.EXPERIMENTAL * categories.BUILTBYTIER3ENGINEER, self.location, 0.1)
        if units and table.getn(units) == 1 then
            return true
        end

        return false
    end,

    FactoryBuild = function(self)
        if self.upgrade then
            IssueUpgrade({self.factory}, self.blueprint_id)
        else
            IssueBuildFactory({self.factory}, self.blueprint_id, 1)
        end
        -- If I had a thread scoped to the factory, this would be way easier
        -- TODO Rearrange task monitoring to come from the builders, not the task
        -- Just have a Queue in the factory, and make the callbacks when GetWorkProgress() resets

        -- Maybe I can use IsCommandDone()?  Seems perfect actually.
        -- Trying this out now^^
        -- It errors out because IssueBuildFactory doesn't return anything...
        local queue_len = table.getn(self.factory:GetCommandQueue())
        local queue_position = queue_len
        local wait_counter = 1
        while (not self.brain:IsDefeated()) and self.factory and (not self.factory.Dead) do
            wait_counter = wait_counter + 1
            local new_queue_len = table.getn(self.factory:GetCommandQueue())
            if new_queue_len < queue_len then
                LOG("Factory built something")
                -- Something was built (or built and a new thing added in the same tick...)
                queue_position = queue_position - 1
                if queue_position == 0 then
                    LOG("Think it was us")
                    break
                end
            else
                queue_len = new_queue_len
            end
            WaitTicks(10)  -- Always wait after the checking in case it's dead
        end
        LOG("Factory finished build after "..wait_counter.." seconds")
        return true  -- Let's just always say we've succeeded
    end,

    BuildThread = function(self)
        self.status = "InProgress"
        LOG("Started construction")

        local result = false
        if self.factory then
            result = self:FactoryBuild()
        elseif self.resource then
            result = self:EngineerBuildResource()
        else
            result = self:EngineerBuild()
        end

        self.status = "Complete"
        for _, engy in self.engineers do
            engy.TestAITask = nil
        end
        LOG("Construction of "..(self.blueprint_id or "reclaim").." complete: result "..repr(result))
        if self.callback then
            self.callback(result)
        end
    end,

    -- Could be either success or failure; can use the callback to determine
    IsDone = function(self)
        return self.status == "Complete"
    end,

    -- Could be either success or failure; can use the callback to determine
    WaitUntilDone = function(self)
        while self.brain.Result ~= "defeat" and not self:IsDone() do
            WaitTicks(2)
        end
    end,

    -- Takes (x, _, z), returns (x, y, z) or nil.  Tries places in a spiral.
    FindPlaceToBuildSpiral = function(self, blueprint_id, near_position)
        local radius = 5  -- Try and exclude the builder's position
        -- TODO: Reduce starting radius for small buildings (5 is pretty good for factories)
        while radius < 70 do
            local counter = 0
            while counter < radius do
                for _, pos in {{radius, counter}, {radius, -counter}, {-radius, counter}, {-radius, -counter}, {counter, radius}, {-counter, radius}, {counter, -radius}, {-counter, -radius}} do
                    local x = math.floor(near_position[1] + pos[1]) + 0.5
                    local z = math.floor(near_position[3] + pos[2]) + 0.5
                    local y = GetSurfaceHeight(x, z)
                    -- TODO: Very rarely this can build overlapping structures.  Maybe when it's called twice in the same tick?
                    if self.brain:CanBuildStructureAt(blueprint_id, {x, y, z}) then
                        return {x, y, z}
                    end
                end
                counter = counter + 1
            end
            radius = radius + 1
        end
    end,
})

-- blueprint should be like BP.MexT1
function CreateTask(brain, blueprint, ...)
    local task = Task()
    task:New(brain, blueprint,  unpack(arg))
    return task
end

-- blueprint should be like BP.MexT1
-- unit is a unit object
-- Returns true if the unit matches that blueprint (any faction)
function CompareBPUnit(blueprint, unit)
    for _, id in blueprint do
        if unit.UnitId == id then
            return true
        end
    end
    return false
end

LAYER_SUFFIX = {
    AIR = "Air",
    LAND = "Land",
    NAVY = "Navy",
}

-- TODO Implement automatic HQ / support management
BP = {
    ACU = {
        AEON = "ual0001",
        UEF = "uel0001",
        CYBRAN = "url0001",
        SERAPHIM = "xsl0001",
        NOMADS = "xnl0001",
    },
    MexT1 = {
        AEON = "uab1103",
        UEF = "ueb1103",
        CYBRAN = "urb1103",
        SERAPHIM = "xsb1103",
        NOMADS = "xnb1103",
    },
    MexT2 = {
        AEON = "uab1202",
        UEF = "ueb1202",
        CYBRAN = "urb1202",
        SERAPHIM = "xsb1202",
        NOMADS = "xnb1202",
    },
    MexT3 = {
        AEON = "uab1302",
        UEF = "ueb1302",
        CYBRAN = "urb1302",
        SERAPHIM = "xsb1302",
        NOMADS = "xnb1302",
    },
    FactoryLandT1 = {
        AEON = "uab0101",
        UEF = "ueb0101",
        CYBRAN = "urb0101",
        SERAPHIM = "xsb0101",
        NOMADS = "xnb0101",
    },
    FactoryLandT2HQ = {
        AEON = "uab0201",
        UEF = "ueb0201",
        CYBRAN = "urb0201",
        SERAPHIM = "xsb0201",
        NOMADS = "xnb0201",
    },
    FactoryLandT3HQ = {
        AEON = "uab0301",
        UEF = "ueb0301",
        CYBRAN = "urb0301",
        SERAPHIM = "xsb0301",
        NOMADS = "xnb0301",
    },
    FactoryLandT2SP = {
        AEON = "zab9501",
        UEF = "zeb9501",
        CYBRAN = "zrb9501",
        SERAPHIM = "zsb9501",
        NOMADS = "znb9501",
    },
    FactoryLandT3SP = {
        AEON = "zab9601",
        UEF = "zeb9601",
        CYBRAN = "zrb9601",
        SERAPHIM = "zsb9601",
        NOMADS = "znb9601",
    },
    FactoryAirT1 = {
        AEON = "uab0102",
        UEF = "ueb0102",
        CYBRAN = "urb0102",
        SERAPHIM = "xsb0102",
        NOMADS = "xnb0102",
    },
    FactoryAirT2HQ = {
        AEON = "uab0202",
        UEF = "ueb0202",
        CYBRAN = "urb0202",
        SERAPHIM = "xsb0202",
        NOMADS = "xnb0202",
    },
    FactoryAirT3HQ = {
        AEON = "uab0302",
        UEF = "ueb0302",
        CYBRAN = "urb0302",
        SERAPHIM = "xsb0302",
        NOMADS = "xnb0302",
    },
    FactoryAirT2SP = {
        AEON = "zab9502",
        UEF = "zeb9502",
        CYBRAN = "zrb9502",
        SERAPHIM = "zsb9502",
        NOMADS = "znb9502",
    },
    FactoryAirT3SP = {
        AEON = "zab9602",
        UEF = "zeb9602",
        CYBRAN = "zrb9602",
        SERAPHIM = "zsb9602",
        NOMADS = "znb9602",
    },
    Hydro = {
        AEON = "uab1102",
        UEF = "ueb1102",
        CYBRAN = "urb1102",
        SERAPHIM = "xsb1102",
        NOMADS = "xnb1102",
    },
    PgenT1 = {
        AEON = "uab1101",
        UEF = "ueb1101",
        CYBRAN = "urb1101",
        SERAPHIM = "xsb1101",
        NOMADS = "xnb1101",
    },
    PgenT2 = {
        AEON = "uab1201",
        UEF = "ueb1201",
        CYBRAN = "urb1201",
        SERAPHIM = "xsb1201",
        NOMADS = "xnb1201",
    },
    PgenT3 = {
        AEON = "uab1301",
        UEF = "ueb1301",
        CYBRAN = "urb1301",
        SERAPHIM = "xsb1301",
        NOMADS = "xnb1301",
    },
    EngyT1 = {
        AEON = "ual0105",
        UEF = "uel0105",
        CYBRAN = "url0105",
        SERAPHIM = "xsl0105",
        NOMADS = "xnl0105",
    },
    EngyT2 = {
        AEON = "ual0208",
        UEF = "uel0208",
        CYBRAN = "url0208",
        SERAPHIM = "xsl0208",
        NOMADS = "xnl0208",
    },
    EngyT3 = {
        AEON = "ual0309",
        UEF = "uel0309",
        CYBRAN = "url0309",
        SERAPHIM = "xsl0309",
        NOMADS = "xnl0309",
    },
    LandScoutT1 = {
        AEON = "ual0101",
        UEF = "uel0101",
        CYBRAN = "url0101",
        SERAPHIM = "xsl0101",
        NOMADS = "xnl0101",
    },
    TankT1 = {
        AEON = "ual0201",
        UEF = "uel0201",
        CYBRAN = "url0107",
        SERAPHIM = "xsl0201",
        NOMADS = "xnl0201",
    },
    ArtyT1 = {
        AEON = "ual0103",
        UEF = "uel0103",
        CYBRAN = "url0103",
        SERAPHIM = "xsl0103",
        NOMADS = "xnl0107",
    },
    AAT1 = {
        AEON = "ual0104",
        UEF = "uel0104",
        CYBRAN = "url0104",
        SERAPHIM = "xsl0104",
        NOMADS = "xnl0103",
    },
    TankT2 = {
        AEON = "ual0202",
        UEF = "uel0202",
        CYBRAN = "url0202",
        SERAPHIM = "xsl0202",
        NOMADS = "xnl0202",
    },
    RangeT2 = {
        AEON = "xal0203",
        UEF = "del0204",
        CYBRAN = "drl0204",
        SERAPHIM = "xsl0202",
        NOMADS = "xnl0306",
    },
    AmphibiousT2 = {
        AEON = "xal0203",
        UEF = "uel0203",
        CYBRAN = "url0203",
        SERAPHIM = "xsl0203",
        NOMADS = "xnl0203",
    },
    AAT2 = {
        AEON = "ual0205",
        UEF = "uel0205",
        CYBRAN = "url0205",
        SERAPHIM = "xsl0205",
        NOMADS = "xnl0205",
    },
    MMLT2 = {
        AEON = "ual0111",
        UEF = "uel0111",
        CYBRAN = "url0111",
        SERAPHIM = "xsl0111",
        NOMADS = "xnl0111",
    },
    ShieldT2 = {
        AEON = "ual0307",
        UEF = "uel0307",
        CYBRAN = "url0306",  -- Mobile stealth
        SERAPHIM = "xsl0202",  -- Just make more Ilshavoh...
        NOMADS = "xnl0306",  -- EMP Tank
    },
    ShieldT3 = {  -- Very variable costs
        AEON = "ual0307",  -- T2
        UEF = "uel0307",  -- T2
        CYBRAN = "url0306",  -- Mobile stealth
        SERAPHIM = "xsl0307",
        NOMADS = "xnl0306",  -- EMP Tank
    },
    RaiderT3 = {
        AEON = "ual0303",
        UEF = "uel0303",
        CYBRAN = "url0303",
        SERAPHIM = "xsl0303",
        NOMADS = "xnl0303",
    },
    RangeT3 = {
        AEON = "xal0305",
        UEF = "xel0305",
        CYBRAN = "xrl0305",
        SERAPHIM = "xsl0305",
        NOMADS = "xnl0305",
    },
    TankT3 = {
        AEON = "ual0303",
        UEF = "xel0305",
        CYBRAN = "xrl0305",
        SERAPHIM = "xsl0303",
        NOMADS = "xnl0305",
    },
    AAT3 = {
        AEON = "dalk003",
        UEF = "delk002",
        CYBRAN = "drlk001",
        SERAPHIM = "dslk004",
        NOMADS = "xnl0302",
    },
    ArtyT3 = {
        AEON = "ual0304",
        UEF = "uel0304",
        CYBRAN = "url0304",
        SERAPHIM = "xsl0304",
        NOMADS = "xnl0304",
    },
    LandT4 = {
        AEON = "ual0401",
        UEF = "uel0401",
        CYBRAN = "url0402",
        SERAPHIM = "xsl0401",
        NOMADS = "xnl0403",
    },
    AirScoutT1 = {
        AEON = "uaa0101",
        UEF = "uea0101",
        CYBRAN = "ura0101",
        SERAPHIM = "xsa0101",
        NOMADS = "xna0101",
    },
    IntyT1 = {
        AEON = "uaa0102",
        UEF = "uea0102",
        CYBRAN = "ura0102",
        SERAPHIM = "xsa0102",
        NOMADS = "xna0102",
    },
    BomberT1 = {
        AEON = "uaa0103",
        UEF = "uea0103",
        CYBRAN = "ura0103",
        SERAPHIM = "xsa0103",
        NOMADS = "xna0103",
    }
}