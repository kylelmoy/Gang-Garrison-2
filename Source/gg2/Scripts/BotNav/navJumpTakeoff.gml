/// navJumpTakeoff(freeGrid, nodeGrid, ay, ax0, ax1, by, bx0, bx1, dir, w, h, toNode)
/// Finds the cheapest takeoff column on the source surface from which a jump onto the
/// target surface is actually flyable, and returns it - or -1 if no takeoff works.
///
/// The takeoff used to be fixed at the end of the run facing the landing (ax1 going
/// right, ax0 going left), which is the natural choice and wrong often enough to matter.
/// A character is NAV_BOX_W cells wide and anchored at its left column, so standing at
/// the very end of a surface puts its body flush against whatever ends that surface. If
/// what ends it is the thing being jumped onto - a crate, a step, a ledge - then the
/// body is already inside the landing's column span at floor level, and the arc is
/// rejected on its first sample every time, no matter which column it aims at.
///
/// koth_valley is the case that found this. An 8x8 cell crate sits on the ground at
/// columns 206-213; the ground node ends at anchor 202 (body 202-205, flush against it)
/// and the crate's top is a node starting at anchor 203. From takeoff 202 every landing
/// column on that crate is blocked. From 200, 199 or 198 the very same jump is clean.
/// The bot could not leave its spawn valley, and 13 of 270 nodes were reachable.
///
/// ⚠️ Worth being precise about, because the previous investigation drew the opposite
/// conclusion and closed the case: varying the *landing* column does not help here and
/// never could. The arc is rejected while it is still next to the takeoff, so where it
/// was aiming is irrelevant - the earlier finding that "landing a couple of cells
/// further in still failed" was true, and led away from the real variable. The takeoff
/// is what has to move.
///
/// Offsets are tried from the end inward, so the first hit is also the cheapest: cost
/// grows with horizontal distance, and stepping back from the edge only ever adds
/// distance. NAV_JUMP_TAKEOFF_TRIES bounds it, and the source run's own width bounds it
/// again - a one-cell surface has exactly one takeoff whatever the constant says.
///
/// Returns the takeoff anchor column. The caller derives everything else from it, since
/// xLand, dCells, tHit and vx are all functions of the takeoff.

var freeGrid, nodeGrid, ay, ax0, ax1, by, bx0, bx1, dir, w, h, toNode;
var off, tries, takeoff, xLand, dCells, dWorld, tHit, vx;
var k, t, sx, sy, samples, blocked, prevSy, sweepY, onto, apex;

freeGrid = argument0;
nodeGrid = argument1;
ay = argument2;
ax0 = argument3;
ax1 = argument4;
by = argument5;
bx0 = argument6;
bx1 = argument7;
dir = argument8;
w = argument9;
h = argument10;
toNode = argument11;

// Once past the apex the character is coming down, and the first surface it comes down
// on is where the jump ends whatever the graph intended (F41).
apex = NAV_JUMP_V0 / NAV_JUMP_GRAVITY;

tries = min(NAV_JUMP_TAKEOFF_TRIES, ax1 - ax0 + 1);

for(off = 0; off < tries; off += 1)
{
    if(dir < 0)
        takeoff = ax0 + off;
    else
        takeoff = ax1 - off;

    if(dir < 0)
    {
        xLand = min(bx1, takeoff - 1);
        if(xLand < bx0)
            continue;
    }
    else
    {
        xLand = max(bx0, takeoff + 1);
        if(xLand > bx1)
            continue;
    }

    dCells = abs(xLand - takeoff);
    dWorld = dCells * NAV_CELL_SIZE;

    // The whole flight, not just the part up to arriving overhead. Mask y grows
    // downward, so a higher surface is a smaller row.
    tHit = navJumpFlight(ay, by, dCells);
    if(tHit < 0)
        continue;
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

        // Above the top of the walkmask is open sky, not a ceiling.
        if(sy >= 0)
        {
            if(ds_grid_get(freeGrid, sx, sy) != 1)
            {
                blocked = true;
                break;
            }

            // Clearance says the body fits here; it does not say the character is still
            // in the air. A cell that is some node's anchor has ground directly under
            // it, so on the way down that is where this jump ends - and if it is not
            // the surface being aimed at, the edge is a fiction. Swept, not sampled:
            // nodeGrid marks one row out of the mask and a descending arc covers most
            // of a row per tick (F41).
            if(t > apex and sy > prevSy)
            {
                for(sweepY = max(0, prevSy + 1); sweepY <= sy; sweepY += 1)
                {
                    onto = ds_grid_get(nodeGrid, sx, sweepY);
                    if(onto >= 0 and onto != toNode)
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

    if(!blocked)
        return takeoff;
}

return -1;
