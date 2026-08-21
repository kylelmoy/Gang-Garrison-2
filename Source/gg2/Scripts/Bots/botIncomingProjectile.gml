/// botIncomingProjectile(char, range)
/// True if an enemy projectile a Pyro can actually reflect is close and in front of it.
/// Airblast costs 40 ammo and reflects only what the AirBlastO poof overlaps, so this
/// checks the same two things the poof would: distance, and that the thing is on the
/// side the bot is facing.
///
/// Rocket, Flare and Mine are the reflectable set (Flamethrower's User Event 2) and none
/// of them shares a parent object, so each needs its own pass. There are never many of
/// any of them alive at once.
///
/// The arc is BOT_AIRBLAST_ARC either side of where the bot is already aiming, which is
/// normally at whoever fired the thing.

var char, range, found;

char = argument0;
range = argument1;
found = false;

with(Rocket)
{
    if(ownerPlayer.team != char.team and point_distance(x, y, char.x, char.y) <= range)
    {
        if(abs(botAngleDelta(point_direction(char.x, char.y, x, y), char.aimDirection)) <= BOT_AIRBLAST_ARC)
            found = true;
    }
}

with(Flare)
{
    if(ownerPlayer.team != char.team and point_distance(x, y, char.x, char.y) <= range)
    {
        if(abs(botAngleDelta(point_direction(char.x, char.y, x, y), char.aimDirection)) <= BOT_AIRBLAST_ARC)
            found = true;
    }
}

with(Mine)
{
    if(ownerPlayer.team != char.team and point_distance(x, y, char.x, char.y) <= range)
    {
        if(abs(botAngleDelta(point_direction(char.x, char.y, x, y), char.aimDirection)) <= BOT_AIRBLAST_ARC)
            found = true;
    }
}

return found;
