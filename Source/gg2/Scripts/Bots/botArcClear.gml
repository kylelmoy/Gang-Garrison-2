/// botArcClear(char, aimDir, spd, grav, tx, ty)
/// Whether the projectile this bot is about to fire has a clear path to what it is
/// aimed at - sampled along the PARABOLA, rather than along the straight chest-to-chest
/// line every other sight test in the bot layer uses.
///
/// Nothing in Scripts/Bots ever checked a projectile's arc. botFindTarget,
/// botCombatUpdate's keep-target test and botGoalSpot are all a single straight
/// collision_line_bulletblocking, while botAimSolve deliberately aims *above* the target
/// to compensate for drop - and the amount is large:
///
///     Minegun (Demoman)          spd 12,   grav 0.2    ~178px of sag at 500px
///     Scattergun/Shotgun/Minigun spd 12.5-13, grav 0.15 ~120px at 500, ~64px at 375
///     Rocket                     spd 12,   grav 0      none
///
/// So a Demoman with a clear straight line to a target 500px away is aiming a whole
/// storey above it. Indoors that is the reported "sometimes shooting at the ceiling",
/// stated as a mechanism rather than as a symptom, and it is one test that serves the
/// Demoman, the Soldier's wasted low-ceiling rocket, and every arcing weapon in the game.
///
/// The flight law is move_all_bullets' own, the same one botAimLead solves against:
///
///     x(t) = sx + vx*t
///     y(t) = sy + vy*t + grav*t*(t + 1)/2
///
/// The t*(t+1)/2 is exact rather than a continuous approximation - gravity is added to
/// vspeed *before* the move is applied, so after t ticks the accumulated sag is
/// grav*(1 + 2 + ... + t).
///
/// The last sample is the target itself rather than the parabola's own endpoint. The
/// flight time is recovered from the horizontal offset, which carries a tick or so of
/// error, and letting that error put the final sample a few pixels *into* the floor the
/// target is standing on would refuse every shot at a grounded enemy. Ending on the
/// aim point is also exactly what botFindTarget's straight test does, so a flat weapon
/// gets the same answer it always did.
///
/// Withholding rather than re-solving is deliberate for v1. A flatter solution generally
/// means closing the distance, which is a positioning decision, and botGoalSpot owns
/// those.
///
/// spd must be positive; a hitscan weapon has no arc to sample and its caller should not
/// be here.

var char, aimDir, spd, grav, tx, ty, sx, sy, vx, vy, tHit, i, t, ax, ay, bx, by;

char = argument0;
aimDir = argument1;
spd = argument2;
grav = argument3;
tx = argument4;
ty = argument5;

if(spd <= 0)
    return true;

sx = char.x;
sy = char.y;
vx = lengthdir_x(spd, aimDir);
vy = lengthdir_y(spd, aimDir);

// When the shot is very nearly vertical the horizontal offset says nothing about the
// flight time, so fall back to the straight-line estimate. Clamped the same way
// botAimLead clamps its own t, so an unreachable aim point cannot make this sample a
// thousand ticks of parabola.
if(abs(vx) > 0.01)
    tHit = (tx - sx) / vx;
else
    tHit = point_distance(sx, sy, tx, ty) / spd;
tHit = min(max(tHit, 1), BOT_AIM_MAX_TICKS);

bx = sx;
by = sy;
for(i = 1; i <= BOT_ARC_SAMPLES; i += 1)
{
    if(i == BOT_ARC_SAMPLES)
    {
        ax = tx;
        ay = ty;
    }
    else
    {
        t = tHit * i / BOT_ARC_SAMPLES;
        ax = sx + vx * t;
        ay = sy + vy * t + grav * t * (t + 1) / 2;
    }

    if(collision_line_bulletblocking(bx, by, ax, ay))
        return false;

    bx = ax;
    by = ay;
}

return true;
