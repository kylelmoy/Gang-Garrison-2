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

var char, tx, ty, tvx, tvy, leadMode, weapon, spd, grav, drift, t0;

char = argument0;
tx = argument1;
ty = argument2;
tvx = argument3;
tvy = argument4;
leadMode = argument5;

spd = 0;
grav = 0;
drift = 0;

if(instance_exists(char.currentWeapon))
{
    weapon = char.currentWeapon.object_index;

    if(weapon == Scattergun or weapon == Shotgun)
    {
        // Both do shot.hspeed += owner.hspeed, so the shooter's own run carries.
        spd = 13;
        grav = 0.15;
        drift = char.hspeed;
    }
    else if(weapon == Minigun)
    {
        spd = 12.5;
        grav = 0.15;
        drift = char.hspeed;
    }
    else if(weapon == Revolver)
    {
        // Also does speed += owner.hspeed*hspeed/15 - a speed change rather than a
        // direction one, so it perturbs the flight time and not the aim line.
        spd = 21;
        grav = 0.15;
    }
    else if(weapon == Rocketlauncher)
    {
        spd = 12;
        grav = 0;
    }
    else if(weapon == Minegun)
    {
        spd = 12;
        grav = 0.2;
    }
    else if(weapon == Flamethrower)
    {
        spd = 8.25;
        grav = 0.15;
    }
    else if(weapon == Blade)
    {
        spd = 10;
        grav = 0;
    }
}

if(spd <= 0)
    return point_direction(char.x, char.y, tx, ty);

if(leadMode == BOT_LEAD_NONE)
    return botAimLead(char.x, char.y, tx, ty, 0, 0, spd, grav, drift);

if(leadMode == BOT_LEAD_LINEAR)
{
    // One pass, by hand: where the target would be after the flight time to where it is
    // standing now, then a stationary drop solve to that point. Deliberately not
    // botAimLead's iteration - the whole difference between this tier and the next is
    // that the flight time is never re-measured against the point being led to.
    t0 = min(max(point_distance(char.x, char.y, tx, ty) / spd, 1), BOT_AIM_MAX_TICKS);
    return botAimLead(char.x, char.y, tx + tvx * t0, ty + tvy * t0, 0, 0, spd, grav, drift);
}

return botAimLead(char.x, char.y, tx, ty, tvx, tvy, spd, grav, drift);
