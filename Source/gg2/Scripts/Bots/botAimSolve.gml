/// botAimSolve(char, target)
/// Returns the aimDirection (degrees) that puts char's current projectile on target,
/// compensating for projectile drop, the target's motion, and - for the weapons that add
/// it - char's own horizontal velocity.
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

var char, target, weapon, spd, grav, drift;

char = argument0;
target = argument1;

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
    return point_direction(char.x, char.y, target.x, target.y);

return botAimLead(char.x, char.y, target.x, target.y,
                  target.hspeed, target.vspeed, spd, grav, drift);
