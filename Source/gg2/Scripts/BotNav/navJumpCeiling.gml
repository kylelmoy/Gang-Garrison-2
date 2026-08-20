/// navJumpCeiling(freeGrid, col, ay)
/// How high, in world px, a character standing at anchor (col, ay) can rise before the
/// map stops it - the apex when nothing is above, less when something is.
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
/// Only the takeoff column is scanned, which is the cheap 90% of the answer: the
/// character spends the whole rise over or beside its takeoff, and anything lower over
/// the rest of the path is still caught by the arc's own clearance walk. Ten reads at
/// most, since nothing above the apex can matter.

var freeGrid, col, ay, apexHeight, maxRows, r, capHeight;

freeGrid = argument0;
col = argument1;
ay = argument2;

apexHeight = NAV_JUMP_V0 * NAV_JUMP_V0 / (2 * NAV_JUMP_GRAVITY);
maxRows = ceil(apexHeight / NAV_CELL_SIZE);
capHeight = apexHeight;

for(r = 1; r <= maxRows; r += 1)
{
    // Above the top of the walkmask is open sky, not a ceiling.
    if(ay - r < 0)
        break;

    if(ds_grid_get(freeGrid, col, ay - r) != 1)
    {
        capHeight = (r - 1) * NAV_CELL_SIZE;
        break;
    }
}

return capHeight;
