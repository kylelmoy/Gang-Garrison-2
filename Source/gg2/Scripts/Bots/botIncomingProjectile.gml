/// botIncomingProjectile(char, range, minTravel)
/// True if a reflectable enemy projectile is close enough, roughly in front of this bot,
/// and has already flown minTravel px from whoever fired it: the Pyro's airblast test, and
/// now its only caller.
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
/// minTravel is the reaction time, and it is a DISTANCE on purpose. The airblast had no
/// delay of any kind: this is re-evaluated every tick and the bit was returned the frame a
/// rocket appeared, so a rocket fired point-blank came back on the frame it was born.
/// Confirmed inhuman, exactly as reported from play. ⚠️ The asymmetry is worth knowing
/// before touching the numbers: with a target inside the acquisition window
/// botCombatUpdate returns early and the airblast is suppressed, so the reflex was
/// fastest precisely when the Pyro was not paying attention.
///
/// Distance beats an age counter twice over. It says "do not reflect a rocket the instant
/// it leaves the barrel" directly rather than by proxy, it is frame-rate independent, and
/// Rocket already maintains exactly this number: move_all_bullets sets travelDistance from
/// the owner's live position every step, for the game's own 800px fade. A rocket's speed
/// decays 13 -> 11.5, so the ~10 frames of human reaction that were asked for is ~120px.
///
/// Flare and Mine carry no travelDistance, so theirs is measured to the owner's Character
/// behind an instance_exists guard. A projectile whose owner has since died has nothing to
/// measure against and is treated as having travelled far enough - it has, by then.
///
/// None of the projectile types share a parent object, so each needs its own pass. There
/// are never many of any of them alive at once.

var char, range, minTravel, found, travelled;

char = argument0;
range = argument1;
minTravel = argument2;
found = false;

with(Rocket)
{
    if(ownerPlayer.team != char.team and point_distance(x, y, char.x, char.y) <= range
       and travelDistance >= minTravel)
    {
        if(abs(botAngleDelta(point_direction(char.x, char.y, x, y), char.aimDirection)) <= BOT_AIRBLAST_ARC)
            found = true;
    }
}

with(Flare)
{
    travelled = minTravel;
    if(instance_exists(ownerPlayer))
    {
        if(botIsCharacter(ownerPlayer.object))
            travelled = point_distance(x, y, ownerPlayer.object.x, ownerPlayer.object.y);
    }
    if(ownerPlayer.team != char.team and point_distance(x, y, char.x, char.y) <= range
       and travelled >= minTravel)
    {
        if(abs(botAngleDelta(point_direction(char.x, char.y, x, y), char.aimDirection)) <= BOT_AIRBLAST_ARC)
            found = true;
    }
}

with(Mine)
{
    travelled = minTravel;
    if(instance_exists(ownerPlayer))
    {
        if(botIsCharacter(ownerPlayer.object))
            travelled = point_distance(x, y, ownerPlayer.object.x, ownerPlayer.object.y);
    }
    if(ownerPlayer.team != char.team and point_distance(x, y, char.x, char.y) <= range
       and travelled >= minTravel)
    {
        if(abs(botAngleDelta(point_direction(char.x, char.y, x, y), char.aimDirection)) <= BOT_AIRBLAST_ARC)
            found = true;
    }
}

return found;
