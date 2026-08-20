/// navJumpEdges(nodes, nodeCount, freeGrid, nodeGrid, gateGrid, rowStart, w, h, fromNode, toNode)
/// Appends jump edges for nodes fromNode .. toNode-1: leaping from the end of one
/// surface onto another that a walk or a fall cannot reach.
///
/// This is what makes the graph connected in both directions. Walk and fall edges
/// alone let a bot descend but never climb back, which on gg_debug left only 22 of 46
/// surfaces reachable from spawn.
///
/// The envelope is GG2's own jump, not a guess: baseJumpStrength 8.3 against gravity
/// 0.6 per tick (F12), giving height above takeoff p(t) = v0*t - g*t*t/2. How long
/// that arc lasts, and how fast it is flown, comes from navJumpFlight - which is where
/// the difference between jumping up onto something and dropping down onto something
/// lives, and it is not cosmetic. Checking a downward landing the upward way accepts
/// every surface within horizontal reach and NAV_MAX_FALL rows below regardless of
/// what is in between, because "arrives over it while at or above it" is true on the
/// first tick of the arc (F41).
///
/// NAV_JUMP_VX is Heavy's max speed, the slowest class (F12). One graph serves every
/// class, so every edge in it has to be traversable by the worst of them; a Scout can
/// clear roughly twice these gaps and simply does not get credit for it yet. That is
/// the same conservative choice NAV_BOX_W/H already make by sizing to Heavy's body.
/// The takeoff speed bucket is recorded on the edge so a per-class relaxation can be
/// added later without regenerating anything else.
///
/// Clearance is sampled along the arc at one sample per tick, never fewer than
/// NAV_JUMP_SAMPLES. A tick moves the character at most 4.53px sideways and 8.3px
/// down, both under two cells, so nothing thin gets tunnelled through; a fixed ten
/// samples would have put six ticks between them on the long descents this now
/// simulates. It is still sampling and not a real step-by-step simulation - genuinely
/// exact arcs are the trajectory-fan work (F35) - but it catches jumps into ceilings,
/// through walls, and onto surfaces that a nearer one shadows.
///
/// gateGrid may be -1. When it is not, the arc of each edge that survives is sampled
/// against it and the first gate crossed becomes the edge's gate code. This is the one
/// place gates genuinely have to be arc-sampled rather than read off a node: a spawn
/// gate stands in a doorway on a flat floor, its own clearance is open, and both
/// halves of that floor are separate nodes - so without this every gate in the game
/// would have a pair of jump edges hopping straight over it, which is precisely the
/// gap already documented for one-way doors and deliberately accepted there because a
/// door is only ever a two-cell nuisance.
///
/// Takes a node range so the build can spread it across frames.

var nodes, nodeCount, freeGrid, nodeGrid, gateGrid, rowStart, w, h, fromNode, toNode;
var i, j, side, dir, ay, ax0, ax1, by, bx0, bx1, takeoff, xLand;
var dCells, dWorld, tHit, vx, samples, cost, k, t, sx, sy, blocked, minRow, maxRow, ry, queue, kept;
var srcGate, arcGate, cellGate, apex, onto, prevSy, sweepY;

// Once past the apex the character is coming down, and the first surface it comes
// down on is where the jump ends whatever the graph intended.
apex = NAV_JUMP_V0 / NAV_JUMP_GRAVITY;

nodes = argument0;
nodeCount = argument1;
freeGrid = argument2;
nodeGrid = argument3;
gateGrid = argument4;
rowStart = argument5;
w = argument6;
h = argument7;
fromNode = argument8;
toNode = argument9;

for(i = fromNode; i < toNode; i += 1)
{
    ay = ds_grid_get(nodes, NAV_NODE_Y, i);
    ax0 = ds_grid_get(nodes, NAV_NODE_X0, i);
    ax1 = ds_grid_get(nodes, NAV_NODE_X1, i);
    srcGate = ds_grid_get(nodes, NAV_NODE_GATE, i);

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

                // The whole flight, not just the part up to arriving overhead. Mask y
                // grows downward, so a higher surface is a smaller row.
                tHit = navJumpFlight(ay, by, dCells);
                if(tHit < 0)
                {
                    j += 1;
                    continue;
                }
                vx = dWorld / tHit;

                blocked = false;
                prevSy = ay;
                samples = max(NAV_JUMP_SAMPLES, ceil(tHit));
                for(k = 1; k <= samples; k += 1)
                {
                    t = tHit * k / samples;
                    sx = round(takeoff + dir * (vx * t) / NAV_CELL_SIZE);
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

                        // Clearance says the body fits here; it does not say the
                        // character is still in the air. A cell that is some node's
                        // anchor has ground directly under it, so on the way down
                        // that is where this jump ends - and if it is not the surface
                        // being aimed at, the edge is a fiction. This is what stops a
                        // hop off a ledge being credited with the floor sixteen rows
                        // below when there is a walkable ledge one column over (F41).
                        //
                        // Swept, not sampled. nodeGrid marks a node's anchor row and
                        // nothing else, one row out of the mask, while a descending
                        // arc covers most of a row per tick and rounds to whichever
                        // is nearest - so a point test walks straight past the row it
                        // was meant to catch. gg_debug's node 29 -> 44 went from
                        // +3.2px above its row on one tick to -5.0px below it on the
                        // next, and the platform in between was never looked at.
                        if(t > apex and sy > prevSy)
                        {
                            for(sweepY = max(0, prevSy + 1); sweepY <= sy; sweepY += 1)
                            {
                                onto = ds_grid_get(nodeGrid, sx, sweepY);
                                if(onto >= 0 and onto != j)
                                {
                                    blocked = true;
                                    break;
                                }
                            }
                            if(blocked)
                                break;
                        }
                    }

                    prevSy = sy;
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
        dWorld = dCells * NAV_CELL_SIZE;
        tHit = navJumpFlight(ay, by, dCells);
        vx = dWorld / tHit;
        cost = max(1, dCells) + NAV_JUMP_PENALTY;

        // Re-walk the arc for gates only now, rather than in the candidate loop: the
        // fan considers every surface in the envelope and keeps three, so sampling
        // here is a fraction of the work for the same answer.
        arcGate = NAV_GATE_NONE;
        if(gateGrid >= 0)
        {
            samples = max(NAV_JUMP_SAMPLES, ceil(tHit));
            for(k = 1; k <= samples; k += 1)
            {
                if(arcGate != NAV_GATE_NONE)
                    break;

                t = tHit * k / samples;
                sx = round(takeoff + dir * (vx * t) / NAV_CELL_SIZE);
                sy = round(ay - (NAV_JUMP_V0 * t - NAV_JUMP_GRAVITY * t * t / 2) / NAV_CELL_SIZE);
                if(sx < 0 or sx > w - NAV_BOX_W or sy < 0 or sy > h - NAV_BOX_H)
                    continue;

                cellGate = ds_grid_get(gateGrid, sx, sy);
                if(cellGate != NAV_GATE_NONE and cellGate != srcGate)
                    arcGate = cellGate;
            }
        }
        if(arcGate == NAV_GATE_NONE)
            arcGate = ds_grid_get(nodes, NAV_NODE_GATE, j);

        // The bucket is the horizontal speed this arc actually needs, which is
        // NAV_JUMP_VX for a jump up or across and slower for a drop. A per-class
        // relaxation later wants the requirement, not the cap.
        navEdgeAdd(i, j, NAV_EDGE_JUMP, round(vx), round(tHit), cost, arcGate);
        kept += 1;
    }
    ds_priority_destroy(queue);
    }
}
