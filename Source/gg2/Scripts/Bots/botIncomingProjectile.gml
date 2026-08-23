/// botIncomingProjectile(char, range)
/// True if a reflectable enemy projectile is close enough and roughly in front of this bot:
/// the Pyro's airblast test, and now its only caller.
///
/// The reflectable set is Rocket, Flare and Mine (Flamethrower's User Event 2), and the
/// facing arc matters because airblast costs 40 ammo and only reflects what the AirBlastO
/// poof actually overlaps - so a rocket behind the bot is not worth spending on.
///
/// This used to have a second mode that dropped the arc and counted Shot as well, for the
/// evasive jump. That question turned out not to be a proximity question at all - see
/// botRocketDodge, which models the arc instead - so the mode is gone and this is back to
/// the one job it was written for.
///
/// None of the projectile types share a parent object, so each needs its own pass. There
/// are never many of any of them alive at once.

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
