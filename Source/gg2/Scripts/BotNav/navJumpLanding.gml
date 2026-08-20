/// navJumpLanding(ay, by, takeoff, bx0, bx1, dir, lead, capHeight)
/// Which anchor column on the target surface a jump from `takeoff` aims at when it aims
/// `lead` columns into the surface, or -1 if that column is off the surface or out of
/// the arc's reach.
///
/// The obvious answer - the nearest column of the target, `takeoff + dir` clamped into
/// the span - is the one this used to be, in three places, and it aims at the *worst*
/// column on the surface. A node's span runs from NAV_BOX_W-1 columns before the solid
/// it stands on, because navNodesExtract counts an anchor as standable when any one of
/// the four footprint cells is supported: a character part-way off a ledge is still
/// standing. So the nearest anchor is the one where the body hangs off the edge by three
/// cells of four, and landing a single pixel short of it is a fall.
///
/// A bot's landing is not pixel-exact - it steers toward the planned trajectory with a
/// key that can only be held or not held, so it arrives up to a column short. Measured
/// over every class, rise, ledge width and run-up: aiming at the nearest column, the bot
/// ends up on the node it was aimed at 62-76% of the time; with one column of lead,
/// 100%. So aim NAV_JUMP_LAND_LEAD columns *into* the surface, exactly the way
/// BOT_ENTRY_LEAD does for walking onto one.
///
/// The lead is a caller's loop rather than this script's, because whether it is
/// affordable is not only a question of reach - navJumpTakeoff tries the leads it wants
/// against real geometry and takes the first arc that flies. A bigger lead is a faster
/// arc, and a faster arc drifts sideways sooner, which is precisely what a character
/// climbing onto a ledge cannot afford: it has to be above the ledge before it is over
/// it. On koth_valley the step out of the valley floor is only flyable at all at
/// 0.5px/tick, so the lead has to be able to lose.

var ay, by, takeoff, bx0, bx1, dir, lead, capHeight, col;

ay = argument0;
by = argument1;
takeoff = argument2;
bx0 = argument3;
bx1 = argument4;
dir = argument5;
lead = argument6;
capHeight = argument7;

if(dir < 0)
{
    col = min(bx1, takeoff - 1) - lead;
    if(col < bx0)
        return -1;
}
else
{
    col = max(bx0, takeoff + 1) + lead;
    if(col > bx1)
        return -1;
}

if(navJumpFlight(ay, by, abs(col - takeoff), capHeight) < 0)
    return -1;

return col;
