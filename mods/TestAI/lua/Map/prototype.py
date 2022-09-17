import time

# - Types are land or sea
# - Regions are disconnected by the same type; each has a unique id.
# - Zones are totally connected internally, and belong to regions.
# - Layers are air, land, sea, hover

class Map:
    def __init__(self) -> None:
        self.land_regions = []
        pass

    def can_path_to(self, start, end, layer) -> bool:
        return True

    # Find the k nearest things of "type" to position - e.g. engineers, armies or mexes.
    def find_k_nearest(self, position, entity_type, number):
        pass

    def find_path_to(self, start, end, layer, safe=False):
        pass

# Might be many types?  How to handle that?  Maybe just have them separate?
class Region:
    pass

# A smallish convex area that fits into a grid
class Zone:
    def __init__(self) -> None:
        pass

    # Record new information about how many enemy units are here
    def update_intel(self, new_intel):
        new_units = self.intel - new_intel
        left_units = new_intel - self.intel
        self.scanned_tick = time.now()
        # Record the movement velocity of all seen units

        # Is there a way we can identify if stuff has been killed?  Probably not really practical.

    # Every maybe 5s, call this
    def tick_threat_spread(self):
        # Assume all known enemy factories are building units, and create new threat there (mix of types based on the factory)
        # Attempt to spread moving threat according to velocity.  Don't spread into a scouted area though (would have seen it) - zero the velocity in that case
        # After doing the velocity spread; move part of the threat to neighboring zones (maybe spread 20% of it out like this every 5s; and bias it towards the front line (gets 3x as much))
        # Reduce confidence rating (how to represent?  Maybe think of it as a mean + std dev)

        pass


THREATENTITY_TYPE_KNOWN_UNIT = 0
THREATENTITY_TYPE_SUSPECTED = 1
class ThreatEntity:
    def __init__(self, type) -> None:
        self.type = type
        self.last_seen = 0
        self.last_position = (0.0, 0.0)
        self.last_velocity = (0.0, 0.0)
