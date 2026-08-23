/// botRunupCol(char, node, takeoffCol, jumpDir, maxCells)
/// The anchor column a bot should back up to before a jump: up to maxCells behind the
/// takeoff column, following WALK edges out of `node` so the run-up may continue onto
/// the surfaces the bot walked in over, and stopping at the last column that still has
/// floor under it.
///
/// The clamp this replaces was the whole bug. botPathKeys already decided on a run-up
/// correctly - it set targetCol = takeoffCol - jumpDir*BOT_RUNUP_CELLS - and then
/// clamped it into [x0, x1] of the node the bot is standing on. A node one anchor column
/// wide, which is what the top step of a staircase is, resolves that clamp back to the
/// column the bot is already on, so the run-up was a no-op and the bot jumped from a
/// standstill. On koth_gallery that is n56 -> n44: 96px of gap, 75px of arc, into the
/// riser and back down the pit, forever.
///
/// Following walk edges is safe *because of what a walk edge is*. navWalkEdges emits one
/// only between runs that touch on the same row, or that are one mask cell apart
/// vertically with overlapping spans - and characterHitObstacle takes a one-cell step for
/// free, keeping hspeed entirely (only a genuine wall zeroes it). So a chain of walk
/// edges is one continuous floor that a character accelerates across exactly the way
/// botJumpReach models. A FALL or DROPTHROUGH edge is not: backing across one walks the
/// bot off a ledge. A JUMP edge is not either: backing across one means flying it again
/// to get back. Neither is followed, which is why this tests NAV_EDGE_WALK rather than
/// "any edge going the right way".
///
/// Measured before it was built (gg2-agent/tools/navfollow.js plus the run-up model):
/// letting the run-up leave the source node takes the Heavy's unflyable jump edges from
/// 3310 to 253 across all twenty-three cached graphs, and koth_gallery's 105 to zero.
/// ⚠️ The cap does not matter - 6, 10, 14, 20, 30 and unbounded cells all give 253 - and
/// that is the useful part of the finding. The gate refuses to leave faster than
/// needVx + BOT_JUMP_VTOL, so six cells is already enough to reach the cap on almost
/// every arc. The fix is being allowed to leave the node at all, not being allowed to
/// run further, so BOT_RUNUP_CELLS stays where it is.
///
/// Gates are honoured per query, the same way navFindPath honours them: a red bot may
/// not build its run-up through a blue spawn gate, and a carrier may not back into its
/// own. Without that, the run-up would walk into a wall the bot cannot pass, go nowhere,
/// and trip the stuck detector on an edge that was never the problem.
///
/// Returns takeoffCol itself when there is nowhere to go, which is a run-up of zero and
/// leaves the caller with exactly the behaviour it had before.

var char, node, takeoffCol, jumpDir, maxCells;
var want, frontier, cur, hops, eStart, eCount, i, to, tx0, tx1, best, bestSpan;

char = argument0;
node = argument1;
takeoffCol = argument2;
jumpDir = argument3;
maxCells = argument4;

if(!global.navReady)
    return takeoffCol;
if(node < 0 or node >= global.navNodeCount)
    return takeoffCol;
if(jumpDir == 0)
    return takeoffCol;

// The column we would like to reach: maxCells behind the takeoff, away from the jump.
want = takeoffCol - jumpDir * maxCells;

cur = node;
if(jumpDir > 0)
    frontier = ds_grid_get(global.navNodes, NAV_NODE_X0, cur);
else
    frontier = ds_grid_get(global.navNodes, NAV_NODE_X1, cur);

// Bounded rather than "until we run out of floor": a node can be one column wide, so a
// long staircase is a long chain, and this runs inside a path follower that is already
// the per-tick hot spot. BOT_RUNUP_HOPS is comfortably more than BOT_RUNUP_CELLS worth
// of one-column nodes.
for(hops = 0; hops < BOT_RUNUP_HOPS; hops += 1)
{
    // Far enough already.
    if(jumpDir > 0 and frontier <= want)
        break;
    if(jumpDir < 0 and frontier >= want)
        break;

    eStart = ds_grid_get(global.navEdgeIdx, 0, cur);
    if(eStart < 0)
        break;
    eCount = ds_grid_get(global.navEdgeIdx, 1, cur);

    // The neighbour that reaches furthest back, among those that actually continue the
    // floor at the frontier. "Touches and extends" is two tests, not one: a node that
    // overlaps the frontier without reaching past it adds no run-up and would let this
    // loop sit on the spot until it ran out of hops.
    best = -1;
    bestSpan = 0;
    for(i = eStart; i < eStart + eCount; i += 1)
    {
        if(ds_grid_get(global.navEdges, NAV_EDGE_TYPE, i) != NAV_EDGE_WALK)
            continue;
        if(!navGatePassable(ds_grid_get(global.navEdges, NAV_EDGE_GATE, i), char.team, char.intel))
            continue;

        to = ds_grid_get(global.navEdges, NAV_EDGE_TO, i);
        tx0 = ds_grid_get(global.navNodes, NAV_NODE_X0, to);
        tx1 = ds_grid_get(global.navNodes, NAV_NODE_X1, to);

        if(jumpDir > 0)
        {
            // Running up leftwards: the neighbour must reach the frontier from the left
            // (its right end is within a cell of it) and start further left than it.
            if(tx1 < frontier - 1 or tx1 >= frontier)
                continue;
            if(best < 0 or tx0 < bestSpan)
            {
                best = to;
                bestSpan = tx0;
            }
        }
        else
        {
            if(tx0 > frontier + 1 or tx0 <= frontier)
                continue;
            if(best < 0 or tx1 > bestSpan)
            {
                best = to;
                bestSpan = tx1;
            }
        }
    }

    if(best < 0)
        break;

    cur = best;
    frontier = bestSpan;
}

// Never past the floor that was actually found, and never past what was wanted.
if(jumpDir > 0)
    return max(want, frontier);
return min(want, frontier);
