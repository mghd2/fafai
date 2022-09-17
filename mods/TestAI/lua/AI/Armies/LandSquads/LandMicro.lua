-- For an n vs 1 fight we want to keep our units at similar range
-- Do we want to go all in once we are in range of them?
-- How do we calculate?
-- Say we make a grid of the local area, and mark how much DPS there is against each spot

LandMicroController = Class({
    New = function(self, brain)
        self.brain = brain
    end,

    DoMicro = function(self)
        local floor = math.floor
        local vdist2 = VDist2
        -- What do we need to store?
        -- DPS against land for each square
        -- HP or Value available to attack in each square?
        local grid = {}
        -- Actually maybe these should be the middle of the squares?
        local basex = 100  -- floor(the lowest x in the grid)
        local basez = 100  -- floor(the lowest z in the grid)

        while not self.brain:IsDefeated() do
            -- Get all units around the rally_pos

            -- Delete the unpathable squares

            -- Ideally would consider ranges all the way out to sniper bots (75) I guess?  That's a lot of squares though.
            -- I guess I consider all units out to like 90 away, but only plot DPS within 20 of the source
            -- Is it reasonable to plot DPS on 1600 individual squares?  Not really; but maybe with spacing of 2-3?
            local enemies = {}  -- TODO: Get enemies nearby
            for _, u in enemies do
                local epos = u:GetPosition()
                if u.range + 14 < vdist2(epos[1], epos[3], self.rally_pos[1], self.rally_pos[3]) then
                    -- Some of the considered range is reachable
                    for i, sqs in grid do
                        for j, sq in sqs do
                            if vdist2(basex + i*2, basez + j*2, epos[1], epos[3]) < u.range + 3 then  -- Allow 2 extra range
                                sq = sq + u.DPS
                                -- Do I need to also record HP?
                            end
                        end
                    end
                end
            end

            -- Bomber AoE is (Sera) 4(T1), 3(T2), 6(T3), 20(T4)
            -- T1 Arty is (Sera) 1.5 radius
            -- OC is 2.5 radius
            -- If spacing between units is 3+, immune to arty
            -- If units are at say 2 spacing, there's 400 possible squares in the considered range?

            -- Say we have a grid of DPS against us and HP we can hit, what do we do?
            -- We need to find separated spots for all our units where they're in range enough, but only just

            -- I could try just doing a greedy placement of units?  If I have a system for saying the best square for one unit.
            -- If I do this then I want to weight being near to the units current pos to enhance stability when it all moves.

            -- Worth trying to translate the whole group as well

            -- I could work out the strength weighted CoM of us and nearby short range enemies?


            WaitTicks(3)
        end
    end,

})

function ManageUnitRange(self, unit)


end

-- Need to extend intel gathering to monitor for things shooting us.  Probably we can just know what / where they are,
-- the projectile and damage basically uniquely identify units anyway.

-- Maybe I make my own formations?
-- Do everything as either rotating the formation, or moving the layers forwards or backwards?

-- Are the in game ones good enough?  They do do some weird stuff, but it does save quite a bit of hassle
-- Main issue with them is when new units arrive
-- If I use separate groups for unit types I have to manage differing speeds myself
-- Constraining the output space is pretty useful though, and I probably need to solve the same challenges for
-- custom formations anyway...

-- If I just have an output space of (x, z, heading), what do I do?

-- What are the different things I can do?
-- A. Units face the enemy base while idle
-- B. Retreat from bad fights towards my base
-- C. Move into good fights that are in the front arc (facing the fight)
-- D. Move in so we have enough to kill not just to maintain one units range
-- E. Move back a little in fights we're taking if we don't need to be this close
-- F. Merge reinforcements into the formation on arrival
-- G. Deal with getting stuck by breaking the formation
-- H. Don't advance away from incomplete fights (e.g. pick a new fight before we've killed the mex)
-- I. Reissue move orders for reinforcements if the squad has moved too far
-- J. Still failing to reset to a safe position when we get wiped out
-- K. Properly detect squad idle state when reforming but not really moving

-- Unprioritized or elsewhere:
-- X. Have a safe staging area, and batch units together to send large groups to squads (say at least 20% of
-- the squad or wait for at most 30s)?

-- Plan: F, A, K, B, C, D, E, H, I, G, J
-- Done: F, A, K, B

-- Where do I implement this?

-- B: Retreat from bad fights
-- Need to be able to continuously assess whether the squad should proceed forwards.
-- rally_pos best defines where the squad is
-- 

-- Using formation moves breaks the is state idle stuff: a formation can be 99% stationary, but 0% idle

function LandMicro(self, unit)



    -- Mostly I want to keep at range, but keep all units similarly at range
    -- Unless we're inside the enemies range, in which case all in
    -- That's going to mean identifying targets is important
    -- Want to maintain the right amount of cohesion: close enough for firepower, but reduce AoE
    -- Keep AA and scouts at the back
    -- Retreat if we don't have enough direct fire left
    -- If we get chased and are slower, should we continue retreating?  Probably (reclaim).

    -- For range, I should get the map to record the main weapon range of everything


    -- Say if we're managing 20 units:
    -- We have a target to go to, which we move towards if no enemies around
    -- Also have a distractibility parameter, that describes how willing we are to not go to the target
    -- Do I want to be able to guard a spot?  I think so - so a max radius?
    -- If we see enemies we respond, but we increase the weight of returning
    -- If 3 units are near to the side, we should move in
    -- If we come up with an equal force, need good micro to win

    -- Let's assume most units move up to 3.5/s, so that's the error margin on ranges?

    -- How do we arrange a retreat in 3D?  Say we have all the enemies known, and their range.
    -- How far do we want to go?  Avoid local minima.

    -- Computationally expensively-ish, I can calculate the amount of threat on every "square" (TBD)
    -- I guess the strict answer then is some graph search algorithm?
    -- Dijkstra style expansion, with weights
    -- This assumes units are static, which is untrue.
    -- Maybe when calculating the threat graph, I can calculate "threat now", "threat in 10s", "20s", "30s"?
    -- Also incorporate current velocity.  3 types of layer: current, likely@t, possible@t
    -- Where likely is an extrapolation of current velocity, and possible is for any inputs
    -- (@0 == current)
    -- How do I deal with old intel?  Do I need to time shift the likely/possible?
    -- ^^ If I do this really well, then maybe ASF micro solves itself?
    -- Need it to be quite efficient to get away with that much work, but probably possible
    -- For movement x secs out, equally weight the current, likely@x and possible@x?


    -- Given that, finding a retreat path is probably just ~Dijkstra
    -- Edge cost is (assume all equal length): 
    -- For most purposes we probably want to generate net distance from the origin (not air fights)
    -- To do that we can reduce weights that go away?  Maybe I can do something in common with
    -- moving in a preferred direction?

    -- Say DirectionPreference=None|Away|Direction
    -- None: edge_cost = threat against us / our threat against them


    -- Threat against us is a bit complex.  I guess really it's a dot product of our unit types with their threat types?
    -- Ours against them is even worse because the range could be different

    -- If there's economic (non-military) threat somewhere, assign a dummy structure that
    -- grows its threat exponentially (1m double), and prioritizes scouting by its threat.
    -- When scouted its threat is set to 0.

end




-- Alternate land management system:
-- Have an Army, representing a major combat force (a few per map kind of size)
-- They move to one of our expansions (towards the enemy), and try and hold it
-- They'll request more troops (submitting anticipated efficiency / need), and track their own performance

-- A good strategy would probably be to hold 70% of the map, and then crush either the enemy ACU or base?