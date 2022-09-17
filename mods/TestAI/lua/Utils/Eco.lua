-- Resource valuing functions
-- An economy based on mex upgrades alone has value curve of 2^(-t/(5min))
-- Infinite reclaim and power limited is more like 1min.  Infinite mexes is similar.
-- TODO: Adjust parameter based on map?
-- Assume that time is distance/2; and let's use 1 min doubling (greed fuels expansion etc).
-- That means a distance of 360 is only worth half.
-- Also round distances < 5 down to zero (no move needed)
-- All times in seconds
-- Ecoing with infinite mass is about a 60s doubling time
local REPAYMENT_TIME_EXPAND = 60.0
local REPAYMENT_TIME_UPGRADE = 300.0  -- Value of just upgrading mexes

local RECLAIM_RATE = 25  -- Use this as a standard reclaim rate for calculating times
local MEX_BUILD_TIME = 7  -- Shorter because the build cost gets assigned too early as well

-- Assumes a repayment time of ~180s, +2m/t and -36m
local MEX_VALUE = 500
-- HCs have V=210; pgens are V=116, so the deposit is worth 370 (=5*116-210)
local HYDRO_VALUE = 300

-- Warning: do not use the ^ operator: it's xor.  Use math.pow().

-- Value of getting m mass at time t (seconds).
function ValueFnInstant(m, t)
    return m * math.pow(2.0, -t/REPAYMENT_TIME_EXPAND)
end

-- Value of getting m mass per second starting at time t (seconds).
local REPAYMENT_TIME_EXPAND_INTEGRAL = REPAYMENT_TIME_EXPAND / math.log(2)
function ValueFnContinuous(m, t)
    return REPAYMENT_TIME_EXPAND_INTEGRAL * m * math.pow(2.0, -t/REPAYMENT_TIME_EXPAND)
end

-- Incorporate everything.  Value of a mex is ValueFn(-36, 2, distance) for example
-- With these calculations, a mex is worth somewhere between 100 and 200 reclaim
function ValueFn(mass_instant, mass_income, time)
    local start_time = math.max(time - 2, 0)  -- Don't need to move gets an advantage
    local value = ValueFnInstant(mass_instant, start_time + mass_instant / RECLAIM_RATE) +
        ValueFnContinuous(mass_income, start_time + MEX_BUILD_TIME)
    -- ^^ Assume mexes will take 8s to build.  Compromise, because spend isn't instant either.
    return math.max(value, 0)  -- Better not to have negative values
end
