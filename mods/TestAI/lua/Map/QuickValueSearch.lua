local DEBUG_MODE = false

local ZOOM_CONFIG = {
    {Size = 10, TargetCount = 10},
    {Size = 30, TargetCount = 20},
    {Size = 90, TargetCount = 40},
    {Size = 270, TargetCount = 80},
}

QuickValueSearch = Class({
    New = function(self, value_fn)
        self.value_fn = value_fn


        -- The maps are at different zooms (1 through 4).  Each one is a progressively more zoomed out subset.
        local example_map = {
            -- Do I want these sorted?  Maybe.
            Squares = {},  -- Squares[square] = calculated value.  These are only the "best" few squares
            Count = 10,  -- Current actual number of squares
            BestValue = 0,
            WorstValue = 0,
        }
        self.qvs_maps = {}  -- i, j indexed
        self.qvs_squares = {}  -- [square] = {each map entry listing it}
    end,

    -- Source will be an I, J map co-ordinate
    -- filter_fn(square) returns a bool - must be true to consider a square
    FindBest = function(self, map, source, half_distance, filter_fn)

        -- Pick an appropriate zoom to start at based on the half_distance
        -- If half_distance is 100, then we want 3 I think?




        if DEBUG_MODE then
            -- Recalculate naively across the whole map, and report how different we ended up
        end
    end,

    -- This structure isn't probably that good for this
    FindBestPath = function(self, map, source, half_distance, filter_fn)

    end,

    -- TODO: Call this on Claim / UnClaim
    -- Call this when a square has changed
    -- If the change exceeds tolerances, then we recalculate
    -- TODO: Problem - I can't replace the square because I want to use lots of references to them
    -- Thus I need to have a sub-table in a square that contains the values that I can pass to this and can update
    -- But keep the square root, with its I, J, Pos etc the same.
    SquareUpdated = function(self, square, new_values, old_values)
        local new_value = self.value_fn(new_values)
        local old_value = self.value_fn(old_values)
        if new_value > old_value then
            -- More valuable - might need to add to more maps
            for i, map in self.qvs_squares[square] do
                

            end


        elseif new_value < old_value then
            -- Less valuable - may need to remove from maps


        end

    end,

})


-- I want to be able to make a few calculators:
-- - Different move speeds (maybe 2 and 8)
-- - Maybe include pre-computed "exploit times" (notably how long does reclaiming and building take)
-- - I could perhaps make several of these to include common filters?  (e.g. the land zone)
-- Get the 100 best squares:
-- - Scoring them based on their value modified by arrival time from a source (and exploit time)
-- - That haven't already been included in the path
-- exclude_squares means certain squares (not too many) can't be returned (i.e. the ones already in the path)
-- min_score means stop looking if they can't meet that score
-- max_value is the (present time) value of as yet unknown future activity
-- I might only want to return like 10?  Seems like I'm considering calling this repeatedly for the same parent
local function getSquaresTimeValueThreshold(map, source, layer, half_distance, value_fn, filter_fn, exclude_squares, min_score, max_value)

end

-- value_fn takes the new square
-- Do I need a cumulative filter_fn option?
-- Do I want to pass in the initial max value?
-- time_fn returns the time needed to exploit the square (probably I should just put this as a pre-computed thing though)
function FindOptimalPath(map, source, layer, half_distance, value_fn, filter_fn, time_fn)

    -- Start with a value normalizing pass where I employ some bad heuristic to rescale the value_fn
    -- This is important because I'm thinking about using a fixed max_value progression

    local paths = {{source}, source, 0, 0, {source=true}}
    local max_value = 100  -- Non-time adjusted maximum value of "future actions"
    -- Do I need to implement a max_value fn, or can I just use like 100 and floor(0.8x) every iteration?  (Roughly 20 passes to reach 0)
    -- If I did I'd have recalculating of old stuff to deal with?
    -- Basically I might need to keep short paths (including the root) around until big single jumps become properly weighted?
    -- I guess this means I'd need to mass the max_value to the getSquares fn too.
    -- Having a really high max_value is similar but not the same as changing the half_distance

    -- Might be better to adjust how quickly I move the max_value according to how many paths I have in progress?

    -- Say I do (e.g.) 20 steps of max_value (from like 100 down to 0.1 then 0)
    -- And when I expand a path, I add all the expanded nodes to the exclude but keep the parent
    -- Then each iteration, with a lower max_value I expand the parent again (maybe adding 5-10 nodes each time)


    -- Relative to the python version, I could try occasionally reducing the amount of max_value provided?
    -- I could also have nodes be partially expanded maybe?  Where I expand them to the nearby stuff only

    local sq1, sq2, value, end_time
    local path_example = {
        {sq1, sq2},  -- Path to here (ordered)
        sq2,  -- Last square in the path
        value,  -- Value to here
        end_time,  -- Time at which we're done with the last square
        {sq1=true, sq2=true}  -- Map of all squares that have been visited
    }

    while (true) do
        -- Cooling
        -- How much do I do this by?  What's the impact of cooling faster?  Want to manage number of in flight paths
        -- The problem with cooling too fast is if an extension is better than the cooled max_value (should I call this temperature?),
        -- then it may never be considered
        -- At higher temperatures I should probably spend more time expanding the best path (min)
        -- High temps will encourage staying nearby

        -- Maybe I do a greedy expansion, then set the initial temperature to twice that value?
        -- Or I could just set the temperature based on observed paths?

        max_value = math.floor(max_value * 0.8)

        -- Calculate limits
        -- TODO: Move this into "as we go" while we make paths

        -- Trimming phase
        -- TODO: Merge trimming into the expansion phase: no point adding and removing from an array (expensive)
        -- TODO: Don't use a function for this
        -- min_value must exceed min_limit; max_value must exceed max_limit
        local min_limit = 7
        local max_limit = 9
        local keep_fn = function(path)
            return
                path[3] > min_limit and
                path[3] + max_value * math.pow(2, path[4]) > max_limit
        end

        -- Expansion and trimming phase: get the best 10 or so new paths for each current path
        -- TODO: Better to get more expansions from the good ones
        local new_paths = {}
        for _, p in paths do
            for _, next in getSquaresTimeValueThreshold(p) do
                local new_path = {new_path_appending_next = true}  -- TODO: Actually calculate; including end_time and the value
                if keep_fn(new_path) then
                    table.insert(new_paths, new_path)
                    p[5][next] = true
                end
            end
            if keep_fn(p) then
                table.insert(new_paths, p)
            end
        end
        paths = new_paths



    end

    -- The old implementation basically relied on limiting expansions to control memory consumption

    -- I'd like to be able to cope with a range of square values more; e.g. get squres with time adjusted value > x efficiently

end

-- Here's a thought on find_best_from(source):
-- Is there something possible about interleaving the values?
-- e.g. X=123, Z=456; we can write P=142536, and then nearby points are nearby in the line
-- ^^ works better in binary, maybe scaling x down by root(base) so there's no systemic bias towards 
-- Use a real kd tree, that makes binary splits trying to have 50% on each side (rebalancing occasionally)?
-- Adding in values is maybe a little tricky; because I want large values to be close to everything (so in many places); so it's not that simple
-- Say I have an interleaved point P, and a value V.
-- I want doubling (or base* say) V to search k units wider
-- Just have a hierarchy of search trees?

-- If I want to do things like find_best(source, value) = {max(value*e^-k<time from source>}, which I think I do, then I have several ways
--     - Just consider everything in a huge area
--     - Have a way of saying "get points within x of source with value at least y"
    
--     10x10 maps are 512x512
    
--     - This requires pre-computation of the values though
--     - For the latter, I can do a series of {map of points at least k}.  Need to be able to access only the nearby points though.
--     - If an individual square is 1 say, maybe I have
--     map_1: [i][j] = the square (as long as value > 10)  -- Don't store this in the quick tree, use the real square
--     map_2: [i/2][j/2] = {the squares with value > 20}
--     map_3: [i/4][j/4] = {the squares with value > 40}
--     ...
--     - Really I don't want to use fixed cutoffs though?  Maybe I just want to include like the best handful?
--     - Do I want two versions, with different rates of expansion?  (e.g. instead of taking a 2x2 of candidates, should I go bigger?)
    
--     map_1: [i][j]
--     map_2: [i/10][j/10] = {the top 10% of squares}
--     map_3: [i/100][j/100] = {the top 1% of squares}  -- Would it be better to referent map_2 or direct to map_1?
--     map_4: [i/1000][j/1000] = {the top 0.1% of squares}  -- ^^ (but map_3)
--     -- Direct is better: if it's indirect then we end up grabbing too much.
    
--     Do I want a top x% list, or a rising cutoff?  The cutoff is very hard to determine though; but makes things a bit easier to be precise with.  I could record the cutoff that the top x% implies?
    
    
--     If I get a "top X%", I should bound it: it gets fed the top 10%, and if it exceeds 12% some get dropped, or goes below 8% readded (basically a full recalc)
    
--     Then to find the highest time weighted point near x, z I can do:
--     -- IF I use the double value each layer approach
--     - Work out value halving distance based on speed: say it's 6 [144 squares]
--     - Go through map_1 for all the squares within 6; find the max
--     - Go through map_2 for all the squares within 6-12; they must be ~double good
--     - Go through map_3 for all the squares within 12-18; they must be 4x good
--     -- Problem is travel time is linear but the square sizes are exponential...
    
--     -- I want separate decay constants for valuation (fairly long; few mins), and for travel time scaling (30s?).  First expanding engineer (special case) might want even less than 30s?
    
--     -- If I'm working with an air transport at decay time = 60.
    
--     Key question is when to use a higher level map?
--     - Say I start with the close stuff in map 1 always.
--     - I have a best actual thing of v; that's within 1 halving interval.
    
--     - Work out that we care about stuff within 600 units (transport?)
--     - Don't want to use map_1 at all probably (a single map_1 square might only represent like a 1% scaling.
--     - I think the key question is how much variation does the distance f  unction impose per adjacent square?
--     - If it's >50%, probably need to use the next layer down to start with; but if it's like <10% at a coarser level the finer one is definitely a waste
--     - Say I'm looking at 5 by 5 squares (not at layer 1 necessarily: each of some size such that that covers an exp decay to 50%).
--     - Never want to pull too many squares in that first step (because each contains a list of 1x1 squares!)
--     - I know everything outside there will be scaled down by 0.5+
    
--     How many squares do I want to look at?
    
    
    
    
--     Do want to figure out a way to blend value: e.g. two 100 reclaims right next to each other is worth more than a 110 on its own.
    