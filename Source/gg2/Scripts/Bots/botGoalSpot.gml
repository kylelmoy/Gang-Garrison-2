/// botGoalSpot(char, tx, ty, minDist, maxDist, losSense, highBonus)
/// Finds the nav node this bot should stand on in order to *do something to* (tx, ty),
/// and returns its index - or -1 if no node in the graph qualifies. The chosen node's
/// own stand position is published in global.botSpotX/global.botSpotY, next-call
/// convention, the same way navJumpTakeoff publishes the rest of the arc it proved.
///
/// This is milestone 7 tier 3's one piece of new structure, and it exists because four
/// separate items on the M7 list all want the same thing and none of them wants a point:
///
///   6.3  a firing position on the enemy generator - somewhere with line of sight to it
///        inside weapon range, since the generator is shot from a distance and standing
///        on it was never the goal
///   5.2  advantageous ground - somewhere overlooking a point we already hold, rather
///        than standing on the point itself
///   2.2  pushing past a captured objective toward the enemy, rather than stopping on it
///   6.2  the Medic's follow position - near the ally, on the side away from the enemy
///
/// Expressed as a goal *predicate* those are one function with different arguments, and
/// building it once is the whole point: the alternative is three near-copies that drift.
///
/// losSense is one of BOT_LOS_ANY / BOT_LOS_NEED / BOT_LOS_AVOID, and it was a boolean
/// until the per-class goals needed the third value. AVOID asks for a node that *cannot*
/// see the anchor, which is the Spy's flank: near enough to the objective to walk in from,
/// out of sight of whoever is guarding it. It is the same line-of-sight test with the
/// answer inverted, so it costs the same and is bounded by the same BOT_SPOT_TRIES.
///
/// ⚠️ BOT_LOS_NEED is 1, so the old boolean call sites kept working unchanged - which is
/// exactly why they were all updated to name the constant instead. A future fourth sense
/// would not be so lucky.
///
/// The search is botFindTarget's shape rather than a scan: score every candidate cheaply,
/// then pay for the expensive test (line of sight) only on the best ones, best-first, and
/// stop at the first that passes. BOT_SPOT_TRIES bounds the collision_line calls whatever
/// the map looks like, so the worst case is a fixed cost rather than one per node. Called
/// on the objective cadence (every BOT_OBJECTIVE_PERIOD, staggered per bot), so at most a
/// couple of bots pay the O(nodes) scoring pass on any one frame.
///
/// Ranking, in world pixels so the terms are comparable:
///
///     rank = distance from me to the spot            walk less
///          + |distance to target - middle of band|   stand in the middle of the band,
///                                                    not on either edge of it
///          - highBonus * height above the target     high ground, when asked for
///
/// A negative rank is fine and is not clamped: ds_priority orders any reals, and clamping
/// at 1 the way botFindTarget does would collapse every high-ground candidate onto one
/// priority and throw away the ordering this is for. (botFindTarget clamps only so that a
/// printed threat reads sensibly; nothing depends on it.)
///
/// ⚠️ Reachability is deliberately NOT checked here. Answering it costs an A* per
/// candidate, and the caller is about to run exactly one A* anyway - so the caller
/// (botObjectiveUpdate) watches for a spot goal that never produces a path and falls back
/// to the plain objective point for a while instead. A goal that resolves is not a route
/// that exists, and this script only promises the first half.

var char, tx, ty, minDist, maxDist, losSense, highBonus;
var queue, n, ny, nx0, nx1, col, tcol, sx, sy, dTarget, rank, cand, tries, best, mid, wrong;

char = argument0;
tx = argument1;
ty = argument2;
minDist = argument3;
maxDist = argument4;
losSense = argument5;
highBonus = argument6;

// Publish the anchor itself as the fallback, so a caller that ignores the -1 return still
// gets a usable point rather than whatever the last call left behind.
global.botSpotX = tx;
global.botSpotY = ty;

if(!global.navReady)
    return -1;
if(maxDist <= minDist)
    return -1;

mid = (minDist + maxDist) / 2;
tcol = navAnchorCol(tx);
best = -1;
sx = tx;
sy = ty;

queue = ds_priority_create();
for(n = 0; n < global.navNodeCount; n += 1)
{
    ny = ds_grid_get(global.navNodes, NAV_NODE_Y, n);
    nx0 = ds_grid_get(global.navNodes, NAV_NODE_X0, n);
    nx1 = ds_grid_get(global.navNodes, NAV_NODE_X1, n);

    // Stand on whichever part of this run faces the target, not on its middle: a long
    // floor's midpoint can be well out of range while one of its ends is not, and
    // rejecting the whole run for that would lose most of the usable ground on a map.
    col = tcol;
    if(col < nx0)
        col = nx0;
    else if(col > nx1)
        col = nx1;

    // The character origin a bot standing on this node would have - chest height, feet
    // 23px lower (F24) - which is both what collision_line_bulletblocking wants and what
    // navNodeFromWorld will resolve back to this same node later.
    sx = navColWorldX(col);
    sy = (ny + NAV_BOX_H) * NAV_CELL_SIZE - 23;

    dTarget = point_distance(sx, sy, tx, ty);
    if(dTarget < minDist or dTarget > maxDist)
        continue;

    rank = point_distance(char.x, char.y, sx, sy)
         + abs(dTarget - mid)
         - highBonus * max(0, ty - sy);
    ds_priority_add(queue, n, rank);
}

tries = 0;
while(best < 0 and !ds_priority_empty(queue))
{
    cand = ds_priority_delete_min(queue);

    ny = ds_grid_get(global.navNodes, NAV_NODE_Y, cand);
    nx0 = ds_grid_get(global.navNodes, NAV_NODE_X0, cand);
    nx1 = ds_grid_get(global.navNodes, NAV_NODE_X1, cand);
    col = tcol;
    if(col < nx0)
        col = nx0;
    else if(col > nx1)
        col = nx1;
    sx = navColWorldX(col);
    sy = (ny + NAV_BOX_H) * NAV_CELL_SIZE - 23;

    if(losSense == BOT_LOS_ANY)
        best = cand;
    else
    {
        tries += 1;
        // `wrong` is "this candidate has the sightline the caller did not ask for", which
        // is a blocked line for NEED and a clear one for AVOID.
        wrong = collision_line_bulletblocking(sx, sy, tx, ty);
        if(losSense == BOT_LOS_AVOID)
            wrong = !wrong;
        if(!wrong)
            best = cand;
        else if(tries >= BOT_SPOT_TRIES)
            break;
    }
}

ds_priority_destroy(queue);

if(best >= 0)
{
    global.botSpotX = sx;
    global.botSpotY = sy;
}
return best;
