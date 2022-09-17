-- The AirThreatMap is used for calculating threat for air units
-- It has a very coarse resolution to account for the imprecision in air movement
-- It considers only threat against air
-- Ground based or naval threat doesn't get motion projected; only aerial



-- How do turns work?
-- Air units roughly fly straight over their first spot and then turn
-- A T1 scout uses about 30-35 overshoot to make a right angle, and can do a U turn in about 50ish
-- T1 inty can turn with about 20 overshoot right angle, U turn in about 25ish
-- T1 bomber can right angle with about 15 overshoot, U in about 15ish
-- T3 spy plane needs about 55 to right angle and 80 to U turn
-- ASF can U turn in about 30
-- Notha right angles in about 15

-- Most air units have vision radius of 32; inties are just 28.
-- Say I have squares be fully visible from the middle, that means up to 40x40 is OK
-- Being able to represent ability to turn is potentially useful.
-- Say a square is 25x25; and an ASF is heading north and travels at 0.6sq/s
-- In 1.5s it can be in the square to the N; probably 3s for the NE and NW or NN
-- E and W squares are maybe 4.5s
-- SE, SW and S are maybe 6s

-- Or I could do air fight micro not considering where things will be, and try and do some kind of
-- Enemy CoM and average heading based thing?

-- Do I need to worry about offmap stuff?

-- Say I project ahead in 10s chunks; in that time an ASF can move about 200


local SQUARE_SIZE = 32

AirThreatMap = Class({
    New = function(self, playable_area)
        self.square_size = SQUARE_SIZE
        self.offsetx = playable_area[1] - self.square_size
        self.offsetz = playable_area[2] - self.square_size

        self.maxi = math.floor((playable_area[3] - playable_area[1] - 0.1) / self.square_size)
        self.maxj = math.floor((playable_area[4] - playable_area[2] - 0.1) / self.square_size)

        self.grid = {}
        for i = 1, self.maxi do
            local row = {}
            self.grid[i] = row
            for j = 1, self.maxj do
                row[j] = {
                    AirHP = 0,
                    AirDPS = 0,
                    SurfaceHP = 0,
                    SurfaceDPS = 0,
                    Futures = {},
                }
            end
        end
    end,

    -- May return nil, and may be called with nil
    GetSquareFromPosition = function(self, pos)

    end,

    -- Called with each changed unit
    -- If position_before is nil, the unit was not previously known
    -- If position_after is nil, the unit has been destroyed
    -- threat is as returned by CalcUnitThreat().
    -- Caller is responsible for making sure position_before is always the after value from the previous call for that unit
    -- If I split current and max HP in threat, this must use max HP (or get old HP somehow)
    UpdateUnit = function(self, threat, position_before, position_after)
        if threat.DS[6] == 0 then
            return
        end
        local sq_before = self:GetSquareFromPosition(position_before)
        local sq_after = self:GetSquareFromPosition(position_after)
        if sq_before == sq_after then
            -- Unit hasn't moved at our resolution
            return
        end
        local hp_var = "SurfaceHP"
        local dps_var = "SurfaceDPS"
        if threat.L == 5 or threat.L == 6 then
            hp_var = "AirHP"
            dps_var = "AirDPS"
        end

        if sq_before then
            -- Remove the unit's threat from its old position
            sq_before[hp_var] = sq_before[hp_var] - threat.HP
            sq_before[dps_var] = sq_before[dps_var] - threat.DS[6]
        end
        if sq_after then
            -- Add the unit's threat to its new position
            sq_after[hp_var] = sq_after[hp_var] + threat.HP
            sq_after[dps_var] = sq_after[dps_var] + threat.DS[6]
        end
    end,

    -- Recalculate where potential units could be
    RecalculateMovement = function(self)
        -- Just assume everything has speed 18?

    end,








})