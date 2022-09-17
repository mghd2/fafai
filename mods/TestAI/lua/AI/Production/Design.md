Task:
- Make a certain thing now using certain builders
- Return 






EcoAllocator:
- Base class for anything that needs to assign resources
- Given a weight
- Knows how much total resources it has, and is 
- Communicates a mass:power ratio it wants upwards



EcoStrategy:
- Varies based on map and game situation
- Specifies high level investment split between certain areas
- Areas are: Eco, Air, Land (per zone?), Navy (per zone?), Expansion (engineers, mexes and reclaim gatherers), Defense (TMD, static AA, SMD, shields, PD etc)

EcoBuilder:
AirBuilder:
LandBuilder:
NavyBuilder:
ExpansionBuilder:
- Given a budget from the EcoStrategy, 




Questions:
- Need to make enough pgens
- Need to make enough factories
- Should priority be decided by the parent?  It kind of is - Strategy splits between various theaters.  A child needs to be able to zero themselves though.