import math
import random
import matplotlib.pyplot as pyplot
from itertools import permutations
from cProfile import Profile
from pstats import Stats
prof = Profile()
prof.enable()

random.seed(11)  # Only really want this for performance comparison

MEX_BUILD_TIME = 12  # For a T1 engy
HYDRO_BUILD_TIME = 80  # Never actually do this alone - maybe using 10BP is best (40s)?
MEX_INCOME = 2
HYDRO_INCOME = 6  # Made up; they aren't that good later in the game (e.g. mediocre at T2)
TIME_CONSTANT = -0.02  # Make this too close to zero and it expands way too many paths.  Mex upgrading is worth about 0.004, but that's too computationally expensive to mirror.
WALK_SPEED = 1.9  # 0.8 for 5x5, 0.4 for 10x10 etc.  Those speeds are for maps made by screenshot.  For maps datalogged, I think speed is probably 1.9
TIME_LIMIT = 360  # Value doesn't count after here.  It's problematic to increase too far, because the value function becomes too close to zero.
MAX_VALUE_LIMIT = 0.0  # Calculated later; max value at TIME_LIMIT
NUM_MARKERS = 0  # Also filled in later
MARKERS = []  #  ^^


# Is there a way I can calculate the TIME_CONSTANT?
# An engy costs 50M and some opportunity cost and some risk of death.  Let's say it costs 100M.
# Upgrading mexes is "safe", and costs 1000M say.
# Mex upgrading is like infinite Target(0, 0, time, -1000, +4)
# Does that give me info on defining instant_value_fn?

# Can I do a geometric approach?  On a flat map it's probably possible somehow.  Represent disconnected areas by introducing z value differentiation?
# Really this is about providing a framework to efficiently answer time(A->B).
# A barrier maps to an increasing split.
# If there's a barrier in 2d land along x=0, y>0; then the 
# Might be easier to just design a system that supports the basic functions (find nearest, path distance, etc) efficiently.  A kinda kd tree of regions (that have full internal connectivity).
# - find_nearest_of_type(engy) might pick all free engineers from geometric distance, calc the path distance for the closest and cull any that can't beat that without obstructions

# CALCULATING PARAMETERS
# - Mex upgrading is indeed exponential.  Let's assume infinite T1->T2 mexes that add 4/t and take 1000 to build  dN/dt = 4N/1000.  N(t) = Ae^Bt => dN/dt = ABe^Bt = BN(t) => B = 4/1000
# - That implies a TIME_CONSTANT of 0.004 (this is too computationally expensive).
# - 0.02 means that mass 1 minute later is worth only 30% as much.  0.004 means it's worth 79% as much
# - Hydros are 2/3 BT and 43% mass of equivalent pgens.  That could be an instant transfer of 215M (say 250M with BP); worth about 1/tick by T2 mex valuation
# - I've represented maps as roughly 110x110 (300% zoom of the client screenshot but flip vertical and divide by 10 while reading to get correct co-ords)
# - A 5x5 takes an engineer 2min13 to cross; that means 0.82/s
# - Expanding engineers are separated by 15s roughly

# Hydros
# - Initial hydro seems hard to include because it affects things too much
# - From YSNP we know that it is worth hitting a pair of hydros pretty quickly if there's enough mexes
# - Other than the first (rushed) one, can probably express the others as mass.

# The only good optimization was using base 2
LN2_TIME_CONSTANT = TIME_CONSTANT / math.log(2)
def continuous_value_fn(income, time):
    return income * 2 ** (time * LN2_TIME_CONSTANT)

    # This is what we really want to calculate, with time*TIME_CONSTANT roughly in the range 0 to -10
    # return income * (math.e ** (time * TIME_CONSTANT))

LN2_TIME_CONSTANT_INV = -1.0 * TIME_CONSTANT / math.log(2)
OPT_2P30 = 2 ** 30
def continuous_value_fn_opt(income, time):
    # Let's see if a Taylor expansion is faster
    # Unfortunately we have a fairly large range of values for ct...  (it could be 5), which probably means we need like 10-15 terms
    #ct = time * TIME_CONSTANT
    #value = 1.0
    #for i in range(200, 0, -1):
    #    value = 1 + ct * value / i
    #return income * value

    # How about we use e^x = 2^(x/ln2).
    # This isn't really any better.  Bit twiddling casts could probably gain a lot though...  I think ** isn't optimized for 2ness
    return income * 2 ** (time * LN2_TIME_CONSTANT)

    # As above, but using some integer shifts.  The value is likely to be in 0 to -10 (500 seconds)
    # I think the int kills accuracy, and it's also slower...
    #int_value = (2**31) >> int(LN2_TIME_CONSTANT_INV * time)
    #return float(int_value)/(2**30)*income

# I'm slightly concerned that the quantization here might lead to inefficiency in the algorithm above.  Linear interpolation should fix that, but does mean more work.
# It's slightly faster without interpolation...  Doesn't seem worth trying to optimize this.
lookup_values = []
for i in range(0, 10 * TIME_LIMIT):  # Just have one value per second; we'll hardly ever need the big times but unfortunately we can look up stuff that's arbitrarily late currently
    lookup_values.append(continuous_value_fn(1, i))
def continuous_value_fn_lookup(income, time):
    i = int(time)
    return income * lookup_values[i]


def instant_value_fn(income, time):
    return 0
    # Good way to do this might be mex = contvfn(-cost/buildtime, now) + contvfn(income+cost/buildtime, now+buildtime).
    # Need to make sure it all offsets properly.  Also everything will go wrong if we ever return a negative overall value

# What's the value of continuously building mexes from then on (really should include reclaim too...)
def max_value_fn(income, time):
    # A little optimistic; usually we call continuous_value_fn() with t_0 + build_time
    # This is basically the integral of continuous_value_fn.
    # Should include something from instant as well
    # income = income / 2 -- This is terrible...  Don't do it
    return max(-1.0 * continuous_value_fn(income, time) / (MEX_BUILD_TIME * TIME_CONSTANT) - MAX_VALUE_LIMIT, 0.0)
# Instead of a better heuristic; I've just tinkered with this one - to half the income...
# Started work on a better heuristic...
def tune_max_value_fn(mexes):
    dist = []
    for m in mexes:
        for n in mexes:
            if m == n:
                continue
            dist.append(m.distance(n))
    dist.sort()

# The fraction of the value of something being delayed by this long
TIME_MAX_VALUE_CONST = max_value_fn(1, 0)
def time_max_value(time):
    return max_value_fn(1, time) / TIME_MAX_VALUE_CONST

# Alternative optimized max_value_fn.  This one is based on distances between mexes.
def tuned_max_value_fn(income, time):
    pass

MAX_VALUE_LIMIT = max_value_fn(MEX_INCOME, TIME_LIMIT)  # This works a bit circularly, because it's 0 during the calc of this

# This target is a mex
class Target:
    def __init__(self, x, y, bt, instant_income=0, continuous_income=0) -> None:
        self.buildtime, self.instant_income, self.continuous_income = bt, instant_income, continuous_income
        self.pos = (x, y)
        
    def value(self, arrival_time):
        return continuous_value_fn(self.continuous_income, arrival_time + self.buildtime) + instant_value_fn(self.instant_income, arrival_time + self.buildtime / 2)
    
    # Walk time to target
    def distance(self, target):
        return math.dist(self.pos, target.pos) / WALK_SPEED

    def print(self):
        return 

    def __repr__(self) -> str:
        return "(" + str(self.pos[0]) + ", " + str(self.pos[1]) + ")"


class Path:
    def __init__(self, start_pos, start_time) -> None:
        self.targets = []
        self.end_time = start_time  # No path so far, so ends immediately
        self.start_time = start_time
        self.start_pos = start_pos
        self.min_value_cache = -1.0

    def add_target(self, target):
        cpos = self.targets[-1] if len(self.targets) > 0 else self.start_pos
        self.end_time += target.distance(cpos) + target.buildtime
        self.targets.append(target)
        self.min_value_cache = -1.0

    def contains_target(self, target):
        if target in self.targets:
            return True
        else:
            return False

    # The actual value of the path; memoized
    def min_value(self):
        if self.min_value_cache == -1.0:
            time = self.start_time
            value = 0.0
            current_pos = self.start_pos
            for t in self.targets:
                time += t.distance(current_pos)
                value += t.value(time)
                time += t.buildtime
                current_pos = t
            self.min_value_cache = value
        return self.min_value_cache

    def copy(self):
        new_path = Path(self.start_pos, self.start_time)
        for t in self.targets:
            new_path.add_target(t)
        return new_path

    # An upper bound on the value of any path that starts like this one, based on the maximum possible utility of an engineer
    def max_value(self):
        return self.min_value() + max_value_fn(MEX_INCOME, self.end_time)

    def __repr__(self) -> str:
        return "->".join([str(t) for t in self.targets])


class PathCandidate:
    def __init__(self, path) -> None:
        self.children = []  # More PathCandidates
        self.path_to_here = path
        self.expanded = False  # Has been expanded
        pass

    # This node and all children have been expanded
    def complete(self):
        return self.expanded and all([c.complete() for c in self.children])

    def expand(self, all_targets):
        # Prevent repeat expansion
        count = 0
        if self.expanded:
            return 0

        if self.path_to_here.end_time > TIME_LIMIT:
            self.expanded = True
            return 0

        #  Add a child for every Target that isn't already in the path
        #print("Expanding", self)
        for target in all_targets:
            if self.path_to_here.contains_target(target):
                continue
            new_path = self.path_to_here.copy()
            new_path.add_target(target)
            self.children.append(PathCandidate(new_path))
            #  print("Added child,", self.children[-1])
            count += 1
        self.expanded = True
        return count

    # Return the highest min_value of any child, and that child (or self if this is the leaf)
    def min_value(self):
        if len(self.children) == 0:
            return (self.path_to_here.min_value(), self)
        else:
            min_v = 0.0
            min_c = None
            for c in self.children:
                c_v, c_c = c.min_value()
                if c_v > min_v:
                    min_v = c_v
                    min_c = c_c
            return (min_v, min_c)

    # Return the highest max_value of any child; except for (sub)paths of an optionally specified child
    def max_value(self, exclude_child=None):
        if len(self.children) == 0:
            if self.complete():
                v, _ = self.min_value()
                return v
            #return self.min_value()  # Not sure if it's OK to not skip the exclude child here...
            # Also this causes an infinite __repr__ stack somehow
            return self.path_to_here.max_value()
        else:
            maxv = 0.0
            for c in self.children:
                if c != exclude_child:
                    maxv = max(maxv, c.max_value(exclude_child))
            return maxv

    # Recursively trim out all children that can't beat the min_max_value provided (i.e. max_value for the candidate < min_max_value)
    def trim_max_value(self, min_max_value):
        count = len(self.children)
        self.children = [c for c in self.children if c.max_value() >= min_max_value]
        count -= len(self.children)
        for c in self.children:
            count += c.trim_max_value(min_max_value)
        return count

    # Recursively expand all children with max_value over max_value
    def expand_over(self, max_value, all_targets):
        if len(self.children) == 0:
            return self.expand(all_targets)
        else:
            count = 0
            for c in self.children:
                if c.max_value() > max_value:
                    count += c.expand_over(max_value, all_targets)
            return count

    # This is pretty dangerous: it's important that it doesn't call any functions that also hit __repr__...
    def __repr__(self) -> str:
        min_v, _ = self.min_value()
        return "Candidate (" + str(self.path_to_here) + ", " + str(len(self.children)) + " children, minv =" + str(min_v) + ", maxv =" + str(self.max_value()) + ", exp?: " + str(self.expanded) + ")"

    def print_children(self) -> str:
        print(self)
        for c in self.children:
            c.print_children()

# Roughly need:
# - committed_path
# - big heap of extensions 
# - take the best one; and replace it with all possible 1-target-longer paths
# - Is it best to use the highest min_value, or the highest max_value?  Maybe alternate.  Former alone won't really terminate; so maybe just max?


# How do I represent the objects?
# - A Target is a single location
# - A Path is a list of targets
# - A PathCandidate is a Path, and then a list of PathCandidates?
# - A leaf PathCandidate has some values; non-leaf ones recurse through all their leaves
# - Once the min value of a PathCandidate exceeds the max value of all other PathCandidates under the same parent; it can be committed (i.e. drop the other candidates)

# - Expand the highest max value


# Need to make it stop once there are no mexes left

class DistanceCalculator:
    def __init__(self, start_pos, mexes) -> None:
        self.start_pos = start_pos
        self.mexes = mexes

    # This is hideous, but I'm hoping it might make the lua translation easier
    # 0 means start; 1+ is a mex
    def calc_distance(self, a: int, b: int) -> float:
        if a == 0:
            return self.start_pos.distance(b)
        if b == 0:
            return a.distance(self.start_pos)
        return self.mexes[a - 1].distance(self.mexes[b - 1])

class PossibleMultiPath:  
    def __init__(self, engy_times) -> None:
        self.expansion_paths = []  # Array of (start_time, end_time, [markers]), representing each engineer's expansion path (using marker ids).  This will work better in Lua.
        for t in engy_times:
            self.expansion_paths.append((t, t, [0]))
        self.min_value_cache = 0.0  # Cached values
        self.max_value_cache = 1000000  # 0 and 1M indicate not calculated
        self.children = []  # Would use indices in Lua
        self.expanded = False  # Think this is probably === to len(self.children) != 0 or self.complete == True
        self.complete = False  # All children are also expanded (recursively)

        # I'm still unsure if it's good for me to keep all the parents; but replicate all the data in the children.  It's what I did previously admittedly.
        # Can I do things by just dropping the parents and not recursing?

    # This is correct for the PMP itself, but doesn't consider children yet
    def max_value(self):
        if len(self.children) > 0:
            return max(c.max_value() for c in self.children)
        if self.max_value_cache > 999999.0:
            self.max_value_cache = self.min_value() + sum([max_value_fn(MEX_INCOME, ep[1]) for ep in self.expansion_paths])
        return self.max_value_cache

    # Returns whether it became complete
    # Targets is an array of integer (markers) available for expanding to
    def expand(self, targets) -> bool:
        if self.expanded:
            self.complete = True
            for c in self.children:
                self.complete = c.expand() and self.complete  # Mustn't short-circuit c.expand()
        else:
            # Create children
            for t in targets:
                self.children.append(7)  # Yeah this is way wrong

        # We need to not consider expanding an engy until its ready.
        # I think that means that you just expand the engy with the lowest et; but it might be more correct to try and expand all engies
        # Expand all: +Gives them all a chance to get each mex
        # Expand lowest: +Might be more efficient?
        # I think we have to expand all, so we can flip from using our true max/min values to using the best of any child
        self.expanded = True
        self.min_value_cache = 0.0
        self.max_value_cache = 1000000
        # Since I seem to have made these immutable; I can just calculate in init.

# Say I do remove parents:
# - Then we have a big list of expansions that all run to leaves
# - 
class MultiPathCandidate:
    # Must specify one of the first two params; last 2 go with exp_paths
    def __init__(self, engy_times=[], exp_paths=[], min_v=0.0, max_v=0.0) -> None:
        self.is_leaf = False
        if exp_paths != []:
            self.expansion_paths = exp_paths
            self.min_value = min_v
            self.max_value = max_v
        else:
            self.expansion_paths = [(et, et, [0]) for et in engy_times]  # Each one is (start_time, end_time, [markers], has_been_expanded)
            self.min_value = 0.0  # No mexes => no value
            self.max_value = sum([max_value_fn(MEX_INCOME, et) for et in engy_times])  # All engies spam mexes
        #print(self)

    # Return an array of MPCs; self will be destroyed after
    # Not sure if it's really a good idea to do full expands: the later engineers will rapidly become useless.  Trouble is; can't confidently delete the parent unless I expand ALL engies.
    # What should we do if we're a leaf node?  We should probably just save ourselves.
    # BIG PROBLEM: If I allow paths to expand only 1 engineer at a time; multiple parents could create identical children.
    # I think if I always expand the engineer that's earliest in time, I might be OK?  Still need to remember on the parent that I can't expand that engy though
    def expand(self, must_have_max_value):
        # If we're a leaf node we might want to save ourselves, although we should find a way to inform the caller perhaps...
        if self.is_leaf:
            return [self]

        expanded_anyone = False

        # Find the engineer to expand: the one that's earliest in time and hasn't been expanded yet
        # TODO Is this last condition correct?  Do I need the parent to handle expanding subsequent engineers?
        # Maybe not: if the parent just expands the earliest engineer only (i.e. not preserving itself)
        # We still get everything; because the children will expand the slower engineers later
        earliest_eti = 0
        earliest_et = 999999.9
        for egi in range(len(self.expansion_paths)):
            if self.expansion_paths[egi][1] < earliest_et:
                earliest_et = self.expansion_paths[egi][1]
                earliest_eti = egi

        if earliest_et < TIME_LIMIT:
            # We have more time to spend

            candidates = []
            possible_mexes = [n for n in range(NUM_MEXES)[1:]]
            possible_mexes.append(NUM_MEXES)
            for eg in self.expansion_paths:
                for em in eg[2]:
                    if em != 0:  # Common to all paths and already removed from possible_mexes
                        possible_mexes.remove(em)

            child_is_leaf = (len(possible_mexes) == 1)

            previous_max_value = max_value_fn(MEX_INCOME, earliest_et)
            for em in possible_mexes:
                new_min = self.min_value
                new_max = self.max_value
                walk_time = MARKERS[self.expansion_paths[earliest_eti][2][-1]].distance(MARKERS[em])
                new_et = earliest_et + walk_time + MARKERS[em].buildtime
                if new_et > TIME_LIMIT:
                    continue
                target_value = MARKERS[em].value(earliest_et + walk_time)
                new_min += target_value
                if not child_is_leaf:
                    new_max += target_value + max_value_fn(MEX_INCOME, new_et) - previous_max_value
                else:
                    new_max = new_min  # max is only higher if there are more mexes to come

                if new_max < must_have_max_value:
                    continue  # Not good enough, don't bother creating it

                new_exp_paths = [p for p in self.expansion_paths]  # Shallow copy top level paths
                new_exp_paths[earliest_eti] = (self.expansion_paths[earliest_eti][0],
                    new_et,
                    [m for m in self.expansion_paths[earliest_eti][2]] + [em]
                )  # Deep copy modified path and extend

                c = MultiPathCandidate(exp_paths=new_exp_paths, min_v=new_min, max_v=new_max)
                candidates.append(c)
                expanded_anyone = True

        if not expanded_anyone:
            # All engineers were out of time, so make ourselves a leaf and preserve ourself
            self.is_leaf = True
            self.max_value = self.min_value
            return [self]

        return candidates

    def generate_paths(self):
        exp_paths = []
        for eg in self.expansion_paths:
            new_path = Path(MARKERS[0], eg[0])
            for mt in [MARKERS[em] for em in eg[2]]:
                new_path.add_target(mt)
            exp_paths.append(new_path)
        return exp_paths

    def __repr__(self) -> str:
        engy_paths = ["->".join([str(em) for em in ep[2]]) for ep in self.expansion_paths]
        return "Candidate min=" + str(self.min_value) + " max=" + str(self.max_value) + " paths=" + ", ".join(engy_paths)


class MultiPathCalculator:
    def __init__(self, engy_times) -> None:
        self.candidates = [MultiPathCandidate(engy_times=engy_times)]

    def expand(self, over_min, over_max, must_have_max_value):
        # New better version, that only expands candidates that have good min or max values
        exp_candidates = []
        for c in self.candidates:
            if c.max_value > over_max or c.min_value > over_min:
                exp_candidates += c.expand(must_have_max_value)
            else:
                exp_candidates += [c]
        self.candidates = exp_candidates
        
    # Returns number trimmed
    def trim(self, value):
        new_candidates = []
        old_count = len(self.candidates)
        for c in self.candidates:
            if c.max_value >= value:
                new_candidates.append(c)
        self.candidates = new_candidates
        return old_count - len(self.candidates)

# Accelerate mex lookup and allow partial querying
# Only use one layer for now; containing 30x30 squares (about sqrt of map size)
class MexGetter:
    def __init__(self, mexes):
        self.mexes = mexes  # Lowest layer
        self.layers = []  # Indexed by x/30, y/30; contains a list of squares
        # How do I combine value though?
        self.maxes = []  # Sorted list of highest to lowest values present inside any layer


    # Step is the number of mexes to get
    def get_good_mexes(pos, step):
        pass



# Given a point, I want to be able to find stuff that exceeds a certain value

# Say distance k is the half distance
# I'd get pretty good results by just having a grid of k*k squares probably?

# Say I have the min-value = 1 grid
# I might get better results by being able to combine local values?  i.e. many nearby mexes get scored together


# Each slice stores its child slices, and direct references to the 
class Slice:
    def __init__(self, xmin, xmax, zmin, zmax):
        self.xmin = xmin
        self.xmax = xmax
        self.zmin = zmin
        self.zmax = zmax


class SMPC:
    # Params optional but together
    def __init__(self, exp_path=[], min_v=0.0, max_base=0.0) -> None:
        self.is_leaf = False
        if exp_path != []:
            self.path = exp_path
            self.hit_map = {m for m in exp_path[2]}
            self.min_value = min_v
            self.max_base = max_base  # The true max_value is min_value + max_base * temperature
        else:
            self.path = (0, 0, [0])  # (start_time, end_time, [markers], has_been_expanded)
            self.hit_map = {0}
            self.min_value = 0.0  # No mexes => no value
            self.max_base = 1.0
        #print(self)

    # Return an array of SMPCs; self will be destroyed after
    # Not sure if it's really a good idea to do full expands: the later engineers will rapidly become useless.  Trouble is; can't confidently delete the parent unless I expand ALL engies.
    # What should we do if we're a leaf node?  We should probably just save ourselves.
    # BIG PROBLEM: If I allow paths to expand only 1 engineer at a time; multiple parents could create identical children.
    # I think if I always expand the engineer that's earliest in time, I might be OK?  Still need to remember on the parent that I can't expand that engy though
    def expand(self, must_have_max_value, temperature):
        # If we're a leaf node we might want to save ourselves, although we should find a way to inform the caller perhaps...
        if self.is_leaf:
            return [self]

        expanded_anyone = False

        et = self.path[1]
        if et < TIME_LIMIT:
            # We have more time to spend

            candidates = []

            child_is_leaf = (len(self.hit_map) == NUM_MEXES - 1)

            for em in range(1, NUM_MEXES+1):
                if em in self.hit_map:
                    continue

                new_min = self.min_value
                new_max = 0
                max_base = 0
                walk_time = MARKERS[self.path[2][-1]].distance(MARKERS[em])
                new_et = et + walk_time + MARKERS[em].buildtime
                if new_et > TIME_LIMIT:
                    continue
                target_value = MARKERS[em].value(et + walk_time)
                new_min += target_value

                if not child_is_leaf:
                    max_base = time_max_value(new_et)
                    new_max = new_min + temperature * max_base
                else:
                    max_base = 0.0
                    new_max = new_min  # max is only higher if there are more mexes to come

                if new_max < must_have_max_value:
                    continue  # Not good enough, don't bother creating it

                new_path = (et,
                    new_et,
                    [m for m in self.path[2]] + [em]
                )  # Deep copy modified path and extend

                c = SMPC(exp_path=new_path, min_v=new_min, max_base=max_base)
                candidates.append(c)
                expanded_anyone = True
            if expanded_anyone:
                return candidates

        # All engineers were out of time, so make ourselves a leaf and preserve ourself
        self.is_leaf = True
        self.max_base = 0.0
        return [self]

    def generate_path(self):
        new_path = Path(MARKERS[0], self.path[0])
        for mt in [MARKERS[em] for em in self.path[2]]:
            new_path.add_target(mt)
        return new_path

    def __repr__(self) -> str:
        engy_paths = ["->".join([str(em) for em in ep[2]]) for ep in self.expansion_paths]
        return "Candidate min=" + str(self.min_value) + " max_base=" + str(self.max_base) + " paths=" + ", ".join(engy_paths)

class SMPCalc:
    def __init__(self, mexes, start_pos, init_temp) -> None:
        self.mexes = mexes
        self.start = start_pos
        self.candidates = [SMPC()]

        self.temperature = init_temp
        print("Starting at temperature ", self.temperature)

    def expand(self, over_min, over_max, must_have_max_value):
        # New better version, that only expands candidates that have good min or max values
        # Now also try and work out the trim parameters during this
        exp_candidates = []
        for c in self.candidates:
            if c.min_value + self.temperature * c.max_base > over_max or c.min_value >= over_min:
                exp_candidates += c.expand(must_have_max_value, self.temperature)
            else:
                exp_candidates += [c]
        self.candidates = exp_candidates

    def trim(self, value):
        new_candidates = []
        old_count = len(self.candidates)
        for c in self.candidates:
            if c.min_value + self.temperature * c.max_base >= value:
                new_candidates.append(c)
        self.candidates = new_candidates
        return old_count - len(self.candidates)

    def run(self):
        minv = 0.0
        maxv = 0.0000000000001

        while minv < maxv:
            self.temperature = self.temperature * 0.9  # Cool
            if len(self.candidates) > 100:
                print("COOLING")
                self.temperature = self.temperature * 0.8  # Cool
            if len(self.candidates) > 1000:
                print("COOLING QUICKLY")
                self.temperature = self.temperature * 0.7  # Cool

            # Can I calculate the temperature needed to maintain a certain length?

            # I think I want to control the number of expansions kept at each stage
            # If I had a good get-best-nearby-weighting-travel-time accelerator I wouldn't need to consider every point each stage 
    

            print("NEW ROUND")
            old_candidates = len(self.candidates)
            self.expand(minv * 0.8, maxv * 0.9, minv * 0.99999999)
            old_minv = minv
            minv = max([c.min_value for c in self.candidates])
            maxv = max([c.min_value + self.temperature * c.max_base for c in self.candidates])
            print("EXPANDED min=" + str(minv) + " max=" + str(maxv) + " num=" + str(len(self.candidates) - old_candidates))
            # Need to trim now...  How?
            removed = self.trim(minv * 0.9999999999999)
            print("TRIMMED " + str(removed) + " TABLE LEN " + str(len(self.candidates)))

            if old_minv == minv:
                print("DID NOT FIND A BETTER PATH")

        return self.candidates[0].generate_path()

def SimAnneal()

def plot(engy_start_pos, path_pairs, orig_mexes):
    mxs = [engy_start_pos.pos[0]] + [t.pos[0] for t in orig_mexes if t.continuous_income < 3]
    mys = [engy_start_pos.pos[1]] + [t.pos[1] for t in orig_mexes if t.continuous_income < 3]
    pyplot.plot(mxs, mys, linestyle='', marker='o', color="black")
    rxs = [t.pos[0] for t in orig_mexes if t.continuous_income >= 3]
    rys = [t.pos[1] for t in orig_mexes if t.continuous_income >= 3]
    pyplot.plot(rxs, rys, linestyle='', marker='o', color="red")

    counter = 0
    for pp in path_pairs:
        counter += 1
        xs1 = [engy_start_pos.pos[0]] + [t.pos[0] for t in pp[0].targets]
        ys1 = [engy_start_pos.pos[1]] + [t.pos[1] for t in pp[0].targets]
        xs2 = [engy_start_pos.pos[0]] + [t.pos[0] for t in pp[1].targets]
        ys2 = [engy_start_pos.pos[1]] + [t.pos[1] for t in pp[1].targets]
        pyplot.plot(xs1, ys1, label=str(counter)+"A")
        pyplot.plot(xs2, ys2, label=str(counter)+"B", linestyle='--')
    pyplot.axis('equal')
    pyplot.title("Paths")
    pyplot.legend()
    pyplot.show()

def find_expansion_path_smpc(mexes, engy_start_pos):
    # Want to first greedily expand a path; use that to set the initial temperature?
    gsmpc = SMPCalc(mexes, engy_start_pos, 0.000001)  # Greedy
    gsmpc.run()

    # This is giving me too high of an initial temperature (5 here, when I want more like 1-2)
    # Oh, I think max_base runs too high: It should be <=1

    # How about I work out the temperature needed to limit the table length to say 1000?
    # Bounded memory consumption is desirable?

    temp = gsmpc.candidates[0].min_value
    smpc = SMPCalc(mexes, engy_start_pos, temp)  # Use the previous attempt as the initial temperature
    smpc.run()
    return smpc.candidates[0].generate_path()


def find_expansion_path(mexes, engy_start_pos):
    start_path = Path(engy_start_pos, 0.0)
    candidate = PathCandidate(start_path)
    candidate.expand(mexes)

    all_expands = 0

    while True:
        expanded = 0
        trimmed = 0
        #time.sleep(1)
        min_v, min_c = candidate.min_value()
        #print("Expand best min", min_c)
        expanded += min_c.expand(mexes)  # Expanding the best min_value too might help converge from both sides
        min_v, min_c = candidate.min_value()
        #print("Min", min_v, "is", min_c)
        trimmed += candidate.trim_max_value(min_v)  # Get rid of bad branches
        max_v = candidate.max_value(min_c)  # Now get the best competitor to the best path
        #print("Expand best max", max_v)
        expanded += candidate.expand_over(max_v - 0.01, mexes)  # Negative offset encourages doing a bit more expansion per loop (might be bad if we're repeatedly trimming them though? Removed -1.0 for now)
        all_expands += expanded
        trimmed += candidate.trim_max_value(min_v)  # Seems like we have to do this again...

        #print ("Best alternative is", max_v)
        if min_v > max_v:
            # Also need to continue expanding within the optimal branch for sufficiently long
            print("Got optimal expansion path")
            break
        if expanded == 0 and trimmed == 0:
            print("Didn't do anything?")
            break

    candidate.print_children()
    
    (_, best_path) = candidate.min_value()
    for t in best_path.path_to_here.targets:
        print(t)
    print("Used", all_expands, "expands")
    return best_path.path_to_here

# engy_delays = [0, 30, 70] - 1 at start, 1 after 30s, 1 after another 40s
def find_k_expansion_paths(engy_delays):
    mpc = MultiPathCalculator(engy_delays)
    minv = 0.0
    maxv = 0.0000000000001
    while minv < maxv:
        print("NEW ROUND")
        old_candidates = len(mpc.candidates)
        mpc.expand(minv * 0.9, maxv * 0.99, minv * 0.99999999)
        old_minv = minv
        minv = max([c.min_value for c in mpc.candidates])
        maxv = max([c.max_value for c in mpc.candidates])
        print("EXPANDED min=" + str(minv) + " max=" + str(maxv) + " num=" + str(len(mpc.candidates) - old_candidates))
        # Need to trim now...  How?
        removed = mpc.trim(minv * 0.9999999999999)
        print("TRIMMED " + str(removed) + " TABLE LEN " + str(len(mpc.candidates)))

        if old_minv == minv:
            print("DID NOT FIND A BETTER PATH")

    return mpc.candidates[0].generate_paths()

# As an optimization, given I have a "claim" system, I could have partial claims on more distant stuff?
# A claim has a strength, based on ETA (exp decay).  Claimed objects could be available to others but at much reduced value?

# How about I make a kinda recursive version?  Make biggish squares over the map, and compute maximum values for those squares
# e.g. a 20x20 square: for any entry/exit point, what's the best path through it.  Issue is if the average value density is high we might want to skip bad reclaim

def find_old_paths(mexes, engy_start_pos, engy_times):
    mexes_trim = mexes[:]
    paths = []
    for t in engy_times:
        paths.append(find_expansion_path_smpc(mexes_trim, engy_start_pos))
        print("Got a path")
        print(paths[-1])
        #  This code doesn't actually use the passed in mexes anyway
        #for t in paths[-1].targets:
        #    mexes_trim = [mex for mex in mexes_trim if t.pos[1] == mex.pos[1] and t.pos[2] == mex.pos[2]]
    return paths


# Notes on mex data:
# - Mexes mustn't be in the same spot; or it generates both paths but the exclude-best-child process only excludes one of them.  Just aggregate them
# - Many mexes close to each other will hurt performance: better to pick one spot from which they can all be built and stack the value.
mexes1 = [
    Target(0, 10, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(0, 20, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(0, 30, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(0, 40, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(0, 50, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(10, 0, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(30, 30, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(30, 40, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(60, 30, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(70, 32, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(100, 200, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(110, 200, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(110, 210, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
]
mexes2 = [  # This one tests ignoring one close mex in favor of a pair
    Target(0, 10, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(0, 11, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(8, 0, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(100, 200, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
]

mexes3 = []
while len(mexes3) < 1000:  # Random test.  Collisions unlikely.
    mexes3.append(Target(random.randint(-200, 200), random.randint(-200, 200), MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME))
    #if len(mexes3) % 10 == 0:
        # Little bit of super mexes
        #mexes3.append(Target(random.randint(-400, 400), random.randint(-400, 400), MEX_BUILD_TIME, instant_income=-36, continuous_income=2*MEX_INCOME))

mexes4 = [  # Double strength mex test
    Target(0, 10, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(11, 0, MEX_BUILD_TIME*2, instant_income=-36, continuous_income=MEX_INCOME*2),
]

start5 = Target(7, 117, 0)
mexes5 = [  # Theta Passage (FAF Version); no hydros; ridges ignored
    Target(12, 117, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(5, 107, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(15, 98, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(27, 103, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(55, 114, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(78, 109, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(87, 114, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(58, 89, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(29, 64, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(6, 62, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(17, 36, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(7, 16, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(15, 8, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(36, 18, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(62, 7, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(63, 30, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(102, 27, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(97, 16, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(107, 6, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(116, 13, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(88, 58, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(114, 55, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(108, 79, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(113, 88, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
]

start6 = Target(16, 39, 0)
mexes6 = [  # Loki (FAF Version); no hydros, terrain guesstimated.  Map is actually 10x10, so use a lower walk speed
    Target(16, 36, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(18, 37, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(14, 39, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(15, 41, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(5, 70, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(2, 73, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(4, 105, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(8, 105, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(4, 109, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(8, 109, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(35, 126, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME), # Terrain adjusted down by 15
    Target(37, 127, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME), # ^^
    Target(38, 124, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME), # ^^
    Target(38, 71, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME), # Terrain adjusted down by 15 and right by 10
    Target(33, 73, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME), # ^^
    Target(28, 76, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME), # ^^
    Target(35, 22, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target(39, 19, MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    # Other half of map omitted
]

start7 = Target(134, 124, 0)
mexes7 = [  # Open Palms.  No correction, and no hydros
    Target( 443 ,  345 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 483 ,  493 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 62 ,  410 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 173 ,  293 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 480 ,  482 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 381 ,  395 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 230 ,  382 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 373 ,  385 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 370 ,  395 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 226 ,  375 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 188 ,  68 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 423 ,  232 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 146 ,  250 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 375 ,  251 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 211 ,  147 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 304 ,  54 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 208 ,  325 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 49 ,  235 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 297 ,  216 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 88 ,  279 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 208 ,  466 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 408 ,  229 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 75 ,  444 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 461 ,  282 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 28 ,  39 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 457 ,  271 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 216 ,  465 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 225 ,  266 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 384 ,  385 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 380 ,  260 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 436 ,  67 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 306 ,  228 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 317 ,  176 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 320 ,  91 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 295 ,  134 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 170 ,  419 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 471 ,  492 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 324 ,  444 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 127 ,  130 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 46 ,  224 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 416 ,  239 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 61 ,  157 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 301 ,  366 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 29 ,  25 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 235 ,  278 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 141 ,  120 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 349 ,  329 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 96 ,  293 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 162 ,  184 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 330 ,  99 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 152 ,  257 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 103 ,  282 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 95 ,  272 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 42 ,  30 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 84 ,  427 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 448 ,  92 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 138 ,  130 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 357 ,  218 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 187 ,  420 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 331 ,  82 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 312 ,  52 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 285 ,  125 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 176 ,  429 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 427 ,  81 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 337 ,  92 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 177 ,  412 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 415 ,  218 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
    Target( 130 ,  120 , MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),
]

start0 = Target(0, 0, 0)

###################################################################################################
# Test run starts here
###################################################################################################

# Which test to use
mexes = mexes3
engy_start_pos = start0
NUM_MEXES = len(mexes)
MARKERS = [engy_start_pos] + mexes  # 1 indexed mex-wise

# Do the test
engy_times = [0.0]
#kp = find_k_expansion_paths(engy_times)  # Just one engineer - all the mex stuff comes from MARKERS
# ^^ Seem to have a bug on Loki; 720max 0/30.  One engineer walks a huge (early on) gap 3 times for no reason
#print(kp)
op = find_old_paths(mexes, engy_start_pos, engy_times)  # Doesn't actually pay attention to the engy times
print(op)
kp = op

def map_to_targets():
    map_here = """info: Recording marker "Mass" at 443.5,15.427700042725,345.5"""  # etc
    import re
    for line in map_here.split("\n"):
        m = re.search("Mass.* (\d+).5,\d+.\d+,(\d+).5", line)
        if m:
            print("Target(", m.group(1), ", ", m.group(2), ", MEX_BUILD_TIME, instant_income=-36, continuous_income=MEX_INCOME),")

prof.disable()
prof.dump_stats('test_expansion.py.stats')
with open('test_expansion.py.out', 'wt') as output:
    stats = Stats('test_expansion.py.stats')
    stats.sort_stats('cumulative', 'time')
    stats.print_stats()

joined_paths = [(kp[i], op[i]) for i in range(len(engy_times))]
plot(engy_start_pos, joined_paths, mexes)

# Notes on using this in practice:
# - Definitely aggregate nearby mexes
# - Definitely trim mexes that aren't nearby
# - Trim ally mexes, and enemy mexes (but only give them 40% let's say)
# - Multiple engineers is still very painful perf wise.
# - Probably best to have a budget of expansions; rate limit based on that.
# - If we spend too long trying to do all the engineers, then bail on doing an at once calculation and do 1 engy at a time greedily.
# - If that fails I guess we could try again with a shorter time frame.

# How often and how much do we actually want to expand?
# We start with +1M, +20E; and say we normally get 3 close mexes and a hydro or so.
# That puts us on +7, +120.  
# Say an expanding engineer generates k mass income per second (100% efficiency would be k=1/6 (not counting E cost), ...  Realistic is probably more like 0.05)
# - Using 1M/s means getting 10E/s (roughly - more late game), which means we need a pgen every 2/k seconds, using 12k engineers.  Also need 0.25 LF, which means 15k engineers?
# - For 0.05, that means we need 0.6 pgen engies and 0.75LF engies; so it's kinda 1:1:1.5 or so 
# Say we want to start putting something into military (either actual T1 Land, or Air Scouts / Bombers / Transports based on map size) fairly early.
# How much military?  The least military is in team games, or on like the ditch / crazyrush (initially).   Land seems like 

# Overall structure:
# - Compute some expansion paths
# - Update the eco manager to take in a series of expansion paths (and it can request more if it wants; after the first couple maybe just use the old approach)
# - BuildPlanners request units (e.g. one manages the land mix) and can request an energy ratio and eco share


# How to do a first bomber build?
# ACU: pgen -> Air Fac -> Assist Bomber
# Air fac: Bomber -> Scout?

# Close hydro "2nd" bomber?
# Probably a good build on maps where expanding is important: not worthwhile if most of the eco is in the base (really more like a side expansions map wanted: e.g. Open Palms).
# ACU: Land -> Pgen -> 4 Mex -> Hydro -> Air Assist?
# How viable is doing a pgen before a hydro?  Putting 750E into the pgen repays in 38 seconds; ACU builds in 13s; hydro repays in 8s and takes (ACU + 1 engy) 27s to build
# LF, 4Mex, Hydro, xPgen, Air, Assist BO (1 engy + ACU); with 0.5 expanding engies needs power of about 
# - Hydro goes down at ~0E, LF pulls 20, exp engies pull 15, ACU+e making factory pulls 120 (so that's 2 pgens needed).  Once assisting a bomber costs 140
# - Probably works with x=2?  Maybe x=3 allows for better future expansion?


# Bomber is 10 speed, Air Scout is 17-19; if 5x5 diagonal distance is about 250, then air scout catches up after 25s basically (takes 10s to build without stalling)
# 5s interval on the bomb, but no idea how to micro to achieve that