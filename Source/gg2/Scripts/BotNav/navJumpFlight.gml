/// navJumpFlight(ay, by, dCells)
/// How long, in ticks, a jump from anchor row ay to anchor row by is in the air while
/// covering dCells anchor columns - or -1 if GG2's jump cannot do it at all.
///
/// This exists because "how long is the jump" has two different answers depending on
/// which way it goes, and getting that wrong silently fills the graph with edges no
/// bot can traverse.
///
///   Landing level or above (by <= ay): the jump ends when the character first arrives
///   over the landing column, because it is at or above that surface by then and drops
///   onto it. Time is set by the horizontal distance at full speed, and the arc has to
///   still be high enough to make the rise.
///
///   Landing below (by > ay): arriving over the landing column proves nothing - from a
///   ledge, every surface below is "arrived over" within a tick or two while the
///   character is still tens of pixels up in the air. The jump ends when the arc falls
///   back down to the landing row, which is a much longer flight, and the horizontal
///   distance is then a *constraint* rather than the thing that sets the time: the
///   character must be able to cover it in the time it takes to fall, so the required
///   speed has to be within what the class can run at.
///
/// Callers get the speed actually flown back out of this as dCells*NAV_CELL_SIZE/t,
/// which is NAV_JUMP_VX exactly in the first case and something slower in the second.
/// Sampling the arc at NAV_JUMP_VX regardless is what produced jump edges from a ledge
/// to a surface sixteen rows below with another surface in between (F41).

var ay, by, dCells, riseWorld, dWorld, t, peak, disc;

ay = argument0;
by = argument1;
dCells = argument2;

riseWorld = (ay - by) * NAV_CELL_SIZE;
dWorld = dCells * NAV_CELL_SIZE;

if(by > ay)
{
    // Positive root of v0*t - g*t*t/2 = riseWorld with riseWorld negative, so the
    // discriminant is always larger than v0*v0 and the root always real.
    disc = NAV_JUMP_V0 * NAV_JUMP_V0 - 2 * NAV_JUMP_GRAVITY * riseWorld;
    t = (NAV_JUMP_V0 + sqrt(disc)) / NAV_JUMP_GRAVITY;

    // Too far sideways to cross before gravity puts the character on the floor.
    if(dWorld > NAV_JUMP_VX * t)
        return -1;
}
else
{
    t = dWorld / NAV_JUMP_VX;

    // Height above takeoff on arrival, against the height that has to be made up.
    peak = NAV_JUMP_V0 * t - NAV_JUMP_GRAVITY * t * t / 2;
    if(peak < riseWorld)
        return -1;
}

if(t > NAV_JUMP_MAX_TICKS)
    return -1;

return t;
