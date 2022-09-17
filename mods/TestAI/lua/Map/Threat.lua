-- Calculating threat against each layer is good and all, but might not always make sense
-- Land units shouldn't not attack just because a bomber is near: it's so much faster that it might as well be everywhere
-- Air fights should consider whether the fight is over static AA or MAA  though



local BP = import('/mods/TestAI/lua/AI/Production/Task.lua').BP
local CompareBPUnit = import('/mods/TestAI/lua/AI/Production/Task.lua').CompareBPUnit
local Map = import('/mods/TestAI/lua/Map/Map.lua')

local DEBUG = false

-- Can't import this function from /lua/system/blueprints-ai.lua.  By Balthazar, but with fixes to damage and interval formulae.
local function CalculatedDPS(weapon)
    -- Base values
    local ProjectileCount
    if weapon.MuzzleSalvoDelay == 0 then
        ProjectileCount = math.max(1, table.getn(weapon.RackBones[1].MuzzleBones or {'nehh'} ) )
    else
        ProjectileCount = (weapon.MuzzleSalvoSize or 1)
    end
    if weapon.RackFireTogether then
        ProjectileCount = ProjectileCount * math.max(1, table.getn(weapon.RackBones or {'nehh'} ) )
    end
    -- Game logic rounds the timings to the nearest tick --  MathMax(0.1, 1 / (weapon.RateOfFire or 1)) for unrounded values
    local DamageInterval = math.floor((math.max(0.1, 1 / (weapon.RateOfFire or 1)) * 10) + 0.5) / 10 +
        (math.max(weapon.MuzzleSalvoDelay or 0, weapon.MuzzleChargeDelay or 0) * (weapon.MuzzleSalvoSize or 1))
    -- TODO: I suspect that the MuzzleSalvoDelay shouldn't be added to the RateOfFire at all
    local Damage = (((weapon.Damage or 0) + (weapon.NukeInnerRingDamage or 0)) * (weapon.DoTPulses or 1) + (weapon.InitialDamage or 0)) * ProjectileCount

    -- Beam calculations.
    if weapon.BeamLifetime and weapon.BeamLifetime == 0 then
        -- Unending beam. Interval is based on collision delay only.
        DamageInterval = 0.1 + (weapon.BeamCollisionDelay or 0)
    elseif weapon.BeamLifetime and weapon.BeamLifetime > 0 then
        -- Uncontinuous beam. Interval from start to next start.
        DamageInterval = DamageInterval + weapon.BeamLifetime
        -- Damage is calculated as a single glob, beam weapons are typically underappreciated
        Damage = Damage * (weapon.BeamLifetime / (0.1 + (weapon.BeamCollisionDelay or 0)))
    end

    LOG("Weapon D="..Damage..", DI="..DamageInterval)
    return Damage * ((1 / DamageInterval) or 0)
end


-- TODO: This is better implemented for the UI by recursively examining the projectile
 local ProjectileDamageMultipliers = {
    sifthunthoartilleryshell01_proj=5,  -- Fragments (Zthuee)
    tiffragmentationsensorshell01_proj=5,  -- Fragments (Lobo)
    aiffragmentationsensorshell01_proj=36,  -- Fragments (Salvation)
}

-- If the automatic calculator doesn't work right for a unit, it can be overridden here
local UnitThreats = {
    -- ACUs are wrong because of weird cost
    -- V musn't be too high, or small forces will suicide to do a little bit of damage
    -- Would be nice to have a bonus reward for definitely killing it though
    -- Include an approximation of OC
    -- This will probably make our ACU too brave though when we start using them
    url0001 = {V=2000, L=1, R=22, HP=10000, S=1.7, DS={400, 400, 400, 0, 0, 0}, DA={4000, 4000, 4000, 0, 0, 0}},
    uel0001 = {V=2000, L=1, R=22, HP=12000, S=1.7, DS={400, 400, 400, 0, 0, 0}, DA={4000, 4000, 4000, 0, 0, 0}},
    ual0001 = {V=2000, L=1, R=22, HP=11000, S=1.7, DS={400, 400, 400, 0, 0, 0}, DA={4000, 4000, 4000, 0, 0, 0}},
    xsl0001 = {V=2000, L=1, R=22, HP=11500, S=1.7, DS={400, 400, 400, 0, 0, 0}, DA={4000, 4000, 4000, 0, 0, 0}},
    xnl0001 = {V=2000, L=1, R=22, HP=10500, S=1.7, DS={400, 400, 400, 0, 0, 0}, DA={4000, 4000, 4000, 0, 0, 0}},
}

ThreatMap = Class({

    -- Threat is recorded in several dimensions:
    -- Type is the current mode of the target it can attack: land, navy, hover, submerged, low_air, high_air
    -- vsType, vsTypeArea
    -- Values are sqrt(dps*hp); for vsTypeArea it's radius*sqrt(dps*hp)*sqrt(pi) (essentially dps*area)


    -- Winner (A vs B) is Ahp * Adps vs Bhp * Bdps
    -- To make addition trivial, need to sqrt (and then it's proportional to mass in most cases)
    -- We need to consider that units not directly there will contribute (e.g. SAMs in an air fight), but their HP isn't relevant

    -- Threats are additive: 2 threat + 2 threat should be a match for 4 threat
    -- For AoE threat, if a group of units has density 1 per 1x1 square

    -- Definitions:
    -- - A square is a 35x35 block of the map
    -- - Threat is the whole set of HPs (not per layer for single units!), DPSs and Values at each layer
    -- - Strength is sqrt(dps*hp) at a single layer

    -- REQUIRED WORK IN THIS CLASS:
    -- Unit threat calculation
    -- Map storage
    -- Updating
    -- Pathing functions
    -- Optimization?
    -- Spreading threat over time

    New = function(self, brain, playable_area)
        self.brain = brain
        self.area = playable_area

        -- Sparse double array
        -- I can use a double array with small spacing but not if I want to put them in all cells in range or allow all movements
        -- I probably need to ~ref count the sources of everything
        -- Top level is a dense double array; each square is 32x32
        -- TODO: Eventually account for unit current HP (when it moves; need to allow for threat dropping)
        -- Squares are:
        local example_threat_square = {
            POS={},  -- Position of middle of square
            VT=21,  -- Last tick seen
            RT=21,  -- Last tick caught on radar
            ST=21,  -- Last tick seen on sonar
            UE={},  -- Map:<entity id>=>unit entry for all enemies in the square at last scout
            I=2,  -- Index into the array
            J=3,  -- Index into the array
            MR=0,  -- 0 means our base, 1 means an enemy base
        }

        -- TODO: Use map version
        local our_x, our_z = brain:GetArmyStartPos()
        local enemy_bases = {}  -- List of {x, z}
        local ally_bases = {}  -- ^^
        for _, a in ListArmies() do
            local b = GetArmyBrain(a)
            if b and IsEnemy(b:GetArmyIndex(), brain:GetArmyIndex()) then
                local e_x, e_z = b:GetArmyStartPos()
                table.insert(enemy_bases, {e_x, e_z})
            elseif b and IsAlly(b:GetArmyIndex(), brain:GetArmyIndex()) then
                local a_x, a_z = b:GetArmyStartPos()
                table.insert(ally_bases, {a_x, a_z})
            end
        end

        self.threat_map = {}
        for i = 1, math.floor((self.area[3]-self.area[1]-0.01)/32) do
            self.threat_map[i] = {}
            for j = 1, math.floor((self.area[4]-self.area[2]-0.01)/32) do
                local x = self.area[1]+32*i-16
                local z = self.area[2]+32*j-16
                local pos = {x, GetTerrainHeight(x, z), z}
                local us_dist = VDist2(our_x, our_z, x, z)
                local ally_dist = us_dist
                for _, a in ally_bases do
                    ally_dist = math.min(ally_dist, VDist2(a[1], a[2], x, z))
                end
                local them_dist = 99999
                for _, e in enemy_bases do
                    them_dist = math.min(them_dist, VDist2(e[1], e[2], x, z))
                end
                -- Use a blend of distance from us and distance from allies
                local blend_dist = math.min(us_dist, (us_dist + ally_dist)/2)
                local mr = blend_dist / (blend_dist + them_dist + 0.1)
                self.threat_map[i][j] = {POS=pos, UE={}, I=i, J=j, MR = mr}
            end
        end
        self.intel_tick = 1  -- Last intel update tick

        -- Indexed by entity id
        -- Values are {P=last position, LS=last seen tick, BP=bpid or nil, T=threat}
        self.enemy_units = {}

        self.new_map = Map.GetMap(brain)

        self.update_intel_thread = ForkThread(ThreatMap.UpdateIntelThread, self)
        self.brain.Trash:Add(self.update_intel_thread)

        self.visual_threat_thread = ForkThread(ThreatMap.VisualizeThreatThread, self)
        self.brain.Trash:Add(self.visual_threat_thread)
    end,

    -- Might return nil if pos is outside the playable area
    GetSquareFromPos = function(self, pos)
        local i = math.ceil((pos[1]-self.area[1])/32)
        local j = math.ceil((pos[3]-self.area[2])/32)
        local mid = self.threat_map[i]
        if mid then
            return mid[j]
        else
            return nil
        end
    end,

    -- TODO: Move units: don't keep threat when they're left or died (and we can see)
    UpdateIntelThread = function(self)
        local intel_tick = 1
        local brain = self.brain
        local army = brain:GetArmyIndex()
        while not brain:IsDefeated() do
            -- Let's just get all enemy units and see what we have
            local all_enemies = brain:GetUnitsAroundPoint(categories.ALLUNITS-categories.WALL-categories.INSIGNIFICANTUNIT, {100, 0, 100}, 100000, 'Enemy')
            for _, enemy in all_enemies do
                local blip = enemy:GetBlip(army)
                if blip then
                    local identified = blip:IsSeenEver(army)
                    local threat = self:GetThreat(enemy, identified)
                    local id = enemy:GetEntityId()
                    local bpid = nil
                    if identified then
                        bpid = blip:GetBlueprint().BlueprintId
                    end
                    -- Watch out for GetPosition()'s value being updated sometimes
                    -- For some reason I can't store U=enemy here: it hangs the game after a little while
                    local new_threat = {P={enemy:GetPositionXYZ()}, T=threat, BP=bpid, LS=intel_tick}

                    -- Remove it from its last seen spot
                    local old_unit = self.enemy_units[id]
                    if old_unit then
                        local old_square = self:GetSquareFromPos(old_unit.P)
                        old_square.UE[id] = nil
                    end

                    -- Add it to its current location
                    local square = self:GetSquareFromPos(new_threat.P)
                    if not square then
                        continue
                    end
                    self.enemy_units[id] = new_threat
                    square.UE[id] = new_threat
                end
            end

            -- Clear out dead units
            -- TODO: I guess this is slightly cheating in FFAs or certain other situations
            local units_died = {}
            for id, data in self.enemy_units do
                local unit = GetUnitById(id)
                if not unit or unit.Dead then
                    table.insert(units_died, id)
                    local square = self:GetSquareFromPos(data.P)
                    if square then
                        square.UE[id] = nil
                    end
                end
            end
            for _, id in units_died do
                self.enemy_units[id] = nil
            end

            --[[
            -- Recalculate square threats
            for i = 1, math.floor((self.area[3]-self.area[1]-0.01)/32) do
                for j = 1, math.floor((self.area[4]-self.area[2]-0.01)/32) do
                    local square_threat = {}
                end
            end]]

            self.intel_tick = intel_tick
            WaitTicks(10)
            intel_tick = intel_tick + 10
        end
    end,

    -- allies is a boolean; true for allies, false for enemies
    -- Returns the total threat that can attack the square
    -- {V={<value by layer>}, HP={<HP by layer>}, DS={<DPS single target by layer>}, DA={<AoE>}}
    -- Undercounts value though, because it largely ignores non-combat units (due to range)
    GetThreatInRangeOfSquare = function(self, square, allies)
        local dps = {0, 0, 0, 0, 0, 0}
        local dps_aoe = {0, 0, 0, 0, 0, 0}
        local hp = {0, 0, 0, 0, 0, 0}
        local value = {0, 0, 0, 0, 0, 0}
        if allies then
            -- This is a circular range while enemies is square, but whatever
            local allied_units = self.brain:GetUnitsAroundPoint(categories.ALLUNITS-categories.WALL, square.POS, 80, 'Ally')
            for _, u in allied_units do
                if not u.Dead then
                    local threat = self:GetThreat(u, true)
                    local pos = u:GetPosition()
                    -- Don't allow a range bonus for now, because our units are unresponsive
                    if threat.R > VDist2(square.POS[1], square.POS[3], pos[1], pos[3]) then
                        local layer = threat.L
                        local unit_dps = 0
                        -- TODO: Consider AoE
                        hp[layer] = hp[layer] + threat.HP
                        value[layer] = value[layer] + threat.V
                        for l = 1, 6 do
                            unit_dps = unit_dps + threat.DS[l]
                            dps[l] = dps[l] + threat.DS[l]
                        end
                        -- Unit has no DPS: Don't count its HP - only its value
                        value[layer] = value[layer] + threat.V
                        if unit_dps > 0 then
                            hp[layer] = hp[layer] + threat.HP
                        end
                    end
                end
            end
        else
            -- Catches all units within 64 range, and some from further
            for i = square.I-2, square.I+2 do
                for j = square.J-2, square.J+2 do
                    local mid = self.threat_map[i]
                    if mid then
                        local sq = mid[j]
                        if sq then
                            for _, u in sq.UE do
                                -- Use a 20 range bonus to allow threatening ~anywhere in the square
                                if u.T.R + 20 > VDist2(square.POS[1], square.POS[3], u.P[1], u.P[3]) then
                                    local layer = u.T.L
                                    local unit_dps = 0
                                    -- TODO: Consider AoE
                                    for l = 1, 6 do
                                        dps[l] = dps[l] + u.T.DS[l]
                                        unit_dps = unit_dps + u.T.DS[l]
                                    end
                                    -- Unit has no DPS: Don't count its HP - only its value
                                    value[layer] = value[layer] + u.T.V
                                    if unit_dps > 0 then
                                        hp[layer] = hp[layer] + u.T.HP
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        return {V=value, DS=dps, DA=dps_aoe, HP=hp}
    end,

    -- TODO: I think I've made it so that logging repr(unit) causes a hang?  Infinite loop?


    -- Can be called with either actual units, or with self.enemy_units
    -- Returns {DS={}, DA={}, HP={}, V={}}
    GetCombinedThreat = function(self, units)
        local our_dps = {0, 0, 0, 0, 0, 0}
        local our_dps_aoe = {0, 0, 0, 0, 0, 0}
        local our_hp = {0, 0, 0, 0, 0, 0}
        local our_value = {0, 0, 0, 0, 0, 0}
        -- TODO: Consider range
        -- TODO: Use helper function like with enemies
        for _, u in units do
            local unit_threat
            if u.T == nil then
                -- Is a unit: get threat
                if u.Dead then
                    continue
                end
                unit_threat = self:GetThreat(u, true)
            else
                -- Is self.enemy_units
                unit_threat = u.T
            end
            our_hp[unit_threat.L] = our_hp[unit_threat.L] + unit_threat.HP
            for l = 1, 6 do
                our_dps[l] = our_dps[l] + unit_threat.DS[l]
                our_dps_aoe[l] = our_dps_aoe[l] + unit_threat.DA[l]
            end
            our_value[unit_threat.L] = our_value[unit_threat.L] + unit_threat.V
        end
        return {DS=our_dps, DA=our_dps_aoe, HP=our_hp, V=our_value}
    end,

    -- What's a good model for the outcome of a fight?
    -- Roughly value destroyed - value lost?  Doesn't consider value of reclaim
    -- Assumes the units are all alive, and considers enemies in range but not other allies in range
    -- Result may be negative (== avoid)!
    -- More or less assumes a fight to the death: not just running by (e.g. air flying over AA)
    -- TODO: Change this (and GetBestFight) so that nothing is much less than 0.  Might want to take a slightly negative fight sometimes.
    FightValue = function(self, attack_square, combined_threat)
        -- Assess enemy units
        local enemy_threat = self:GetThreatInRangeOfSquare(attack_square, false)

        -- This function was (is!) really hard to get right.
        -- Naive approaches failed to work well for asymmetric fights (Bombers, or MAA)
        local fight_value = 0

        -- Work out value weighted survival time
        local avtotal = 0
        local evtotal = 0
        local atimetotal = 0
        local etimetotal = 0
        for l = 1, 6 do
            -- Survival time for the units in this layer
            local atime = math.min(combined_threat.HP[l]/(enemy_threat.DS[l]+1), 60)
            local etime = math.min(enemy_threat.HP[l]/(combined_threat.DS[l]+1), 60)

            avtotal = avtotal + combined_threat.V[l]
            evtotal = evtotal + enemy_threat.V[l]

            atimetotal = atimetotal + atime * combined_threat.V[l]
            etimetotal = etimetotal + etime * enemy_threat.V[l]
        end
        -- Assume that all DPS comes evenly from value across all layers
        -- TODO: Work separately with a DPS l1->l2 matrix.  We get scared of things like fighting 2 tanks vs a tank + an inty.
        local atime = (atimetotal + 1) / (avtotal + 1)
        local etime = (etimetotal + 1) / (evtotal + 1)

        for l = 1, 6 do
            -- Rates of value loss in this layer
            local avrate = enemy_threat.DS[l]*combined_threat.V[l]/(combined_threat.HP[l]+1)
            local evrate = combined_threat.DS[l]*enemy_threat.V[l]/(enemy_threat.HP[l]+1)

            -- We lose value according to the enemy's value destruction rate for the full battle time
            -- (Value loss stops when all enemies are dead)
            local avalueloss = math.min(avrate * etime, combined_threat.V[l])
            local evalueloss = math.min(evrate * atime, enemy_threat.V[l])

            fight_value = fight_value + evalueloss - avalueloss
        end

        -- TODO: If we lose the combat part of the fight, then we shouldn't be allowed to claim the excess value from economic HP
        -- Really I should probably put economic structures in separate layers?

        if DEBUG and fight_value ~= 0 then
            LOG("FV: "..fight_value.." was us: "..repr(combined_threat).." vs "..repr(enemy_threat))
        end

        return fight_value
    end,
    -- 2:1 sqrt(dpshp) advantage is great; not much point going further

    -- Data is {V=<value of killing>, L=<current layer>, DS={<single target dps>}, DA={<multi target dps}, R=<range>, H=<hp>, S=<speed>}
    -- Layers are {land, navy, hover, submerged, low_air, high_air} (as a number)
    GetThreat = function(self, unit, identified)
        if not identified then
            -- Just assume T1 tank ish for now (TODO: Check layer; consider speed etc)
            -- TODO: Don't cheat by identifying units that weren't in visual
            --return {V=90, L=1, R=24, HP=300, S=2, DS={25, 25, 25, 0, 0, 0}, DA={0, 0, 0, 0, 0, 0}}
        end

        return self:GetBlueprintThreat(unit.UnitId)
    end,

    GetBlueprintThreat = function(self, bpid)
        if not UnitThreats[bpid] then
            UnitThreats[bpid] = self:CalcUnitThreat(bpid)
        end
        return UnitThreats[bpid]
    end,

    CalcUnitThreat = function(self, bpid)
        local bp = __blueprints[bpid]
        if DEBUG then
            LOG("Analyzing BP "..repr(bp))
        end
        local range = 0
        local max_dps = 0
        local dps = {0, 0, 0, 0, 0, 0}
        local dps_aoe = {0, 0, 0, 0, 0, 0}
        local value = bp.Economy.BuildCostMass +
            bp.Economy.BuildCostEnergy / 20 +
            bp.Economy.BuildTime / 40

        local speed = bp.Physics.MaxSpeed
        if bp.Air.CanFly then
            speed = bp.Air.MaxAirspeed
        end

        local ehp = bp.Defense.MaxHealth
        if bp.Defense.Shield then
            ehp = ehp + (bp.Defense.Shield.ShieldMaxHealth or 0)
        end

        -- TODO: Fill in others
        local layer = 6
        if bp.LayerCategory == "LAND" then
            layer = 1
        end

        -- TODO: For ghettos, calculate the DPS of the LABs in them

        -- Calculate DPS and what it can hit
        for _, w in bp.Weapon do
            local wdps = CalculatedDPS(w)

            -- Use an override table for fragmentation projectiles and such
            -- TODO: Use -- https://github.com/FAForever/fa/blob/57d060905d5605cfc4a8c459210aa96bb12e4b12/lua/ui/game/unitviewDetail.lua#L576 instead.
            local projectile = string.match(w.ProjectileId, '[^/]+.bp')
            if projectile then
                projectile = string.sub(projectile, 1, -4)
                LOG("Checking for override of projectile "..repr(projectile))
                wdps = wdps * (ProjectileDamageMultipliers[projectile] or 1)
            end

            -- Rescale DPS based on unit HP to account for big single units not losing DPS when fighting many small ones
            -- HP = 55: 0.5
            -- HP = 3000: 1
            -- HP = 160000: 1.5
            local hpfrac = 8 / math.log(1 + ehp)
            wdps = wdps * hpfrac

            local wdps_aoe = 3.14 * wdps * w.DamageRadius * w.DamageRadius
            if wdps + wdps_aoe / 10 > max_dps then
                -- Use the highest DPS weapon to set the range
                max_dps = wdps + wdps_aoe / 10
                range = w.MaxRadius
            end

            --Layers are: {land, navy, hover, submerged, low_air, high_air}
            if w.RangeCategory == 'UWRC_AntiAir' or w.TargetRestrictOnlyAllow == 'AIR' or string.find(w.WeaponCategory or '', 'Anti Air') then
                dps[5] = dps[5] + wdps
                dps[6] = dps[6] + wdps
                dps_aoe[5] = dps_aoe[5] + wdps_aoe
                dps_aoe[6] = dps_aoe[6] + wdps_aoe
            elseif w.RangeCategory == 'UWRC_AntiNavy' or string.find(w.WeaponCategory or '', 'Anti Navy') then
                if string.find(w.WeaponCategory or '', 'Bomb') or string.find(w.Label or '', 'Bomb') or w.NeedToComputeBombDrop or bp.Air.Winged then
                    wdps = wdps / 2  -- Half DPS for bombs to allow for looping around
                    wdps_aoe = wdps_aoe / 2  -- ^^
                end
                dps[2] = dps[2] + wdps
                dps[4] = dps[4] + wdps
                dps_aoe[2] = dps_aoe[2] + wdps_aoe
                dps_aoe[4] = dps_aoe[4] + wdps_aoe
            elseif w.RangeCategory == 'UWRC_DirectFire' or string.find(w.WeaponCategory or '', 'Direct Fire')
            or w.RangeCategory == 'UWRC_IndirectFire' or string.find(w.WeaponCategory or '', 'Artillery') then
                dps[1] = dps[1] + wdps
                dps[2] = dps[2] + wdps
                dps[3] = dps[3] + wdps
                dps_aoe[1] = dps_aoe[1] + wdps_aoe
                dps_aoe[2] = dps_aoe[2] + wdps_aoe
                dps_aoe[3] = dps_aoe[3] + wdps_aoe
            elseif string.find(w.WeaponCategory or '', 'Bomb') or string.find(w.Label or '', 'Bomb') or w.NeedToComputeBombDrop then
                wdps = wdps / 2  -- Half DPS for bombs to allow for looping around
                wdps_aoe = wdps_aoe / 2  -- ^^
                dps[1] = dps[1] + wdps
                dps[2] = dps[2] + wdps
                dps[3] = dps[3] + wdps
                dps_aoe[1] = dps_aoe[1] + wdps_aoe
                dps_aoe[2] = dps_aoe[2] + wdps_aoe
                dps_aoe[3] = dps_aoe[3] + wdps_aoe
            end  -- Omits death weapons
        end

        local threat = {
            V=value,
            L=layer,
            R=range,
            -- TODO: If I ever split current and max HP, look carefully at all uses of this data and decide which is right
            HP=ehp,
            S=speed,
            DS=dps,
            DA=dps_aoe,
        }
        LOG("Analyzed threat for new unit "..repr(bp.BlueprintId)..": "..repr(threat))
        return threat
    end,

    -- Find the most valuable fight a group of units can take
    -- Returns a square or nil
    -- map_ratio_limit (optional) specifies the allowable ratio of distance to our base vs distance to enemy base as {min, max}
    -- source (optional) is a position {x, y, z} weights the value of the fights by distance from that point (using the speed of the first unit)
    -- The filter_fn is called with a NEW square
    GetBestFight = function(self, units, map_ratio_limit, source, filter_fn)
        if table.empty(units) then
            return nil
        end
        local our_threat = self:GetCombinedThreat(units)
        local best_score = -1
        local best_square = nil
        local best_time = 1

        local temp_best_raw_value = 1
        local considered_count = 0

        map_ratio_limit = map_ratio_limit or {0.0, 1.0}

        local value_speed = self:GetThreat(units[1], true).S
        for _, ts in self.threat_map do
            for _, t in ts do
                if next(t.UE) and map_ratio_limit[1] < t.MR and t.MR < map_ratio_limit[2] then
                    if filter_fn then
                        local sq = self.new_map:GetSquare(t.POS)
                        if sq and not filter_fn(sq) then
                            continue
                        end
                    end
                    considered_count = considered_count + 1
                    local value = self:FightValue(t, our_threat)
                    local temp_value = value
                    local travel_time
                    if source then
                        travel_time = VDist2(source[1], source[3], t.POS[1], t.POS[3]) / value_speed
                        value = value * math.pow(2.0, -travel_time/60)  -- Situation changes quickly, favour sooner results heavily
                    end
                    if value > best_score then
                        best_time = travel_time
                        best_score = value
                        best_square = t
                        temp_best_raw_value = temp_value
                    end
                end
            end
        end
        if best_score > 0 then
            return best_square
        else
            if DEBUG then
                LOG("DEBUG TBRV="..temp_best_raw_value)
                LOG("DEBUG CC="..considered_count)
                LOG("Not returning anything - best fight was "..best_score..", travel time "..best_time.." for "..repr(best_square))
            end
            return nil
        end
    end,

    -- Get the strength of the units in range of a square
    -- Intentionally only considers units 
    -- Air units move around too much
    -- I need to consider the air control status for everything as a whole
    -- If I don't have air control, it's harder to raid
    GetStrengthInRangeOfSquare = function(self, square)

    end,

    -- Returns a strength ratio for a given layer; >1 means our advantage
    GetStrengthRatio = function(self, layer)
        local allies = self.brain:GetUnitsAroundPoint(categories.MOBILE-categories.INSIGNIFICANTUNIT, {100, 0, 100}, 100000, 'Ally')
        local a_threat = self:GetCombinedThreat(allies)

        -- TODO: Limited intel will lead to us overestimating our strength
        local e_threat = self:GetCombinedThreat(self.enemy_units)

        local e_strength = math.sqrt(e_threat.DS[layer] * e_threat.HP[layer])
        local a_strength = math.sqrt(a_threat.DS[layer] * a_threat.HP[layer])

        return (a_strength + 1) / (e_strength + 1)
    end,

    -- Should I have a separate version that also suggests the spacing?
    CalcThreatForUnits = function(self, layer, unit_count, position)
        if unit_count == 0 then
            return 0
        end

        local unit_spacing = 5 / math.sqrt(unit_count - 0.99)  -- Completely made up: should be roughly average distance between units
        -- This is 50 for 1 unit, 1.67 for 10 units, 0.5 for 101 units
        local threat_data = self.threat_map[position][layer]  -- TODO: position->indexes

        -- Assign equal weight to the last seen, projected and possible threats?
        -- For now just use last seen

        local threat = threat_data[1] + (threat_data[2] / unit_spacing)

    end,

    VisualizeThreatThread = function(self)
        local t1tanks = {DS={180, 180, 180, 0, 0, 0}, DA={0, 0, 0, 0, 0, 0}, HP={3000, 0, 0, 0, 0, 0}, V={900, 0, 0, 0, 0, 0}}
        local brain = self.brain
        while not brain:IsDefeated() do
            for _, ts in self.threat_map do
                for _, t in ts do
                    local value = 0
                    local al = 0
                    local aa = 0
                    for _, u in t.UE do
                        value = value + u.T.V
                        al = al + u.T.DS[1]
                        aa = aa + u.T.DS[6]
                    end
                    if value > 10 then
                        DrawCircle(t.POS, math.sqrt(value) / 8, 'aaffffff')
                        --DrawCircle(t.POS, math.sqrt(aa) / 2, 'aaff2222')
                        DrawCircle(t.POS, math.sqrt(al) / 2, 'aa22ff22')
                    end

                    -- TODO: Remove this bit, it's horrible
                    if self.squad_for_threat then
                        t1tanks = self:GetCombinedThreat(self.squad_for_threat.units)
                    end

                    -- Visualize the places where 10 T1 tanks have a good or bad fight
                    local fvalue = self:FightValue(t, t1tanks)
                    if fvalue > 0 then
                        local size = 2 * math.log(fvalue) + 1
                        DrawCircle(t.POS, size, 'aa2222ff')
                    elseif fvalue < 0 then
                        local size = 2 * math.log(0-fvalue) + 1
                        DrawCircle(t.POS, size, 'aaff2222')
                    end

                end
            end
            WaitTicks(2)  -- Drawings last 2 ticks
        end
    end,



    -- Returns places to defend
    -- attack_layer we want to attack units at: usually either air (Inties vs attacking Bombers) or land (Kill tank raiders)
    -- our_layer is the layer our units are (e.g. air for bomber defence)
    -- max_strength (optional) will ignore squares above a certain strength
    -- Returns {P=<pos>, S=<strength (sqrt(dps_hp)) needed to draw>, V=<value>}; in decreasing value order
    -- Defends half of the map
    -- May return an empty list
    -- TODO: Consider zone
    GetDefendTargets = function(self, attack_layer, our_layer, max_strength)
        local targets = {}
        for i = 1, math.floor((self.area[3]-self.area[1]-0.01)/32) do
            for j = 1, math.floor((self.area[4]-self.area[2]-0.01)/32) do
                local square = self.threat_map[i][j]
                if square.MR < 0.5 then
                    if next(square.UE) then
                        local threat = self:GetThreatInRangeOfSquare(square, false)
                        -- TODO: AoE and range advantages
                        local strength = math.sqrt(threat.DS[our_layer] * threat.HP[attack_layer])
                        if threat > 0 and (not max_strength or strength < max_strength) then
                            -- There's a unit in the square, and an attackable unit in range of it (not ideal)
                            table.insert(targets, {P=square.POS, S=strength, V=threat.V[attack_layer]})
                        end
                    end
                end
            end
        end
        table.sort(targets, function(a, b) return a.V > b.V end)
        return targets
    end,

    -- How far apart from each other an army should stand, allowing for amount of AoE nearby
    GetSuggestedArmySpacing = function(self, layer, position)
        local threat_data = self.threat_map[position][layer]
        local aoe_ratio = threat_data[2] / (threat_data[1] + 0.0001)
        return aoe_ratio
    end,



})