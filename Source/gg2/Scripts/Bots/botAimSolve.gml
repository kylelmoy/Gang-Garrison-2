/// botAimSolve(char, tx, ty, tvx, tvy, leadMode)
/// Returns the aimDirection (degrees) that puts char's current projectile on a target at
/// (tx, ty) moving at (tvx, tvy) px/tick, compensating for projectile drop, the target's
/// motion, and - for the weapons that add it - char's own horizontal velocity.
///
/// The aim point is passed in rather than read off an instance because the caller aims at
/// something other than a chest often enough for it to be the rule: a stale perceived
/// position (the difficulty model's perception lag), or the ground under a target's feet
/// for a splash weapon.
///
/// Almost nothing in GG2 is hitscan. The Rifle is; the Rocket flies flat; every other
/// projectile falls, at 0.15 or 0.2 px per tick squared
/// (Scripts/Physics/System/move_all_bullets.gml). A Shot at speed 13 crossing the 375px
/// combat radius takes ~29 ticks and sags ~64px on the way - a whole character height -
/// so aiming straight at a target shoots consistently high at range, on the Scattergun
/// and the Revolver just as much as on the obviously-lobbed Minegun. Left unfixed that
/// presents as "the bots are just bad at long range" rather than as an aiming bug.
///
/// This script is the weapon table; botAimLead is the arithmetic.
///
/// Speeds are the muzzle speeds passed to createShot, averaged where the weapon rolls
/// them (Minigun 12+random(1), Flamethrower 6.5+random(3.5)). Per-shot spread is not
/// modelled - it is symmetric about the aim line, so the solved direction is still the
/// best single answer.
///
/// The Rocket is the one real approximation. It accelerates rather than coasting -
/// speed = (speed + 1)*0.92 every tick, decaying from 13 toward a fixed point of 11.5 -
/// which averages ~12.07 over a 30-tick flight. A flat 12 costs about half a tick of
/// flight time over that distance, and since the rocket has no gravity that shows up
/// only as ~3px of lead error against a sprinting Scout.
///
/// The Rifle (true hitscan) and the Medigun (whose primary is an ally-targeting heal
/// beam, not a projectile at all) fall through to a direct point_direction. A Medic
/// firing needles aims with $08, which is per-class policy rather than this script's
/// business.
///
/// leadMode is the difficulty model's leading gate, and the three modes are three
/// different players rather than three accuracies:
///
///   BOT_LEAD_NONE    solve the drop, treat the target as standing still. Anything that
///                    moves is missed behind, which is what a weak bot should do.
///   BOT_LEAD_LINEAR  predict the target once, at the flight time to where it is now,
///                    and solve the drop to that predicted point. Right for a slow target
///                    or a short shot, and increasingly short as the flight lengthens -
///                    the characteristic miss of someone who leads by eye. Measured
///                    against a simulation of the engine's own integration: it lands a
///                    Shot on a target running 6 px/tick out to ~200 px and misses it
///                    behind at 375 px, where the full solve still connects.
///   BOT_LEAD_FULL    the full iterated intercept in botAimLead.
///
/// Quake III gates leading the same way, on aim_skill 0.4 and 0.8, and the difference is
/// highly legible from the receiving end.

var char, tx, ty, tvx, tvy, leadMode, spd, grav, drift, t0;
var tfloor, node;

char = argument0;
tx = argument1;
ty = argument2;
tvx = argument3;
tvy = argument4;
leadMode = argument5;

// The weapon's own numbers, from botWeaponBallistics - which is where this table used
// to be written out inline. botArcClear needs the same three, and two copies of them is
// how the aim solve and the clearance test end up firing at different parabolas.
spd = botWeaponBallistics(char, BOT_BALL_SPD);
grav = botWeaponBallistics(char, BOT_BALL_GRAV);
drift = botWeaponBallistics(char, BOT_BALL_DRIFT);

if(spd <= 0)
    return point_direction(char.x, char.y, tx, ty);

if(leadMode == BOT_LEAD_NONE)
    // "Standing still" means standing still on every axis, not just the horizontal ones -
    // pin the floor to ty itself so botAimLead's target-gravity term has nothing to fall
    // through and vanishes, same as tvy = 0 already meant before that term existed.
    return botAimLead(char.x, char.y, tx, ty, 0, 0, spd, grav, drift, ty);

if(leadMode == BOT_LEAD_LINEAR)
{
    // One pass, by hand: where the target would be after the flight time to where it is
    // standing now, then a stationary drop solve to that point. Deliberately not
    // botAimLead's iteration - the whole difference between this tier and the next is
    // that the flight time is never re-measured against the point being led to.
    //
    // The linear step already applied tvy by hand, so the point handed to botAimLead is
    // treated as at rest there - pin the floor to it for the same reason as
    // BOT_LEAD_NONE, or the target-gravity term would apply a second, uncoordinated fall
    // on top of this one.
    t0 = min(max(point_distance(char.x, char.y, tx, ty) / spd, 1), BOT_AIM_MAX_TICKS);
    return botAimLead(char.x, char.y, tx + tvx * t0, ty + tvy * t0, 0, 0, spd, grav, drift,
                      ty + tvy * t0);
}

// Search downward from the target for the nearest floor - literally the snap
// botObjectiveUpdate uses to anchor a goal onto the graph (M7 3.6). A cheap
// approximation: exactly right for a target that lands back on the platform it left,
// and only wrong if it drifts onto a different one mid-flight, same as everywhere else
// in this codebase that already accepts "the nearest node below" as the answer.
//
// It calls botNodeSnap rather than repeating its loop, which is what it was doing: a
// second copy of the same 900px descent, running on the target cadence instead of the
// objective one, and just as capable of spending a whole frame on a target standing over
// a pit. Its own navReady guard is botNodeSnap's, which returns -1 for the same case.
tfloor = 100000; // no map is this tall; disables the clamp when the graph has no floor here
node = botNodeSnap(tx, ty);
if(node >= 0)
    tfloor = (ds_grid_get(global.navNodes, NAV_NODE_Y, node) + NAV_BOX_H) * NAV_CELL_SIZE - 23;

return botAimLead(char.x, char.y, tx, ty, tvx, tvy, spd, grav, drift, tfloor);
