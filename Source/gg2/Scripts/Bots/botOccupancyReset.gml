/// botOccupancyReset()
/// Drops both teams' edge occupancy maps and clears every bot's "my route is counted"
/// flag, so the two cannot disagree.
///
/// Called when the nav graph is not ready - which is what a map change looks like from
/// botPopulationUpdate. Occupancy keys are navEdgeKey values built out of node indices,
/// and a node index only means anything to one build of the graph, so counts from the
/// previous map would otherwise sit in the maps making arbitrary edges of the new one
/// look busy.
///
/// Clearing the flags is the half that is easy to forget. Destroying the maps alone would
/// leave every bot believing its route was still counted, so the next botPathFree would
/// decline to decrement, and the route would then be added a second time on the next plan
/// - a count of 2 for one bot, on a map where it is the only thing walking.
///
/// WARNING: global.players can hold -1 for a dangling roster entry, and -1 is GM8's `self`, so
/// `mate.botOccupied = false` on one would quietly write the *caller's* flag. Same guard
/// as botRoleAssign's, and for the same reason. `mate` rather than the obvious `other`
/// because `other` is a GM8 keyword and `var ... other;` kills the build at startup.

var i, mate;

// Nothing built yet, or already cleared. The caller runs this on every tick the graph is
// not ready, which is every tick of a cold build - over a second on the largest map - so
// the no-op case has to cost two comparisons rather than two ds_map_destroys and a walk
// down the roster.
if(!variable_global_exists("botOccupancy0"))
    exit;
if(global.botOccupancy0 < 0 and global.botOccupancy1 < 0)
    exit;

if(global.botOccupancy0 >= 0)
    ds_map_destroy(global.botOccupancy0);
global.botOccupancy0 = -1;
if(global.botOccupancy1 >= 0)
    ds_map_destroy(global.botOccupancy1);
global.botOccupancy1 = -1;

if(!variable_global_exists("players"))
    exit;

for(i = 0; i < ds_list_size(global.players); i += 1)
{
    mate = ds_list_find_value(global.players, i);
    if(mate == -1)
        continue;
    mate.botOccupied = false;
    mate.botOccupiedTeam = -1;
}
