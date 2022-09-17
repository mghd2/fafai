Fixes Made
- Don't send units or engineers to locations they can't reach (result: helpful, but not a fundamental change in strength)
- Don't stream units in



Fixes Needed
- Units eventually get stuck in a blob
- Use the ACU in combat, or at least to hold a key expansion
- Don't attack superior forces
- Get reclaim
- DONE Tech up
- DONE Make air
- Get intel
- Use factory rally points (or similar), and then generate squads of clumps of units
- Should I try and use the various platoon.lua AIs?
- ACU Snipe mode (if lots of units around ACU, attack)
- Some engineers get stuck, and need to move to prod themselves.  Eventually only the ACU seems to work?


vs M27

On Regor, there's basically one expansion path but it crosses a puddle.
ACU walk is probably important, and probably make factories there.
Do really badly..

Does OK on Open Palms
Pretty good on Twin Rivers

vs Updated M27

vs DilliDalli
Problem on Twin Rivers: sending loads of units to attack the islands that get stuck uselessly

RNG
It's strong; lots of factories and good unit usage
Yeah really strong


Command Queue:
- Can be got; it's a list
- platoon.lua is a bit weird but doesn't imply any new behavior
- Maybe when you issue a command it can fail, and the command queue is empty?  Seems like the base AI relies on this without any tick waits
- spreadattack.lua is very interesting: seems like commands have a .type and .position.
- .type goes through TranslatedOrder (in that file)
- Then makes a SimCallback call to GiveOrders(unit_orders=orders, unit_it=unit:GetEntityId(), From=GetFocusArmy())
- This uses IssueClearCommands and then calls a bunch of regular functions (boring)
- construction.lua implies type can be "Script", and that that's something worth waiting for to not be true (watchForQueueChange())
- construction.lua also has some of what looks like command creation
- The type and position don't work?
- Can they be matched up with the return values of the various Issue functions at least?