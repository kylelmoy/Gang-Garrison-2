/// navJumpEdges(nodes, nodeCount, freeGrid, nodeGrid, gateGrid, rowStart, w, h, fromNode, toNode)
/// Appends jump edges for nodes fromNode .. toNode-1: leaping from the end of one
/// surface onto another that a walk or a fall cannot reach.
///
/// This is what makes the graph connected in both directions. Walk and fall edges
/// alone let a bot descend but never climb back, which on gg_debug left only 22 of 46
/// surfaces reachable from spawn.
///
/// The envelope is GG2's own jump, not a guess: baseJumpStrength 8.3 against gravity
/// 0.6 per tick (F12), giving height above takeoff navJumpHeight(t). How long that arc
/// lasts, and how fast it is flown, comes from navJumpFlight, and the one rule behind
/// both is that a jump ends where the arc comes back down - never where it first
/// arrives over the target (that is true on the first tick of a drop) and never where
/// it first arrives level with the target (that is true seventeen ticks before a steep
/// climb lands). Both of those are F41, and the second of them was still here until
/// the flight model was made one formula.
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
/// Where the arc *starts*, where on the target it aims, and how much climb the ceiling
/// above the takeoff leaves it are all decided by navJumpTakeoff, which owns the search
/// and the clearance walk together and hands the whole arc back through globals. This
/// script does not re-derive any of it: two copies of that reasoning would agree by luck
/// rather than by construction, and an edge whose recorded speed and duration describe a
/// different arc from the one that was proven is F41's failure class exactly.
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
var dCells, tHit, vx, samples, cost, k, t, sx, sy, minRow, maxRow, ry, queue, kept;
var srcGate, arcGate, cellGate;
var keptRows, bonusUsed, far, ki, krow;

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
        dir = -1;
    else
        dir = 1;

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
                // Which column to leave from is a search, not a given - see
                // navJumpTakeoff. It returns -1 when no takeoff on this surface can
                // fly the jump at all.
                takeoff = navJumpTakeoff(freeGrid, nodeGrid, ay, ax0, ax1,
                                         by, bx0, bx1, dir, w, h, j);
                if(takeoff < 0)
                {
                    j += 1;
                    continue;
                }

                dCells = abs(global.navJumpLandCol - takeoff);

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
    //
    // ⚠️ "Cheapest few" is blind to what a landing actually connects to, and that is
    // its own failure mode - found on `ctf_conflict`/`ctf_avanti` (M7 tier 2) and
    // again, worse, on `ctf_truefort`: a node standing at the top of one long
    // staircase has many cheap candidates landing one step further down that same
    // staircase, all mutually redundant with each other, and they fill the whole
    // quota before a genuinely different, structurally load-bearing candidate is ever
    // considered - on `ctf_truefort` the missing edge ranked 7th cheapest, well
    // outside any quota this project would want to raise blindly (see the method note
    // in the M7 plan on why a global bump is the wrong lever once the rank gets that
    // deep). What every one of those redundant candidates has in common is landing
    // close to the *other kept candidates'* own row, not close to the source's - they
    // are one staircase, seen from its top. So one extra slot is kept back for
    // whatever is cheapest among the leftovers whose row is not close to anything
    // already kept: at most one more edge per source per direction, same bounded cost
    // as the M7 tier-2 constant bump, but aimed at the actual failure instead of
    // raising a global cap and hoping the next map's rank is shallow enough to catch.
    kept = 0;
    bonusUsed = false;
    keptRows = ds_list_create();
    while(!ds_priority_empty(queue) and (kept < NAV_JUMP_MAX_PER_SIDE or !bonusUsed))
    {
        j = ds_priority_delete_min(queue);
        by = ds_grid_get(nodes, NAV_NODE_Y, j);
        bx0 = ds_grid_get(nodes, NAV_NODE_X0, j);
        bx1 = ds_grid_get(nodes, NAV_NODE_X1, j);

        // Past the normal quota, only a landing that reaches somewhere none of the
        // kept edges already did is worth the one bonus slot.
        if(kept >= NAV_JUMP_MAX_PER_SIDE)
        {
            far = true;
            for(ki = 0; ki < ds_list_size(keptRows) and far; ki += 1)
            {
                krow = ds_list_find_value(keptRows, ki);
                if(abs(by - krow) <= NAV_JUMP_DIVERSITY_ROWS)
                    far = false;
            }
            if(!far)
                continue;
        }

        // Re-derive the winning takeoff rather than carrying it out of the candidate
        // loop: a ds_priority holds a value and a priority and nothing else, and this
        // runs at most NAV_JUMP_MAX_PER_SIDE+1 times per side against a candidate loop
        // that considered every surface in the envelope. Cheap, and it keeps one
        // definition of what a flyable arc is.
        takeoff = navJumpTakeoff(freeGrid, nodeGrid, ay, ax0, ax1,
                                 by, bx0, bx1, dir, w, h, j);
        if(takeoff < 0)
            continue;

        // The whole arc comes back with the takeoff, not from a second derivation of
        // this script's own. Which lead it could afford and how much climb the ceiling
        // left it are both things only the clearance walk knows, and re-deriving them
        // here would mean two copies of that reasoning agreeing by luck.
        xLand = global.navJumpLandCol;
        dCells = abs(xLand - takeoff);
        tHit = global.navJumpTicks;
        vx = global.navJumpVx;
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
                sy = round(ay - navJumpHeight(t, global.navJumpCapH) / NAV_CELL_SIZE);
                if(sx < 0 or sx > w - NAV_BOX_W or sy < 0 or sy > h - NAV_BOX_H)
                    continue;

                cellGate = ds_grid_get(gateGrid, sx, sy);
                if(cellGate != NAV_GATE_NONE and cellGate != srcGate)
                    arcGate = cellGate;
            }
        }
        if(arcGate == NAV_GATE_NONE)
            arcGate = ds_grid_get(nodes, NAV_NODE_GATE, j);

        // The bucket is the horizontal speed this arc needs and the ticks are how long
        // it is in the air, and both go in **unrounded**. They are what the follower
        // steers by - the planned position at tick n is takeoff + vx*n, and the arc
        // ends at vx*ticks - so rounding them is not a tidy-up, it is throwing away
        // the trajectory. A slow climb wants 0.54px/tick; round() calls that 1, an
        // 85% error, which over a 22-tick flight is two cells past an 18px ledge.
        navEdgeAdd(i, j, NAV_EDGE_JUMP, vx, tHit, cost, arcGate, takeoff);
        ds_list_add(keptRows, by);
        if(kept < NAV_JUMP_MAX_PER_SIDE)
            kept += 1;
        else
            bonusUsed = true;
    }
    ds_list_destroy(keptRows);
    ds_priority_destroy(queue);
    }
}
