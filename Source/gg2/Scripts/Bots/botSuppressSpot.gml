/// botSuppressSpot(char, lastX, lastY, foeTeam)
/// Where to keep shooting when a target is held but cannot be seen: the nearest point on
/// the route it would have to take to come back into view, rather than the stale position
/// it was last seen at. Returns a nav node, or -1 when there is no useful answer and the
/// caller should keep doing whatever it was doing.
///
/// M7 3.8 gave a bot 30 ticks of memory across a lost sightline and had it keep firing at
/// the last position actually seen. That is right for a corner someone is about to step
/// back around and wrong for one they left, because the stale position is behind cover by
/// construction - the bot is shooting the wall it lost them behind. What was missing is
/// any notion of *where they must come from*, and the graph already knows: the enemy has
/// to walk a route, and the first node on it this bot can see is the place worth denying.
///
/// ⚠️ Worth building because the case is common, and that was measured before any of it
/// was written rather than assumed (M9 §9.2 asked for exactly this check). Twelve bots on
/// koth_valley over 3172 frames: **13733 bot-ticks with a live target, 2744 of them - 20%
/// - with no line of sight to it**, and for a Heavy specifically 1432 of 6442, or 22%. So
/// about one tick in five of every engagement is spent aiming at a remembered position,
/// and the 30-tick drop does not already eat most of it.
///
/// ⚠️ A BOUNDED BREADTH-FIRST WALK, NOT AN A* - AND THAT IS A MEASUREMENT, NOT A
/// PREFERENCE. M9 §3.1 specifies "run navFindPath from there toward the Heavy's own node
/// and walk that path outward". Built that way first and timed: **8.13 ms a call on
/// koth_valley's 270 nodes**. Amortised over BOT_TARGET_PERIOD that is 3.25 ms a frame for
/// six Heavies, which sounds survivable and is not - nothing staggers the bots, so six
/// recomputing on the same frame is 48.8 ms against a 33.3 ms budget, on the *smallest*
/// interesting map. ctf_truefort has 687 nodes. That is a hitch, and it is the same shape
/// as the one navNodeFromWorld's row index was just built to remove.
///
/// The search here expands at most BOT_SUPPRESS_HOPS nodes outward from where the enemy
/// was, and stops at the first one this bot can see. Breadth-first order is *fewest hops
/// from where they were*, which is the soonest they could appear - which is the question
/// being asked. It also needs no route to this bot to exist at all, where the A* version
/// returned -1 whenever one did not.
///
/// The walk uses the ENEMY's gates, not ours: it is their route, and a red bot must not
/// decide that a blue enemy will come out through a red spawn gate. hasIntel is false - a
/// carrier is on everyone's HUD anyway, and guessing wrong only closes gates, which can
/// only shrink the answer.

var char, lastX, lastY, foeTeam, srcNode, queue, seen, n, hops, eStart, eCount, i, to;
var nx, ny, best;

char = argument0;
lastX = argument1;
lastY = argument2;
foeTeam = argument3;

if(!global.navReady)
    return -1;

// Where they were. Snapped downward, because a position in mid-air belongs to the surface
// under it - a target last seen jumping is going to land on something.
srcNode = botNodeSnap(lastX, lastY);
if(srcNode < 0)
    return -1;

best = -1;
queue = ds_queue_create();
seen = ds_map_create();
ds_queue_enqueue(queue, srcNode);
ds_map_add(seen, srcNode, 1);
hops = 0;

while(!ds_queue_empty(queue) and hops < BOT_SUPPRESS_HOPS)
{
    n = ds_queue_dequeue(queue);
    hops += 1;

    // The world point a character standing on this node occupies: the middle of its run,
    // at chest height, which is both what the sight test wants and what the aim solve is
    // about to be handed.
    nx = navColWorldX(floor((ds_grid_get(global.navNodes, NAV_NODE_X0, n)
                             + ds_grid_get(global.navNodes, NAV_NODE_X1, n)) / 2));
    ny = (ds_grid_get(global.navNodes, NAV_NODE_Y, n) + NAV_BOX_H) * NAV_CELL_SIZE - 23;

    // Not the node they were last seen on: that one is behind cover by construction, and
    // shooting it is exactly the behaviour this replaces. The test is cheap and it is also
    // the guard that stops a caller aiming at a wall when the enemy simply stood still.
    if(n != srcNode)
    {
        if(!collision_line_bulletblocking(char.x, char.y, nx, ny))
        {
            best = n;
            break;
        }
    }

    eStart = ds_grid_get(global.navEdgeIdx, 0, n);
    if(eStart < 0)
        continue;
    eCount = ds_grid_get(global.navEdgeIdx, 1, n);
    for(i = eStart; i < eStart + eCount; i += 1)
    {
        to = ds_grid_get(global.navEdges, NAV_EDGE_TO, i);
        if(ds_map_exists(seen, to))
            continue;
        if(!navGatePassable(ds_grid_get(global.navEdges, NAV_EDGE_GATE, i), foeTeam, false))
            continue;
        // GM8's ds_map_replace does not insert a missing key, so this is add-only and the
        // exists test above is what keeps it that way.
        ds_map_add(seen, to, 1);
        ds_queue_enqueue(queue, to);
    }
}

ds_queue_destroy(queue);
ds_map_destroy(seen);
return best;
