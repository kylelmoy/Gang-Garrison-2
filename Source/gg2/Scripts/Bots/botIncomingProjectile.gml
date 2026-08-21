/// botIncomingProjectile(char, range, anyDirection)
/// True if a dangerous enemy projectile is close, for two different callers with two
/// different needs (M7 4.3 widened this from a Pyro-only primitive):
///
///   anyDirection = false  the original airblast check: only the reflectable set
///                         (Rocket, Flare, Mine - Flamethrower's User Event 2), and only
///                         within BOT_AIRBLAST_ARC of where the bot is already aiming,
///                         since airblast costs 40 ammo and only reflects what the
///                         AirBlastO poof overlaps.
///   anyDirection = true   the dodge check: also counts Shot, and drops the facing arc -
///                         you dodge things behind you too, and a Scattergun blast is as
///                         much a reason to jump as a Rocket is. Needle and Flame are left
///                         out: weak enough per-hit and continuous enough that one jump
///                         does not read as "dodging" them the way it does a single shot.
///
/// None of the projectile types share a parent object, so each needs its own pass. There
/// are never many of any of them alive at once.

var char, range, anyDirection, found, inArc;

char = argument0;
range = argument1;
anyDirection = argument2;
found = false;

with(Rocket)
{
    if(ownerPlayer.team != char.team and point_distance(x, y, char.x, char.y) <= range)
    {
        inArc = anyDirection or abs(botAngleDelta(point_direction(char.x, char.y, x, y), char.aimDirection)) <= BOT_AIRBLAST_ARC;
        if(inArc)
            found = true;
    }
}

with(Flare)
{
    if(ownerPlayer.team != char.team and point_distance(x, y, char.x, char.y) <= range)
    {
        inArc = anyDirection or abs(botAngleDelta(point_direction(char.x, char.y, x, y), char.aimDirection)) <= BOT_AIRBLAST_ARC;
        if(inArc)
            found = true;
    }
}

with(Mine)
{
    if(ownerPlayer.team != char.team and point_distance(x, y, char.x, char.y) <= range)
    {
        inArc = anyDirection or abs(botAngleDelta(point_direction(char.x, char.y, x, y), char.aimDirection)) <= BOT_AIRBLAST_ARC;
        if(inArc)
            found = true;
    }
}

if(anyDirection)
{
    with(Shot)
    {
        if(ownerPlayer.team != char.team and point_distance(x, y, char.x, char.y) <= range)
            found = true;
    }
}

return found;
