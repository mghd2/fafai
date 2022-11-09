Map design goals


Modularity:
- I may want to have multiple views that store different data and support different calculations
- I think I want to build threat differently at each layer
- Views usually will want to store aggregated data (e.g. for a 32x32 block)
- Maybe I have a base map that stores all the data (the 1x1, ..., ?x? grids)

- I could have shared views between multiple AI instances, and per-AI views?
- - It's hard to do this if the view is split inside the map class (per AI)
- - Sharing pathing data might not be that important though

- Do I want to have fixed zoom levels across all views?
- - Might make things simplest?  1x1 probably needed (but hardly used)
- - Maybe 1x1, 5x5, 32x32?
- - It's nice if they're strict subsets of a single one; and if they divide the map size nicely?
- - Odd numbers are nice for pathing because they have a centre though (contradiction)
- - For powers of two; 1x1, 4x4, 16x16, 64x64?
- - Or 1x1, 8x8, 64x64?  << Seems good?


Many things will be along the lines of:
- Find an expansion path optimizing the time weighted value; with certain filters and threat disincentives


Maybe I should start with air, so there's no reachability concerns?

I should start incorporating intel early on