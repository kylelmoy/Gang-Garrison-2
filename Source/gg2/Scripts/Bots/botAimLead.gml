/// botAimLead(sx, sy, tx, ty, tvx, tvy, spd, grav, drift)
/// Returns the direction (degrees) to fire from (sx, sy) so that a projectile of muzzle
/// speed spd, per-tick gravity grav, and an added constant horizontal drift meets a
/// target that is at (tx, ty) now and moving at (tvx, tvy) px/tick.
///
/// The pure arithmetic behind botAimSolve, kept separate from the weapon table so it can
/// be tested against a forward simulation without needing a Character, a weapon or a map
/// (F33). Callers that want to aim somewhere other than a target's chest - splash at the
/// feet, a predicted landing spot - want this rather than botAimSolve.
///
/// A projectile launched at speed s in direction th is at
///
///     x(t) = sx + (s*cos(th) + drift)*t
///     y(t) = sy - (s*sin(th))*t + grav*t*(t + 1)/2
///
/// The t*(t+1)/2 is exact rather than a continuous approximation: move_all_bullets adds
/// gravity to vspeed *before* it applies the move, so after t ticks the accumulated sag
/// is grav*(1 + 2 + ... + t).
///
/// Set that equal to the target's position at time t and rearrange, and what is left is
/// a plain straight-line aim at a *virtual* point - the target's predicted position,
/// raised by the sag and shifted back by the drift:
///
///     ax = tx + (tvx - drift)*t
///     ay = ty + tvy*t - grav*t*(t + 1)/2
///
/// The only unknown is t, and t is just the distance to that virtual point over spd,
/// because the projectile covers spd px of that straight line every tick. So: guess t,
/// place the point, re-measure t, repeat.
///
/// BOT_AIM_ITERATIONS is 8 rather than the 2-3 that "iterate the flight time" usually
/// wants, and the reason is worth knowing before anyone trims it. Each pass shrinks the
/// error by roughly the target's closing speed over spd, so a stationary target settles
/// in two passes but one running away at 6px/tick from a speed-13 Shot only converges by
/// a factor of ~0.46 a pass - and gravity feeds back, since a longer flight sags more,
/// which puts the aim point further away, which lengthens the flight again. Measured
/// against a forward simulation, a Scout fleeing at 6px/tick is still missed by 26px
/// after 3 passes and by 4.6px after 8. Eight passes is a handful of hypots per aim
/// decision, once per 15 ticks per bot, which is nothing.
///
/// The clamp is what makes an unreachable target safe. Where no solution exists the
/// iteration runs away - the sag pushes the aim point higher, which makes it further
/// away, which makes the flight longer, which increases the sag - so t is held inside
/// [1, BOT_AIM_MAX_TICKS] and the answer degrades into the best bounded lead rather than
/// diverging. That case is real, not hypothetical: a target fleeing at 9px/tick 375px
/// away from a speed-13 Shot has a closing speed of 4px/tick, so the intercept is ~94
/// ticks out and would need a 670px lob - well past both the cap and the projectile's own
/// ~35-tick lifetime. The bot then fires a lead that falls short, which looks like a
/// missed prediction rather than a shot at the sky. Not taking that shot at all is a
/// question of engagement range, which belongs to per-class policy rather than here.
///
/// spd must be positive; a hitscan or beam weapon has no flight time to solve and wants
/// point_direction instead. botAimSolve is what makes that call.

var sx, sy, tx, ty, tvx, tvy, spd, grav, drift, i, t, ax, ay;

sx = argument0;
sy = argument1;
tx = argument2;
ty = argument3;
tvx = argument4;
tvy = argument5;
spd = argument6;
grav = argument7;
drift = argument8;

t = point_distance(sx, sy, tx, ty) / spd;

for(i = 0; i < BOT_AIM_ITERATIONS; i += 1)
{
    t = min(max(t, 1), BOT_AIM_MAX_TICKS);
    ax = tx + (tvx - drift) * t;
    ay = ty + tvy * t - grav * t * (t + 1) / 2;
    t = point_distance(sx, sy, ax, ay) / spd;
}

// Re-derive the aim point at the settled t, so the answer matches the flight time it was
// solved for rather than the one before it.
t = min(max(t, 1), BOT_AIM_MAX_TICKS);
ax = tx + (tvx - drift) * t;
ay = ty + tvy * t - grav * t * (t + 1) / 2;

return point_direction(sx, sy, ax, ay);
