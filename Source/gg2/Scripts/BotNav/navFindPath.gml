/// navFindPath(startNode, goalNode, team, hasIntel, blocked)
/// A* over the built nav graph, for a character of `team` carrying the intel or not.
/// Returns a ds_list of node indices from startNode to goalNode inclusive, or -1 if
/// the goal is unreachable or the graph is not ready. The caller owns the returned
/// list and must ds_list_destroy it.
///
/// team/hasIntel are what make gates work. Everything else in the graph is static -
/// one edge set serves every bot - but a gate's passability depends on who is asking
/// (F26), so gate nodes are carried in the graph with full connectivity and refused
/// here, per query, by navGatePassable. The effect is that a blue bot's search simply
/// cannot expand through a red spawn gate, so it routes the long way round rather than
/// walking into a wall, and the same graph still serves the red bots going through it.
///
/// `blocked` is a ds_map of navEdgeKey values to skip, or -1 for none - a caller's
/// private list of edges it has already tried and failed to traverse. It is the
/// anti-thrash half of the path follower (F35): without it a bot that wedges in a
/// doorway re-plans, gets handed the same route it just failed, and wedges again
/// forever. Keeping it out of the graph keeps it per bot, which it has to be, and
/// keeping it a ds_map rather than a cost multiplier keeps the heuristic admissible.
///
/// The test is on the edge rather than on the node it arrives at, because an arc can
/// cross a gate without landing on it (see navEdgeAdd). It also falls out of that that
/// a bot standing inside a gate it may not pass - one that just picked up the intel,
/// or anyone the setup gates shut around - still gets edges *out*: those arrive
/// somewhere ungated and so are never refused.
///
/// Uses ds_priority for the open set with lazy deletion - a node can be pushed more
/// than once and stale copies are skipped when popped, because they are already
/// closed. GM8 does have ds_priority_change_priority for a real decrease-key, but it
/// needs a handle per queued item that ds_priority does not hand back, so lazy
/// deletion is both simpler and what the structure actually supports.
///
/// The adjacency index is built once with the graph rather than per call. Rebuilding
/// it here was costing an O(edges) pass before every search even started - about 2ms
/// of the 2.9ms a query took on cp_dirtbowl - for a table that never changes between
/// builds.
///
/// The heuristic is straight-line distance between surface midpoints in mask cells.
/// Walk cost is also measured in cells, so the heuristic never overestimates a walk
/// and A* stays admissible. Fall edges are charged their drop height, which is at
/// least the straight-line distance they cover vertically, so they do not break it
/// either.

var startNode, goalNode, team, hasIntel, blocked, openSet, gScore, cameFrom, closed;
var current, nb, e, eStart, eCount, i, tentative, path, guard;
var gx, gy, cx, cy, nx, ny;

startNode = argument0;
goalNode = argument1;
team = argument2;
hasIntel = argument3;
blocked = argument4;

if(!global.navReady)
    return -1;
if(startNode < 0 or goalNode < 0)
    return -1;
if(startNode >= global.navNodeCount or goalNode >= global.navNodeCount)
    return -1;

if(startNode == goalNode)
{
    path = ds_list_create();
    ds_list_add(path, startNode);
    return path;
}

gScore = ds_grid_create(1, global.navNodeCount);
ds_grid_clear(gScore, -1);
cameFrom = ds_grid_create(1, global.navNodeCount);
ds_grid_clear(cameFrom, -1);
closed = ds_grid_create(1, global.navNodeCount);
ds_grid_clear(closed, 0);

gx = (ds_grid_get(global.navNodes, NAV_NODE_X0, goalNode) + ds_grid_get(global.navNodes, NAV_NODE_X1, goalNode)) / 2;
gy = ds_grid_get(global.navNodes, NAV_NODE_Y, goalNode);

openSet = ds_priority_create();
ds_grid_set(gScore, 0, startNode, 0);
ds_priority_add(openSet, startNode, 0);

current = -1;
guard = 0;
while(!ds_priority_empty(openSet))
{
    // The graph is a few hundred nodes; a runaway here means a corrupt edge list, and
    // a hung server is far worse than a missing path.
    guard += 1;
    if(guard > 100000)
        break;

    current = ds_priority_delete_min(openSet);
    if(current == goalNode)
        break;
    if(ds_grid_get(closed, 0, current) == 1)
        continue;
    ds_grid_set(closed, 0, current, 1);

    eStart = ds_grid_get(global.navEdgeIdx, 0, current);
    if(eStart < 0)
        continue;
    eCount = ds_grid_get(global.navEdgeIdx, 1, current);

    for(i = eStart; i < eStart + eCount; i += 1)
    {
        nb = ds_grid_get(global.navEdges, NAV_EDGE_TO, i);
        if(nb < 0 or nb >= global.navNodeCount)
            continue;
        if(ds_grid_get(closed, 0, nb) == 1)
            continue;
        if(!navGatePassable(ds_grid_get(global.navEdges, NAV_EDGE_GATE, i), team, hasIntel))
            continue;

        // Its own if, never folded in beside the handle test: GM8 evaluates both sides
        // of and/or unconditionally, so an inline "blocked < 0 or ds_map_exists(...)"
        // calls ds_map_exists on -1 for every caller without a blacklist (F40).
        if(blocked >= 0)
        {
            if(ds_map_exists(blocked, navEdgeKey(current, nb)))
                continue;
        }

        tentative = ds_grid_get(gScore, 0, current) + ds_grid_get(global.navEdges, NAV_EDGE_COST, i);
        e = ds_grid_get(gScore, 0, nb);
        if(e >= 0 and e <= tentative)
            continue;

        ds_grid_set(gScore, 0, nb, tentative);
        ds_grid_set(cameFrom, 0, nb, current);

        nx = (ds_grid_get(global.navNodes, NAV_NODE_X0, nb) + ds_grid_get(global.navNodes, NAV_NODE_X1, nb)) / 2;
        ny = ds_grid_get(global.navNodes, NAV_NODE_Y, nb);
        ds_priority_add(openSet, nb, tentative + point_distance(nx, ny, gx, gy));
    }
}

path = -1;
if(current == goalNode)
{
    path = ds_list_create();
    ds_list_add(path, goalNode);
    cx = goalNode;
    guard = 0;
    while(cx != startNode and guard < global.navNodeCount + 2)
    {
        cx = ds_grid_get(cameFrom, 0, cx);
        if(cx < 0)
            break;
        ds_list_insert(path, 0, cx);
        guard += 1;
    }

    // A chain that did not reach the start means cameFrom was inconsistent; report no
    // path rather than a path that does not start where the caller asked.
    if(ds_list_find_value(path, 0) != startNode)
    {
        ds_list_destroy(path);
        path = -1;
    }
}

ds_priority_destroy(openSet);
ds_grid_destroy(gScore);
ds_grid_destroy(cameFrom);
ds_grid_destroy(closed);
return path;
