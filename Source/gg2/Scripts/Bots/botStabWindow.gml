/// botStabWindow(char, subject)
/// Whether a Spy pressing ATTACK *now* would actually connect with `subject` - the test
/// that replaces "the enemy is within BOT_STAB_RANGE right now".
///
/// The mechanic, read out of Revolver's cloaked branch and its alarms, is the whole
/// design:
///
///   1. On ATTACK while cloaked with readyToStab, the Spy FREEZES - owner.runPower = 0,
///      owner.jumpStrength = 0 - the StabAnim spawns facing owner.aimDirection, and
///      alarm[1] is set to StabreloadTime, which is 32.
///   2. Thirty-two ticks later alarm[1] creates the StabMask: hitDamage 200, lethal from
///      any angle (front and back only change the kill icon), pinned to owner.x/owner.y
///      every step so it travels nowhere of its own.
///   3. The mask lives alarm[0] = 6 ticks and connects on body overlap, or on an
///      unblocked line from its own origin.
///
/// So the damage window is t+32 to t+38 after the press, and the Spy cannot move during
/// it. botClassKeys used to press on `char.cloak and dist <= BOT_STAB_RANGE`: a test on
/// where the enemy is a full second before the hitbox exists. Against anything that is
/// moving that press is close to a guaranteed miss, and it also freezes the Spy in the
/// open for 38 ticks to take it. This asks the question the mechanic actually poses -
/// will the target be standing in the mask when the mask exists - and refuses when
/// nothing is predicted to arrive, so a Spy does not spend the freeze on empty air.
///
/// The box is the sprite, not a radius. StabMaskS is 64x64 with origin (26, 37) and
/// StabMask's Step sets image_xscale from `direction` without ever touching image_angle,
/// so the mask is axis-aligned and merely flipped: it reaches 37px the way the Spy
/// faces, 26px behind, 37px up and 26px down. BOT_STAB_RANGE therefore stops being the
/// trigger and stays what it always described, the reach.
///
/// The target is grown by its own bounds rather than treated as a point, because the
/// mask collides mask-to-mask: a Character whose centre is just outside the box still
/// overlaps it by a shoulder. Prediction is constant horizontal velocity plus
/// botFallPredict, the same fall model botAimLead uses, floored on the graph through
/// botNodeSnap - a target that is running off a ledge is exactly the case a naive
/// straight-line prediction gets wrong, and it is common at knife range.
///
/// Deliberately says nothing about whether the Spy is cloaked, has readyToStab, or is
/// looking at an ally. Those are botClassKeys' preconditions and they are cheaper than
/// this is.

var char, subject, t, px, py, sfloor, node, tvx, facing;
var mx0, mx1, my0, my1, bx0, bx1, by0, by1, shiftX, shiftY;

char = argument0;
subject = argument1;

if(!botIsCharacter(subject))
    return false;

// The mask, in world coordinates, around where the Spy is standing - which is also
// where it will still be standing, since the press is what freezes it.
facing = 1;
if(char.aimDirection >= 90 and char.aimDirection <= 270)
    facing = -1;
if(facing > 0)
{
    mx0 = char.x - BOT_STAB_BACK;
    mx1 = char.x + BOT_STAB_REACH;
}
else
{
    mx0 = char.x - BOT_STAB_REACH;
    mx1 = char.x + BOT_STAB_BACK;
}
my0 = char.y - BOT_STAB_REACH;
my1 = char.y + BOT_STAB_BACK;

// The floor the target cannot be predicted through. -1 from botNodeSnap means the graph
// has nothing below it, which is what a very large tfloor already means to botFallPredict.
sfloor = 100000;
node = botNodeSnap(subject.x, subject.y);
if(node >= 0)
    sfloor = (ds_grid_get(global.navNodes, NAV_NODE_Y, node) + NAV_BOX_H) * NAV_CELL_SIZE - 23;

tvx = subject.hspeed;

for(t = BOT_STAB_LEAD_MIN; t <= BOT_STAB_LEAD_MAX; t += 1)
{
    px = subject.x + tvx * t;
    py = botFallPredict(subject.y, subject.vspeed, t, sfloor);

    // The target's own body, moved to where it is predicted to be.
    shiftX = px - subject.x;
    shiftY = py - subject.y;
    bx0 = subject.x + subject.left_bound_offset + shiftX;
    bx1 = subject.x + subject.right_bound_offset + shiftX;
    by0 = subject.y + subject.top_bound_offset + shiftY;
    by1 = subject.y + subject.bottom_bound_offset + shiftY;

    if(bx1 >= mx0 and bx0 <= mx1 and by1 >= my0 and by0 <= my1)
        return true;
}

return false;
