Things to check!!!
- Grep for EngineerBuildQueue is very enlightening
- ^^ ProcessBuildCommand is a good example for how to build something I think



How do we decide what to build?
- Eco reinvestment vs units vs tech vs scouting
- Units?  Military objectives inform vague directions (land spam default; navy and air if water; land to counter a proxy and such)
- Have E (amount and rate) and M (same) and BP (localized) resources - how to distribute it?
- Location of structure?


- Eco?  E, M and BP.  BP is distributed - demand for BP somewhere may vary (reclaim; fortifying; countering a proxy etc)
- Scouting?



How can we make an early build work well?  Really we need assists, and an economy projector
- Probably not really worth doing
- Early game spreading engies is good, because travel time doesn't cost resources



TODO:
- How do I get stuff to assist?
- Kinda need a better way to express construction, and possibly to then compile that down.

TODO: 
- How do I see what's going on in the game?
- Is map analysis the right starting point?
- Can't really do good unit macro or micro or good build orders without it I guess

- What would be good things to add on top of minimal AI to make it decent?
- ACU usage makes a big difference
- Proper tank management (take fights you'll win and such)
- Can do air micro pretty easily
- Initial BO?

Eco projection:
- Start with investment percentage; probably need to curve it with time
- Then M; include both generation and conservative expected reclaim
- M projection can be based on quantities of mexes in range
- E and BP requirements need to be based on M
- Mobile BP is localized as well; each region gets to have a request

- Making T1 mexes and getting reclaim is basically free
- Maybe have pgens be free as well?
- Maybe you don't need to set a super high eco fraction initially; instead rely on the lack of BP for initial expansion?
- Factories don't have to be part of eco?


def eco_fraction():
    return 30

def project_m():
    mnow = currentMassInNotReclaim()
    projections = [mnow]
    for i in range(1, 1, 10):
        projections[i] = projections[i-1] * 


How to hook into Lua?
m27 has some suggestions
- You can use a a builder in a buildergroup that only runs custom logic (they suggest engies reclaiming)
- Something about that builder referencing a custom PlatoonAI (this is p52)


Base planning:
- Master planned bases (mostly)
- Include space for TMD, AA and maybe shields
- T1 pgens can be reclaimed eventually
- If we do end up needing things like T2 PD that's potentially awkward
- A little hard to adapt to air/land.  Maybe I could have a block that can do either?
- Blocks are a little awkward if there isn't much space
- Land factories in a ring around a mex
- Air factories in a pair next to a hydro; leading into a grid


Taking control / stopping default AI being annoying:
- DilliDalli only hooks OnCreateAI and InitializeSkirmishSystems
- I think it might be slightly easier: OnCreateAI could be hooked to set self.SkirmishSystems = false, and then only need to worry about InitialAIThread really (which waits 30 ticks and then forks some other threads, which I can easily hook: EvaluateThread and ExecuteThread).
- Evaluate thread might be killable with self.ConstantEval = false?  Dunno when self:SetConstantEvalutate() gets called though, which resets it.
- ExecuteAIThread is annoying: I should probably replace it with my own code.
- InitializeSkirmishSystems() might be called before OnCreateAI()?  At least it is when called by AbandonedByPlayer() (AI replaces leaver).
- ISS() does seem to need hooking... Dunno why the variable exists then...
- Looks like InitializeArmies() in ScenarioUtilities.lua is the caller.  That does call GetArmyBrain() and check the SkirmishSystems variable, so maybe that might work?
- Did this.
- I'm losing half the economy monitor stuff: it's in ISS()

How does the default AI manage tanks?
- There's a Platoon called ArmyPool; but it might be turned off
- PickEnemy runs, and so does BaseManagersDistressAI (uses the waiting units)
- ISS AdBuilderManagers() for the main base
- There are a bunch of AIs in platoon.lua: some are quite useful - e.g for experimentals / TML etc
- ReclaimAI is useful say.  It does attempt to PlatoonDisband() itself sometimes, and uses brain:PlatoonExists(), relies on the economy monitor.



- How to decide what to attack?  Measure what locations are strategic: include based in that.
- Increase priority of attacking things nearer strategic locations (e.g. especially our own base)

Does it make sense for me to try and pull in all this complex code, when DilliDalli replaced it all (kinda) in a few kloc?


Use the normal framework?
- Can I just do things like "make two PG before an LF" with normal build tasks?
- Add "Expecting to stall M/E" and so on
- For eco management, give each building a category, and a "check category is funded" BC?


Mapping:
- Need to understand the distribution of economic value
- Is there loads of it (especially reclaim) => expand and tech
- Is there only a little => proceed slower
- Is it easy to hold => Hold and tech
- Is it hard to hold => Full T1 spam

- For all the points of economic value, work out the relative distance from us / enemy: between 0.0 (our base) and 1.0 (enemy bases)
- For multiplayer, work out if it's nearer us or our allies (with some balancing: a draft?)
- We can then value the middle of the map

- Raiding groups will have a low retreat tendency (like to be on our side); ACU quite high.
- Raiders should seek out valuable targets and avoid disadvantageous combat.  Don't need to retreat to our base though: better to pick a different target.
- On our side of the map we can take even fights anywhere, or bad fights defending stuff (will get reclaim).
- How many armies and how big?  If there's two lanes, is it better to have 2 equal?  Probably not.
- Do it by matching the enemy sizes?
- Say I take all units, work out the potential pressure on each spot now, in 10s, in 20s etc (assuming everything converges there).  This will be useful for going all in against an ACU.
- 
- If there's more than one enemy ACU, want to aim to kill eco and such.  Only 1: kill ACU trumps all.
- On Twin Rivers, need to not lose bases; but otherwise concentrate forces.
- On Open Palms M27 mostly attacks down the middle, but redirects units to defend.  A side attack is probably better though?

Goals of unit movement:
1. Keep units alive
2. Take good trades
3. Acquire valuable territory
4. Defend valuable territory
5. Destroy enemy investments
6. Die where we can get reclaim
7. Micro for advantage

How can I do each one individually?  Then attempt to synthesize.
1. I think this is somewhat subsumed by 2?
2. Move in when we have superior strength (may include more range etc), retreat otherwise
3. 
4. Fortify at frontline resources.  Despatch units to intercept raiders.  Guard key expanding engineers (and / or expand with ACU).
5. Estimate strength needed to kill quickly; compare values
6. Adjust trade parameters 
7. Stay near max range away from enemies.  Engineers dodge and flee.