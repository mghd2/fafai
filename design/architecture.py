# High level plan

# Early game build
# - Generate expansion paths (mexes and reclaim and distant hydros)
# - Decide if first hydro or not
# - Decide if ACU used in base
# - Decide if separate islands style
# - Calculate early build, incorporating expansion path mass predictions and hydro timing
# - Lay out build

# - Establish scouting and such
# - Try and generate engies to expand to mexes and reclaim fields (with decent priority)
# - Adjust tank priority


# Priority distribution system:
# - Don't want a simple higher => only that system
# - Maybe priority for a task implies an approx share of the economy?
# - If we're losing in combat, need to increase tank share vs eco share say
# - Adjust air balance and such
# - First prioritize having half as much military strength in each arena (air/land/sea - although calling one a total loss is viable)
# - Do high level balance centrally; and then allow internal bits to have fixed values


# Say we've decided on the %age split between eco, land, air
# - Upgrading the first factory to T2 can be a shared investment (how?)
# - We should record the amount of eco going into various things
# - In order to save up for big tasks (factory upgrades, T2 mexes), we want to accumulate some spare resources (E generation and storage, and M storage, and free budget) and then start (maybe with 1/3rd banked? - means can build in 2/3 time)
# - Task requests and is given eco, but doesn't spend it for a bit

# - Suppose we want to spend 10% of total eco going to T2: really we should project when that'll be enough, and then go super hard aiming to finish then

# - Kinda want to oscillate in practice between eco and strategic especially
# - T2 factories are efficient, so want to slightly underbuild T1 facs

# Approx typical timeline (call most of these the strategic buffer)
# - Initial BO
# - T1 phase, expand, basic production
# - E storage
# - Gun com? (Is it ever actually worth going T2 com other than for com drops?)
# - T2 factory
# - T3 factory
# - Com drop?
# - Big stuff: experimentals, nukes, T3 arty

# When should we go T2?
# - Economically, want to be at around +500E - that'll correspond to about +50M (that seems high?)
# - Militarily, 
# - T1 fac = 20BP for 240M (0.083), T2 fac = 40BP for 580M (0.0689), T3 fac = 90BP for 1440M (0.0625)
# - T1 is 
# Thaam has 25dps, 280hp for 54M.  Ilshy has 117dps, 2500hp for 360M.  Othuum has 400dps, 4700hp for 840M.  Chicken is 3800dps, 67000hp for 26500M.
# Logistics, and (often) range clearly superior for the higher tech force.
# Let's say range is worth twice the closing time.  That means that a range difference of 1 is 1 second of free shooting.
# 2000M is 926dps, 10360hp in Thaams = 9.6M; 650dps, 13890hp in Ilshies = 9.0M (R+8); and 952dps, 11190hp in Othuums (R+4) = 10.6M; and 287dps, 5060hp in Chickens (R+30) = 1.5M (lol)
# Range adjusted: Ilshies can half kill the Thaams before they're in range = big win.  Othuums only get 40% for free but are then better so similar.  Othuums vs ilshies is kinda close
# Striker has 24dps, 280hp for 56M.  Pillar is 54dps, 1500hp for 198M.  Titan is 150dps, 3700hp (given a bonus here for the shield) for 480M.  Percy is 337dps, 7200hp for 1280M
# 2000M is 857dps = 8.6M, 10000hp in T1; 545dps, 15150hp in T2 = 8.3M; 625dps, 15420hp in T3F = 9.6M; 527dps, 11250hp in T3H UEF = 5.9M

# Bit of practical testing time.
# 2160M of ilshies beats its own weight in tanks (1 full hp left) in a straight engage (tanks into ilshies; tiny bit of micro on the tanks but not at the start)
# Othuums significantly beat ilshies
# 5 ilshies charger a slightly cheaper mix of 16 tanks and 16 arty: does quite well.  4 ilshies microd against static but not exploiting range same: absolutely crushes
# Let's say it's a +20% military advantage each time
# So let's say we have a go-to-t2 score (needs to reach 100): 1 point per 15E income, 1 point per 1M income, 1 point per 50M in army (alive, not all time)?  Maybe do something for E in army if mostly air
# go-to-t3 might be: 1 point per 40E income, 1 point per 2M income, 1 point per 100M in army?
# Doesn't really handle islands or playing air, but hey

# General policy on engineer assisting:
# - Most of the time, if it can spend more than the travel time assisting, it should do it.


# Base layout:
# - Spaces adjacent to mexes are for land factories or storage only.  Allow for 2 air facs adjacent to a hydro (sharing a corner).


TargetEcoSplit = (0.3, 0.4, 0.1, 0.2)  # eco, land, air, strategic
EcoSpentLastMin = (400, 400, 100)
Targets = tuple(sum(EcoSpentLastMin) * pc for pc in TargetEcoSplit) - EcoSpentLastMin  # Probably doesn't work; want element-wise subtraction

