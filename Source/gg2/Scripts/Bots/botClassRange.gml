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
    case CLASS_PYRO:     return 140;
    case CLASS_QUOTE:    return 300;
}

return 375;
