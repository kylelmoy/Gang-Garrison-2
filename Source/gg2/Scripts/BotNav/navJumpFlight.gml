/// navJumpFlight(ay, by, dCells, capHeight)
/// How long, in ticks, a jump from anchor row ay onto anchor row by lasts while
/// covering dCells anchor columns - or -1 if GG2's jump cannot do it at all.
///
/// **A jump ends where the arc comes back down, and nowhere else.** GG2's jump is a
/// fixed impulse: it rises until it runs out of climb or hits something, and lasts
/// until the arc descends through whatever it lands on. There is no short jump and no
/// variable jump height, so the flight time is a function of the *rise* - the
/// horizontal distance does not shorten it, it only has to be coverable within it:
/// dCells*NAV_CELL_SIZE <= NAV_JUMP_VX * t, or there is no edge.
///
/// `capHeight` is how far the character may rise before a ceiling stops it (see
/// navJumpHeight, which owns the arc itself). Anything at or above the apex means
/// nothing is in the way. A cap below the landing is a rejection: the character
/// cannot get high enough to land there, whatever it does sideways.
///
/// ⚠️ **The bug this replaced, and it is F41 again in the other direction.** The old
/// code timed a *climbing* jump by when the arc first reached the landing height -
/// the earliest moment the character is level with the target. That is not a landing.
/// The character is still rising then, and it keeps rising for another 57px worth of
/// arc before coming down somewhere else entirely. Because the caller derives the
/// horizontal speed as distance/time, a short time meant a fast arc, and the bot flew
/// off the far side of everything it was aimed at.
///
/// Measured against a tick-by-tick simulation of Character's own integration, for a
/// climb of six rows onto a ledge two cells away: the old model called it a 5.4-tick
/// flight at 2.2px/tick, and a bot flying exactly that came down 47px away - four
/// cells past an 18px ledge. The same jump under this model is a 22.3-tick flight at
/// 0.54px/tick and lands on it. Across a sweep of every class, rise, ledge width and
/// run-up distance, "does the bot end up on the node the edge names" went from 12-19%
/// to 100%. That is the whole of koth_valley's four-jump chain to the control point.
///
/// F41 fixed exactly this reasoning for jumps that land *below* the takeoff, where
/// "arrives over the target" is true on the first tick. The climbing case kept its own
/// version of the same mistake: "arrives level with the target" is true 17 ticks before
/// the character is anywhere near landing on it.
///
/// Callers get the speed the arc is flown at as dCells*NAV_CELL_SIZE/t, and both the
/// generator's clearance sampling and the path follower's steering use that same
/// number, which is what makes the edge in the graph and the jump the bot actually
/// flies the same jump.

var ay, by, dCells, capHeight, riseWorld, dWorld, apexHeight, tUp, fall, dTerm, hTerm, d, t;

ay = argument0;
by = argument1;
dCells = argument2;
capHeight = argument3;

riseWorld = (ay - by) * NAV_CELL_SIZE;
dWorld = dCells * NAV_CELL_SIZE;

apexHeight = NAV_JUMP_V0 * NAV_JUMP_V0 / (2 * NAV_JUMP_GRAVITY);
if(capHeight > apexHeight)
    capHeight = apexHeight;
if(capHeight < 0)
    capHeight = 0;

// Higher than the character can get, whether that is the apex or a ceiling below it.
if(riseWorld > capHeight)
    return -1;

tUp = (NAV_JUMP_V0 - sqrt(max(0, NAV_JUMP_V0 * NAV_JUMP_V0 - 2 * NAV_JUMP_GRAVITY * capHeight)))
      / NAV_JUMP_GRAVITY;

// Falling from the top of the rise to the landing row, with the terminal-velocity
// clamp that the long drops actually spend most of their time in.
fall = capHeight - riseWorld;
dTerm = NAV_JUMP_TERM_VY / NAV_JUMP_GRAVITY;
hTerm = NAV_JUMP_GRAVITY * dTerm * dTerm / 2;
if(fall <= hTerm)
    d = sqrt(2 * fall / NAV_JUMP_GRAVITY);
else
    d = dTerm + (fall - hTerm) / NAV_JUMP_TERM_VY;

t = tUp + d;

// Too far sideways to cross before the arc puts the character back on the floor.
if(dWorld > NAV_JUMP_VX * t)
    return -1;

if(t > NAV_JUMP_MAX_TICKS)
    return -1;

return t;
