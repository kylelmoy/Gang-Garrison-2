/// botOccupancyMap(team)
/// Returns the ds_map of edge occupancy counts for one team, creating it on first ask,
/// or -1 for a team that does not field bots (spectators).
///
/// The counts are keyed by navEdgeKey(from, to) and hold "how many bots on this team
/// currently have this edge in an installed route". navFindPath multiplies an edge's
/// cost by (1 + BOT_OCCUPANCY_COST * count), so the more team-mates are already walking
/// an edge the less attractive it is to the next one to plan - which is the whole route
/// variety mechanism (see navFindPath's header for what it replaced and why).
///
/// Per team rather than one shared map, because the thing being spread out is a team.
/// A blue bot has no reason to avoid the route red is walking - if anything it wants to
/// be on it - and folding both teams into one map would have each team's routes push the
/// other's around for no reason anyone could see from the outside.
///
/// The maps live on globals rather than on anything per-bot because occupancy is the one
/// piece of route state that is deliberately *shared*: it is what makes the mechanism
/// model bots bunching up rather than approximating it with per-bot noise, and it is why
/// the penalty is the same for every bot asking at the same moment.
///
/// Keys are node indices, which only mean anything to one build of the graph, so the maps
/// are dropped on a map change - botOccupancyReset, called from botPopulationUpdate when
/// the graph is not ready.

var team;
team = argument0;

if(team != TEAM_RED and team != TEAM_BLUE)
    return -1;

if(!variable_global_exists("botOccupancy0"))
{
    global.botOccupancy0 = -1;
    global.botOccupancy1 = -1;
}

// Two named globals rather than a global array indexed by team: an unset global array
// slot reads as 0 in GM8, and 0 is a perfectly valid ds_map id - so a missed
// initialisation would silently share whichever structure happens to own id 0 rather
// than failing. A named global can be tested with variable_global_exists.
if(team == TEAM_RED)
{
    if(global.botOccupancy0 < 0)
        global.botOccupancy0 = ds_map_create();
    return global.botOccupancy0;
}

if(global.botOccupancy1 < 0)
    global.botOccupancy1 = ds_map_create();
return global.botOccupancy1;
