/// botClassRange(class)
/// The distance in world pixels at which this class stops caring about an enemy. It is
/// both the target-search radius and the outer edge of the firing band, so a bot never
/// tracks something it could not shoot.
///
/// These are the weapons' real reaches, not preferences. A Flamethrower's Flame lives 15
/// ticks at 6.5-10 px/tick, so it simply cannot touch anything past ~130 px, and a Pyro
/// holding down fire at 300 px is only announcing where it is. A Rifle is the one true
/// hitscan weapon in the game and is limited by sight rather than by flight. In between,
/// the Scattergun and Shotgun fire spreads whose pellets diverge to uselessness well
/// before the 375 px the sentry uses, while the Rocketlauncher's Rocket is explicitly
/// given range 800.
///
/// Minimum bands are botClassKeys' business, because they are about self-harm and
/// weapon behaviour rather than about attention.
///
/// ⚠️ The Pyro is deliberately NOT its weapon's reach, and that is the one exception here.
/// A Flame spawns 25 px out, lives 15 ticks at 6.5-10 px/tick and inherits the owner's
/// motion, so it lands somewhere between ~120 and ~175 px depending on the roll and on
/// whether the Pyro is running in. This value is the range at which the bot keeps *paying
/// attention* to an enemy, and setting it at the weapon's reach (it was 140, against a
/// BOT_FLAME_REACH of 130) meant a target that stepped 10 px back was dropped from the
/// roster entirely: the bot stopped tracking, stopped turning, and had to re-acquire from
/// scratch when it closed again. Reported from play as a Pyro that fires too late and
/// stops too early. 200 keeps the target held while the Pyro closes the gap, which is what
/// a Pyro's whole game is; botClassKeys still refuses the trigger past BOT_FLAME_REACH.

var class;
class = argument0;

switch(class)
{
    case CLASS_SCOUT:    return 220;
    case CLASS_SOLDIER:  return 800;
    case CLASS_SNIPER:   return 900;
    case CLASS_DEMOMAN:  return 500;
    case CLASS_MEDIC:    return 300;
    case CLASS_ENGINEER: return 400;
    case CLASS_HEAVY:    return 500;
    case CLASS_SPY:      return 300;
    case CLASS_PYRO:     return 200;
    case CLASS_QUOTE:    return 300;
}

return 375;
