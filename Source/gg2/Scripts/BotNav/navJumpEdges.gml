/// navJumpEdges(nodes, nodeCount, freeGrid, nodeGrid, rowStart, w, h, fromNode, toNode)
/// Appends jump edges for nodes fromNode .. toNode-1: leaping from the end of one
/// surface onto another that a walk or a fall cannot reach.
///
/// This is what makes the graph connected in both directions. Walk and fall edges
/// alone let a bot descend but never climb back, which on gg_debug left only 22 of 46
/// surfaces reachable from spawn.
///
/// The envelope is GG2's own jump, not a guess: baseJumpStrength 8.3 against gravity
/// 0.6 per tick (F12), giving height above takeoff p(t) = v0*t - g*t*t/2. A candidate
/// is accepted when the character, travelling horizontally at NAV_JUMP_VX, is still
/// at or above the landing surface by the time it arrives over it - so the arc is
/// checked against the real trajectory rather than against a bounding box.
///
/// NAV_JUMP_VX is Heavy's max speed, the slowest class (F12). One graph serves every
/// class, so every edge in it has to be traversable by the worst of them; a Scout can
/// clear roughly twice these gaps and simply does not get credit for it yet. That is
/// the same conservative choice NAV_BOX_W/H already make by sizing to Heavy's body.
/// The takeoff speed bucket is recorded on the edge so a per-class relaxation can be
/// added later without regenerating anything else.
///
/// Clearance is sampled along the arc rather than simulated tick by tick. That is the
/// deliberate v1 approximation: it catches jumps into ceilings and through walls,
/// while genuinely exact arcs are the trajectory-fan work (F35).
///
/// Takes a node range so the build can spread it across frames.

var nodes, nodeCount, freeGrid, nodeGrid, rowStart, w, h, fromNode, toNode;
var i, j, side, dir, ay, ax0, ax1, by, bx0, bx1, takeoff, xLand;
var dCells, dWorld, tHit, peak, riseWorld, cost, k, t, sx, sy, blocked, minRow, maxRow, ry, queue, kept;

nodes = argument0;
nodeCount = argument1;
freeGrid = argument2;
nodeGrid = argument3;
rowStart = argument4;
w = argument5;
h = argument6;
fromNode = argument7;
toNode = argument8;

for(i = fromNode; i < toNode; i += 1)
{
    ay = ds_grid_get(nodes, NAV_NODE_Y, i);
    ax0 = ds_grid_get(nodes, NAV_NODE_X0, i);
    ax1 = ds_grid_get(nodes, NAV_NODE_X1, i);

    // Apex is about 9.6 cells, so nothing above that is ever reachable; below, the
    // fall cap bounds how far a jump can usefully carry.
    minRow = max(0, ay - 10);
    maxRow = min(h - NAV_BOX_H, ay + NAV_MAX_FALL);

    for(side = 0; side < 2; side += 1)
    {
    if(side == 0)
    {
        dir = -1;
        takeoff = ax0;
    }
    else
    {
        dir = 1;
        takeoff = ax1;
    }

    queue = ds_priority_create();

    for(ry = minRow; ry <= maxRow; ry += 1)
    {
        j = ds_grid_get(rowStart, 0, ry);
        if(j < 0)
            continue;

        while(j < nodeCount and ds_grid_get(nodes, NAV_NODE_Y, j) == ry)
        {
            if(j == i)
            {
                j += 1;
                continue;
            }

            by = ry;
            bx0 = ds_grid_get(nodes, NAV_NODE_X0, j);
            bx1 = ds_grid_get(nodes, NAV_NODE_X1, j);

            // A step a walk edge already covers needs no jump. Skipping these is the
            // main defence against the redundant-link explosion this technique is
            // known for (F35).
            if(abs(by - ay) <= 1 and bx0 <= ax1 + 1 and ax0 <= bx1 + 1)
            {
                j += 1;
                continue;
            }

            {
                if(dir < 0)
                {
                    xLand = min(bx1, takeoff - 1);
                    if(xLand < bx0)
                    {
                        j += 1;
                        continue;
                    }
                }
                else
                {
                    xLand = max(bx0, takeoff + 1);
                    if(xLand > bx1)
                    {
                        j += 1;
                        continue;
                    }
                }

                dCells = abs(xLand - takeoff);
                dWorld = dCells * NAV_CELL_SIZE;
                tHit = dWorld / NAV_JUMP_VX;
                if(tHit > NAV_JUMP_MAX_TICKS)
                {
                    j += 1;
                    continue;
                }

                // Height above takeoff when the jump arrives over the landing point,
                // against the height it has to make up. Mask y grows downward, so a
                // higher surface is a smaller row.
                peak = NAV_JUMP_V0 * tHit - NAV_JUMP_GRAVITY * tHit * tHit / 2;
                riseWorld = (ay - by) * NAV_CELL_SIZE;
                if(peak < riseWorld)
                {
                    j += 1;
                    continue;
                }

                blocked = false;
                for(k = 1; k <= NAV_JUMP_SAMPLES; k += 1)
                {
                    t = tHit * k / NAV_JUMP_SAMPLES;
                    sx = round(takeoff + dir * (NAV_JUMP_VX * t) / NAV_CELL_SIZE);
                    sy = round(ay - (NAV_JUMP_V0 * t - NAV_JUMP_GRAVITY * t * t / 2) / NAV_CELL_SIZE);

                    // Off the side of the map, or below its bottom, is a dead end.
                    if(sx < 0 or sx > w - NAV_BOX_W or sy > h - NAV_BOX_H)
                    {
                        blocked = true;
                        break;
                    }

                    // Above the top of the walkmask is open sky, not a ceiling. The
                    // mask is the only collision geometry there is, so a row above it
                    // cannot block anything - and rejecting these silently threw away
                    // every jump taken from a surface within an apex of the top edge,
                    // which is about 9.6 cells.
                    if(sy >= 0)
                    {
                        if(ds_grid_get(freeGrid, sx, sy) != 1)
                        {
                            blocked = true;
                            break;
                        }
                    }
                }
                if(blocked)
                {
                    j += 1;
                    continue;
                }

                // Jumping is more expensive than walking the same ground, so a route
                // that can walk will.
                cost = max(1, dCells) + NAV_JUMP_PENALTY;
                ds_priority_add(queue, j, cost);
            }

            j += 1;
        }
    }

    // Keep only the cheapest few landings per direction. Emitting every surface the
    // envelope admits is what makes this technique notorious for redundant links
    // (F35): a far platform is almost always reachable by landing on a nearer one and
    // going again, so the extra edges buy nothing and cost build time, memory and A*
    // expansion for every query afterwards.
    kept = 0;
    while(kept < NAV_JUMP_MAX_PER_SIDE and !ds_priority_empty(queue))
    {
        j = ds_priority_delete_min(queue);
        by = ds_grid_get(nodes, NAV_NODE_Y, j);
        bx0 = ds_grid_get(nodes, NAV_NODE_X0, j);
        bx1 = ds_grid_get(nodes, NAV_NODE_X1, j);
        if(dir < 0)
            xLand = min(bx1, takeoff - 1);
        else
            xLand = max(bx0, takeoff + 1);
        dCells = abs(xLand - takeoff);
        tHit = (dCells * NAV_CELL_SIZE) / NAV_JUMP_VX;
        cost = max(1, dCells) + NAV_JUMP_PENALTY;
        navEdgeAdd(i, j, NAV_EDGE_JUMP, round(NAV_JUMP_VX), round(tHit), cost);
        kept += 1;
    }
    ds_priority_destroy(queue);
    }
}
