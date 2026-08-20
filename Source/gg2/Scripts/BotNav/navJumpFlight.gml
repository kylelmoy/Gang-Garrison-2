/// navJumpFlight(ay, by, dCells)
/// How long, in ticks, a jump from anchor row ay to anchor row by is in the air while
/// covering dCells anchor columns - or -1 if GG2's jump cannot do it at all.
///
/// This exists because "how long is the jump" has two different answers depending on
/// which way it goes, and getting that wrong silently fills the graph with edges no
/// bot can traverse, or - the bug this version fixes - silently leaves out edges a bot
/// plainly can traverse.
///
///   Landing below (by > ay): arriving over the landing column proves nothing - from a
///   ledge, every surface below is "arrived over" within a tick or two while the
///   character is still tens of pixels up in the air. The jump ends when the arc falls
///   back down to the landing row, which is a much longer flight, and the horizontal
///   distance is then a *constraint* rather than the thing that sets the time: the
///   character must be able to cover it in the time it takes to fall, so the required
///   speed has to be within what the class can run at (F41).
///
///   Landing level or above (by <= ay): a fast dash - horizontal distance at full speed
///   - is tried first, because a character does not dawdle in the air if it does not
///   need to (this is the case the existing tests pin down: a flat ten-cell jump is a
///   13-tick dash, not a 28-tick full arc). If that dash does not gain enough height in
///   time - a *steep, short* jump, more climb than distance - the character instead
///   runs slower and spends longer airborne, up to the first moment the arc reaches the
///   required height. That "slow down" option only helps when the fast dash arrives
///   *before* the arc could possibly be high enough; if it is already past the whole
///   window where the arc is that high (too far sideways for the height on offer, at
///   any speed up to the cap), slowing down only makes the arrival later still, so it
///   is correctly still a rejection, not a slower acceptance.
///
///   ⚠️ **The bug this replaced**: the old code always used the fast-dash time for the
///   "at or above" case, full stop - which is exactly right for a shallow or flat jump
///   but wrongly rejects a steep one, because dashing across one cell in barely a tick
///   leaves no time to rise even though the same jump, taken slowly, clears it with
///   room to spare. Concretely: one column over and eight rows up (48px, close to the
///   full ~57px a standing jump can reach) came back -1, because arriving in the
///   1.3 ticks a full-speed dash takes only gains 10px - and that is a completely
///   ordinary "jump up onto the next step" a stairway is built from. Verified live: on
///   `koth_valley`, this alone was enough to disconnect a bot's spawn from all but 5%
///   of the nav graph, and the failure was visible as a screenshot overlay (green
///   reachable, red not) where the red started exactly at the base of the first tall
///   staircase past spawn.
///
/// Callers get the speed actually flown back out of this as dCells*NAV_CELL_SIZE/t,
/// which is NAV_JUMP_VX exactly for a fast dash and something slower for both a drop
/// and a slow climb. Sampling the arc at NAV_JUMP_VX regardless is what produced jump
/// edges from a ledge to a surface sixteen rows below with another surface in between
/// (F41) - the same mistake this fix undoes for the climbing case.

var ay, by, dCells, riseWorld, dWorld, t, tFast, peakFast, disc, t1;

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
    tFast = dWorld / NAV_JUMP_VX;
    peakFast = NAV_JUMP_V0 * tFast - NAV_JUMP_GRAVITY * tFast * tFast / 2;

    if(peakFast >= riseWorld)
    {
        // The easy, common case: a dash already clears it.
        t = tFast;
    }
    else
    {
        // Not enough height yet at full speed - is there a valid, slower speed that
        // gets there in time, or is the target simply out of reach at any speed up to
        // the cap? v0*t - g*t*t/2 = riseWorld has two roots when riseWorld is within
        // the jump's reach at all; t1 (rising) is only a real option if the fast dash
        // would arrive *before* it, i.e. slowing down has somewhere to go.
        disc = NAV_JUMP_V0 * NAV_JUMP_V0 - 2 * NAV_JUMP_GRAVITY * riseWorld;
        if(disc < 0)
            return -1;

        t1 = (NAV_JUMP_V0 - sqrt(disc)) / NAV_JUMP_GRAVITY;
        if(tFast < t1)
            t = t1;
        else
            return -1;
    }
}

if(t > NAV_JUMP_MAX_TICKS)
    return -1;

return t;
