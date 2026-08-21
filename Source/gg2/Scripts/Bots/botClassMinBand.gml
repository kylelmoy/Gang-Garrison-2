/// botClassMinBand(class)
/// The distance in world pixels inside which this class should not be fighting, and the
/// missing counterpart to botClassRange: that script owns the outer edge of the firing
/// band, this one owns the inner edge. Both are per class and both are the weapon's
/// reach rather than a preference.
///
/// Two different reasons produce a minimum band, and they are worth keeping apart:
///
///   self-harm    a Rocket's explosion has a 65 px radius and a Mine's is similar, so a
///                Soldier or a Demoman firing at something standing on top of it kills
///                itself. That is BOT_SPLASH_SAFE, and it is a hard gate on the trigger
///                (botClassKeys) as well as a reason to back away (botInputUpdate).
///   degeneracy   at zero separation the aim solve has no direction to resolve and two
///                bots that have walked into each other stand nose to nose pressing
///                fire at nothing (M7 2.4). That is BOT_MIN_ENGAGE, and it applies to
///                every class whose weapon is not specifically a close-range one.
///
/// The three classes that return 0 are the ones whose whole job is to be inside anyone
/// else's minimum: a Pyro's Flamethrower cannot touch anything past ~130 px at all, a
/// Spy's stab is a 40 px move, and a Medic's beam is a heal rather than a shot. Backing
/// those away from a fight would be backing them out of the only fight they can win.

var class;
class = argument0;

switch(class)
{
    case CLASS_SOLDIER:  return BOT_SPLASH_SAFE;
    case CLASS_DEMOMAN:  return BOT_SPLASH_SAFE;
    case CLASS_PYRO:     return 0;
    case CLASS_SPY:      return 0;
    case CLASS_MEDIC:    return 0;
}

return BOT_MIN_ENGAGE;
