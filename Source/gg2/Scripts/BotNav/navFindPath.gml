/// navFindPath(startNode, goalNode, team, hasIntel, blocked, occupancy)
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
///
/// Closed nodes are RE-OPENED when a cheaper route to them turns up, which is what makes
/// the search optimal rather than merely fast. Skipping an already-closed neighbour - which
/// is what this did - is only sound when the heuristic is *consistent*, and consistency is
/// a strictly stronger property than the admissibility the paragraph above establishes.
/// It fires on honest costs too, which is worth knowing: the ctf_truefort blue leg went
/// from 68 nodes to 60 when the re-open went in, so the heuristic was never quite as
/// consistent as the paragraph above argues. It fires harder with `occupancy` below, which
/// perturbs costs deliberately and makes the two properties come apart on purpose.
///
/// A per-bot cost jitter (M7 1.4) used to multiply each edge by up to NAV_PATH_JITTER, and
/// it was deleted. Replaying it offline against the real cached graphs corrected the reason
/// twice over, and both corrections matter for anything that wants to perturb a cost here:
///
///   1. Per-edge noise cannot produce route variety at all. It is mean-reverting: over a
///      sixty-edge route every candidate inflates by about the same average, so the ordering
///      between long routes barely moves. On the full ctf_truefort blue leg all eight bots -
///      seeded with real Player instance ids - got the *identical* 68-node route. The jitter
///      did not fan the team out; it moved the whole team onto one slightly worse route.
///   2. The closed set was not what returned it. Re-running the ctf_truefort n178 -> n177
///      reproduction with and without the re-open gives the same answer at every seed,
///      because under the jittered costs the three-hop route genuinely is cheaper (40.47
///      against the direct jump's 42.54). A* was right; the costs it was given were not.
///      The honest gap is 33.67 against 38.17, only 13% - well inside a 35% jitter. The
///      54.67 that ROUTEVARIETY.md quotes charges n178 -> n196 at 17.50, the walk edge,
///      when a parallel fall edge covers the same hop for 1.00.
///
/// The re-open below is still worth having on its own account - it took that leg from 68
/// nodes to 60 on honest costs - but it is not what makes a perturbation safe. What makes
/// one safe is being the *right shape*, and `occupancy` is the shape that works.
///
/// `occupancy` is a ds_map of navEdgeKey values to "how many bots on this team are already
/// walking this edge", or -1 for none. An edge in it is charged
/// (1 + BOT_OCCUPANCY_COST * count) times its honest cost, so a route that team-mates are
/// already on costs more than one they are not, and a team fans out across whatever
/// alternatives the map offers. Measured offline on ctf_truefort at BOT_OCCUPANCY_COST
/// 0.25: eight bots go from one shared route to eight distinct ones, pairwise edge overlap
/// 1.00 -> 0.23, nodes touched 60 -> 188, and the worst route only 1.23x the optimal.
///
/// It is the right shape for three reasons the jitter was the wrong shape for. It is
/// *structured* rather than random, so what it makes expensive is exactly what is crowded.
/// It is the same for every bot asking at the same moment, so it perturbs no one's view of
/// the graph relative to anyone else's. And it is *coarse* - a handful of edges carry a
/// count at all - so it moves whole routes rather than nudging the ordering of every edge
/// in the graph at once.
///
/// It does still make the heuristic inconsistent, which is what the re-open below is for.
/// Cost measured offline: 1.6x to 2.0x the pops of an unperturbed search, and *fewer*
/// re-opens rather than more (113 -> 50 on the ctf_truefort blue leg) - the extra pops are
/// a wider frontier, not thrashing.
///
/// Callers pass -1 rather than relying on the argument being absent. GM8 gives an unpassed
/// argument the value 0, and 0 is a perfectly valid ds_map id, so a five-argument call would
/// silently read whichever structure happens to own it.
///
var startNode, goalNode, team, hasIntel, blocked, occupancy, openSet, gScore, cameFrom, closed;
var current, nb, e, eStart, eCount, i, tentative, path, guard, cost, eKey;
var gx, gy, cx, cy, nx, ny;

startNode = argument0;
goalNode = argument1;
team = argument2;
hasIntel = argument3;
blocked = argument4;
occupancy = argument5;

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
        // No closed test here. A neighbour that is already closed is still allowed to be
        // improved; see the re-open below and the header for why skipping it is unsound.
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

        cost = ds_grid_get(global.navEdges, NAV_EDGE_COST, i);

        // Its own if for the same reason the blacklist test above has one: GM8 evaluates
        // both sides of and/or unconditionally, so folding the -1 check in beside the
        // lookup would call ds_map_exists on -1 for every caller without an occupancy map.
        if(occupancy >= 0)
        {
            eKey = navEdgeKey(current, nb);
            if(ds_map_exists(occupancy, eKey))
                cost = cost * (1 + BOT_OCCUPANCY_COST * ds_map_find_value(occupancy, eKey));
        }

        tentative = ds_grid_get(gScore, 0, current) + cost;
        e = ds_grid_get(gScore, 0, nb);
        if(e >= 0 and e <= tentative)
            continue;

        ds_grid_set(gScore, 0, nb, tentative);
        ds_grid_set(cameFrom, 0, nb, current);
        // Re-open it. The push below is ignored by the pop loop while the node is still
        // marked closed, so without this the improvement would be recorded in gScore and
        // never expanded from - the node would keep its old, worse successors.
        ds_grid_set(closed, 0, nb, 0);

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
