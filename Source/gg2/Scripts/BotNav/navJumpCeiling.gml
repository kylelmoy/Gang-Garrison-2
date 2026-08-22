/// navJumpCeiling(freeGrid, col, ay, dir, colLimit, needRise)
/// How high, in world px, a character standing at anchor (col, ay) and jumping `dir`
/// toward a surface whose far edge is `colLimit` can rise before the map stops it - the
/// apex when nothing is above, less when something is. `needRise` is how much climb the
/// jump being considered actually wants, in px, and is what keeps the corridor below
/// from perturbing jumps that never needed it.
///
/// This exists because refusing a jump on the grounds that the character would bump its
/// head is wrong, and expensively so. GG2's jump is a fixed impulse that rises 57px
/// whether the room has 57px of headroom or not; hitting a ceiling zeroes vspeed and
/// the character comes down early, which is a perfectly ordinary jump and lands exactly
/// where a shorter arc lands. Treating the bump as "this jump is impossible" throws away
/// every climb under an overhang.
///
/// It was the second half of koth_valley's valley floor. The step up out of it is a
/// plateau six rows above the ground, and eight rows above *that* is an overhang; the
/// arc's clearance sample fails at the top of the rise, so the step had no edge, so a
/// bot standing on the valley floor had nowhere to go at all - 264 was a node with
/// incoming falls and not one outgoing anything. The jump is trivially makeable in the
/// game: walk up to the step, jump, clip your head, land on the step.
///
/// ⚠️ The scan is a CORRIDOR, not a column, and the difference is a whole class of
/// climb. This used to read straight up from the takeoff column on the grounds that "the
/// character spends the whole rise over or beside its takeoff", which is true of a
/// vertical hop and false of any jump that travels while it climbs. koth_valley's
/// control point shafts are the case that proves it: the free channel between the crate
/// at the bottom and the ledge above it sits at columns 367-370, then jogs three columns
/// left to 364-367 at the ledge's own row. Reading straight up from the only standable
/// takeoff (369) hits that shoulder nine rows up and reports 48px of headroom, against
/// the 54px the rung needs - so navJumpLanding refused every arc, no edge was ever
/// costed, and the shaft was a one-way drop a bot could fall into and never climb out
/// of. A human makes the jump comfortably, drifting out from under the shoulder as it
/// rises: measured takeoff (2232.66, 768.40), landing (2198.60, 714.46), a 53.9px rise
/// inside a 57.6px apex.
///
/// So a row counts as open when ANY column the arc could be in by then is open, and the
/// arc is allowed one anchor column of drift per row. That bound is deliberately the
/// conservative end of the real thing - near the takeoff a character crosses a 6px row
/// in about a tick and can move NAV_JUMP_VX (4.53px) sideways in it, and near the apex
/// it spends many ticks in one row and drifts several columns - but a bound that
/// under-states drift only ever refuses climbs, which is the failure this script exists
/// to stop making, and never invents one.
///
/// Being permissive here is safe because it is not the last word. The cap only decides
/// how much rise navJumpFlight may assume; the arc that comes out of it is then walked
/// against the real geometry by navJumpTakeoff's own clearance sweep, which samples the
/// actual trajectory column by column. A cap that says "you may rise" and a trajectory
/// that in fact clips something is caught there. The cap saying "you may not" was final,
/// which is why the error was invisible.
///
/// The corridor is bounded twice over - by one column per row, and by colLimit, the far
/// edge of the surface being aimed at, since an arc that drifts past its own landing is
/// not a climb onto it. Worst case is maxRows columns wide, so about a hundred reads
/// where the column scan took ten.
///
/// ⚠️ And it is bounded a third time, by `needRise`, which is the part that took a
/// regression to learn. The corridor is only consulted when the straight-up scan does
/// NOT already give the jump the climb it asked for. Widening it unconditionally looks
/// harmless - it can only ever report MORE headroom - but capHeight is an input to which
/// arcs get costed at all, and NAV_JUMP_MAX_PER_SIDE then keeps a fixed number of them
/// per node per side. More candidates therefore means a DIFFERENT set kept, not a
/// superset: ctf_orange lost 117 jump edges that way and with them the only ungated
/// route into the enemy intel, which navaudit reported as a 106-node pocket behind a
/// blueteam gate. Gating on needRise makes the change surgical - every jump the strict
/// scan already allowed keeps its exact capHeight, so its arc, its cost and its place in
/// the pruning order are all untouched, and only jumps that were being refused outright
/// can appear. Descents never reach the corridor at all, since needRise is <= 0 for
/// them.

/// ⚠️ Every clearance read here is an AIRBORNE one, and airborne is a row taller than
/// standing. freeGrid is dilated by NAV_BOX_H = 6 cells, which is exactly the 36px body
/// GG2 rests on a surface - row-aligned, six rows. A body in flight is at an arbitrary y
/// and therefore touches SEVEN rows, so "the box fits at row r" is tested as r and r - 1
/// both being clear. Above the top of the mask is sky and counts as clear.
///
/// This is not belt-and-braces, it is the difference between an arc that flies and one
/// that does not: measured, dropping it let a 6-row test pass arcs through koth_valley's
/// shaft that the follower could not hold, and the bot slid off the two-column ledge it
/// had just landed on and had to climb again (707 ticks against a 113-tick baseline).

var freeGrid, col, ay, dir, colLimit, needRise;
var apexHeight, maxRows, r, c, lo, hi, capHeight, open, gw;

freeGrid = argument0;
col = argument1;
ay = argument2;
dir = argument3;
colLimit = argument4;
needRise = argument5;

apexHeight = NAV_JUMP_V0 * NAV_JUMP_V0 / (2 * NAV_JUMP_GRAVITY);
maxRows = ceil(apexHeight / NAV_CELL_SIZE);
capHeight = apexHeight;
gw = ds_grid_width(freeGrid);

// Pass one: straight up from the takeoff column, which is what this script did for
// its whole life and is still the right answer almost everywhere.
for(r = 1; r <= maxRows; r += 1)
{
    // Above the top of the walkmask is open sky, not a ceiling.
    if(ay - r < 0)
        break;

    // Airborne: seven rows, so this row and the one above it.
    open = (ds_grid_get(freeGrid, col, ay - r) == 1);
    if(open and ay - r - 1 >= 0)
        open = (ds_grid_get(freeGrid, col, ay - r - 1) == 1);
    if(!open)
    {
        capHeight = (r - 1) * NAV_CELL_SIZE;
        break;
    }
}

// That answer stands unless it is the thing refusing the jump. Anything this jump can
// already afford is left exactly as it was - see the warning above about what happens
// to the pruning order otherwise.
if(capHeight >= needRise)
    return capHeight;

// Pass two: the same scan over the corridor the arc could actually be in, one anchor
// column of drift per row toward the target.
capHeight = apexHeight;
for(r = 1; r <= maxRows; r += 1)
{
    if(ay - r < 0)
        break;

    if(dir < 0)
    {
        lo = max(col - r, colLimit);
        hi = col;
    }
    else
    {
        lo = col;
        hi = min(col + r, colLimit);
    }

    lo = max(0, lo);
    hi = min(gw - 1, hi);

    open = false;
    for(c = lo; c <= hi and !open; c += 1)
        if(ds_grid_get(freeGrid, c, ay - r) == 1)
        {
            if(ay - r - 1 < 0)
                open = true;
            else if(ds_grid_get(freeGrid, c, ay - r - 1) == 1)
                open = true;
        }

    if(!open)
    {
        capHeight = (r - 1) * NAV_CELL_SIZE;
        break;
    }
}

return capHeight;
