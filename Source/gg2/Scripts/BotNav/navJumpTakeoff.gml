/// navJumpTakeoff(freeGrid, nodeGrid, ay, ax0, ax1, by, bx0, bx1, dir, w, h, toNode)
/// Finds the cheapest takeoff column on the source surface from which a jump onto the
/// target surface is actually flyable, and returns it - or -1 if no takeoff works.
///
/// The takeoff used to be fixed at the end of the run facing the landing (ax1 going
/// right, ax0 going left), which is the natural choice and not always a possible one.
/// What makes a takeoff unusable is almost never the landing - it is what is *above* the
/// takeoff. Every jump in GG2 rises until something stops it, so a low ceiling over the
/// end of a run shortens every arc that starts there, and one low enough leaves no arc
/// that reaches the target at all. Two cells further along there is headroom and the
/// identical jump is clean. Nothing about aiming elsewhere can fix that, which is what
/// makes this a search over takeoffs rather than over landings.
///
/// ⚠️ **This script was written for a different reason, and that reason has since been
/// fixed elsewhere.** It was added because a character standing flush against a crate -
/// body NAV_BOX_W wide, anchored at its left column, so already inside the crate's
/// columns at floor level - could not jump onto it from there, and could from a few
/// cells back. That was true of the arcs the generator could then describe, all of which
/// were far too fast, and it is not true of GG2: walking up to a crate and hopping onto
/// it is an ordinary thing a player does, and once navJumpFlight stopped timing a climb
/// by when it first drew level with the target, the slow arc that does it exists and the
/// run's end flies it. Stepping back from a crate is in fact counter-productive - the
/// same landing from further away is a faster arc, and faster is what fails. The search
/// still earns its place on the ceiling case above; the crate case no longer needs it.
///
/// Offsets are tried from the end inward, so the first hit is also the cheapest: cost
/// grows with horizontal distance, and stepping back from the edge only ever adds
/// distance. NAV_JUMP_TAKEOFF_TRIES bounds it, and the source run's own width bounds it
/// again - a one-cell surface has exactly one takeoff whatever the constant says.
///
/// The arc walked here is the *whole* flight, apex included, down to where it comes
/// back through the landing row - not the truncated one a climbing jump used to get.
/// That is what puts the descending nodeGrid sweep below to work on jumps that go up
/// as well as jumps that go down: a climb that comes down on some other surface first
/// is a fiction in exactly the way F41 describes, and until navJumpFlight was fixed
/// this loop never simulated far enough to notice.
///
/// Returns the takeoff anchor column, and publishes the rest of the arc it proved in
/// global.navJumpLandCol / navJumpTicks / navJumpVx / navJumpCapH - which column it aims
/// at, how long it is in the air, how fast it crosses, and how much climb the ceiling
/// left it. Those are return values, not state: read them straight after the call, since
/// the next one overwrites them. They are published rather than re-derived because the
/// lead and the cap are decisions this search makes against real geometry, and a caller
/// working them out again would be a second copy of that reasoning agreeing by luck.

var freeGrid, nodeGrid, ay, ax0, ax1, by, bx0, bx1, dir, w, h, toNode;
var off, tries, takeoff, xLand, dCells, dWorld, tHit, vx, lead, capHeight;
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

tries = min(NAV_JUMP_TAKEOFF_TRIES, ax1 - ax0 + 1);

for(off = 0; off < tries; off += 1)
{
    if(dir < 0)
        takeoff = ax0 + off;
    else
        takeoff = ax1 - off;

    // How much climb this takeoff actually has, which is not always the apex - and
    // when it is not, the arc is shorter, faster and still perfectly flyable.
    capHeight = navJumpCeiling(freeGrid, takeoff, ay);

    // Once the rise ends the character is coming down, and the first surface it comes
    // down on is where the jump ends whatever the graph intended (F41). Under a ceiling
    // that moment arrives early, so this is not the apex constant it used to be.
    apex = (NAV_JUMP_V0 - sqrt(max(0, NAV_JUMP_V0 * NAV_JUMP_V0
                                     - 2 * NAV_JUMP_GRAVITY * capHeight)))
           / NAV_JUMP_GRAVITY;

    for(lead = NAV_JUMP_LAND_LEAD; lead >= 0; lead -= 1)
    {
    // Where on the target to aim is its own decision, with its own reasons - see
    // navJumpLanding. The lead is tried from the largest down because landing well
    // inside a surface is worth having, and it has to be able to lose: a bigger lead
    // is a longer arc over the same fixed airtime, so it is a faster one, and a faster
    // arc is already moving sideways while it is still level with the thing it is
    // climbing onto. koth_valley's step out of the valley floor is the case that
    // proves it - the plateau's own side wall is what the arc hits, and only the
    // slowest arc onto it (half a pixel a tick) rises clear before it drifts across.
    // Trying the leads against the geometry rather than only against reach is the
    // difference between that step existing in the graph and the bot being trapped on
    // the floor below it.
    xLand = navJumpLanding(ay, by, takeoff, bx0, bx1, dir, lead, capHeight);
    if(xLand < 0)
        continue;

    dCells = abs(xLand - takeoff);
    dWorld = dCells * NAV_CELL_SIZE;

    // The whole flight, to where the arc comes back down - not to where it first
    // arrives level with the target. Mask y grows downward, so a higher surface is a
    // smaller row.
    tHit = navJumpFlight(ay, by, dCells, capHeight);
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
        sy = round(ay - navJumpHeight(t, capHeight) / NAV_CELL_SIZE);

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
    {
        // The chosen landing column is a second return value, and there is nowhere else
        // to put it: navJumpEdges needs the exact column this arc was proven against,
        // and re-deriving it there would mean repeating the same lead search and hoping
        // the two agree. Read it immediately - the next call overwrites it.
        global.navJumpLandCol = xLand;
        global.navJumpTicks = tHit;
        global.navJumpVx = vx;
        global.navJumpCapH = capHeight;
        return takeoff;
    }
    }
}

global.navJumpLandCol = -1;
global.navJumpTicks = -1;
global.navJumpVx = 0;
global.navJumpCapH = 0;
return -1;
