/// botWeaponBallistics(char, field)
/// One scalar per (weapon, question): the muzzle speed, the per-tick gravity, and the
/// horizontal drift the shooter's own run adds, for whatever this character is holding.
/// Returns 0 for a weapon with no entry, which is how a hitscan or beam weapon says it
/// has no flight to solve - botAimSolve reads BOT_BALL_SPD and falls back to a straight
/// point_direction on zero.
///
/// This table lived inline in botAimSolve, which was the only thing that needed it.
/// botArcClear is the second: it samples the parabola a shot will actually fly, and a
/// second copy of these numbers is exactly how the aim solve and the clearance test end
/// up disagreeing about where a Minegun round goes. Same reasoning as botClassProfile,
/// whose header says it out loud: consolidating two facts is cheap and consolidating
/// twenty is not, so it is done before the third caller rather than after.
///
/// The numbers come from each weapon's own User Event 1, and the drift entries from the
/// projectiles that copy the owner's hspeed:
///
///   Scattergun / Shotgun   spd 13,   grav 0.15,  shot.hspeed += owner.hspeed
///   Minigun                spd 12.5, grav 0.15,  same
///   Revolver               spd 21,   grav 0.15,  no drift - it does speed +=
///                          owner.hspeed*hspeed/15, which perturbs the flight TIME and
///                          not the aim line, so it does not belong in this term
///   Rocketlauncher         spd 12,   grav 0      - the one class whose straight
///                          line-of-sight test matches its own projectile
///   Minegun                spd 12,   grav 0.2    - ~178px of sag at 500px, the largest
///                          in the game and the reason botArcClear exists
///   Flamethrower           spd 8.25, grav 0.15
///   Blade                  spd 10,   grav 0

var char, field, weapon;

char = argument0;
field = argument1;

if(!instance_exists(char.currentWeapon))
    return 0;

weapon = char.currentWeapon.object_index;

if(field == BOT_BALL_SPD)
{
    if(weapon == Scattergun or weapon == Shotgun)
        return 13;
    if(weapon == Minigun)
        return 12.5;
    if(weapon == Revolver)
        return 21;
    if(weapon == Rocketlauncher)
        return 12;
    if(weapon == Minegun)
        return 12;
    if(weapon == Flamethrower)
        return 8.25;
    if(weapon == Blade)
        return 10;
    return 0;
}

if(field == BOT_BALL_GRAV)
{
    if(weapon == Scattergun or weapon == Shotgun)
        return 0.15;
    if(weapon == Minigun)
        return 0.15;
    if(weapon == Revolver)
        return 0.15;
    if(weapon == Minegun)
        return 0.2;
    if(weapon == Flamethrower)
        return 0.15;
    return 0;
}

if(field == BOT_BALL_DRIFT)
{
    if(weapon == Scattergun or weapon == Shotgun or weapon == Minigun)
        return char.hspeed;
    return 0;
}

return 0;
