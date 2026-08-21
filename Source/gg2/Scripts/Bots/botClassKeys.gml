/// botClassKeys(player, char, subject, dist, subjectIsAlly, tick)
/// The per-class firing policy: which of ATTACK and SPECIAL this bot wants held this
/// tick, given what it is aiming at. subject may be noone, which is how a class says
/// what it does with nobody in front of it (a Spy re-cloaks; everyone else waits).
///
/// The caller has already decided *where* the bot aims and whether the fire gates are
/// open (botCombatUpdate); this script only decides what the trigger fingers do. It is
/// deliberately the one place a class's weapon knowledge lives, because the alternative
/// - a switch in the aim code, another in the input driver - is how two of them end up
/// disagreeing about what SPECIAL means.
///
/// SPECIAL is not one action. Character's Begin Step routes it three ways at once: it
/// runs the current weapon's User Event 2 while the bit is *held*, and it toggles a
/// Spy's cloak on the rising *edge*. So a Pyro or a Demoman can hold it, and a Spy must
/// press and release it - which is why the cloak branch throttles itself through
/// botCloakAt rather than returning the bit every tick.
///
/// Minimum bands exist for one reason: self-harm. A Rocket's explosion has a 65 px
/// radius and a Mine's is similar, so a Soldier or Demoman that fires at something
/// standing on top of it kills itself. Everything else fires from zero.
///
/// v1 simplifications, matching the plan's open questions: no sticky-jumping, no
/// deliberate Spy flanking, and the Engineer builds where it stands rather than choosing
/// a chokepoint (botServerActions).

var player, char, subject, dist, subjectIsAlly, tick, keys, weapon, enemyNear;

player = argument0;
char = argument1;
subject = argument2;
dist = argument3;
subjectIsAlly = argument4;
// The tick is passed rather than read off the caller as "frame": frame is a GameServer
// variable, so reading it here would make this script callable only from inside the
// server step - and the first thing anyone does with a policy script is call it by hand
// to ask what it would decide.
tick = argument5;

keys = 0;
weapon = char.currentWeapon;

switch(player.class)
{
    case CLASS_SOLDIER:
        // Rockets fly flat and hurt whoever is standing next to the impact, including
        // the shooter.
        if(subject != noone and dist >= BOT_SPLASH_SAFE)
            keys |= KEY_ATTACK;
        break;

    case CLASS_DEMOMAN:
        if(subject != noone and dist >= BOT_SPLASH_SAFE)
            keys |= KEY_ATTACK;

        // SPECIAL detonates every mine this bot has out at once, so it is worth pressing
        // the moment any one of them has an enemy inside its blast - which is what a
        // chokepoint full of mines is for.
        if(botMinesArmed(player, char))
            keys |= KEY_SPECIAL;
        break;

    case CLASS_PYRO:
        if(subject != noone and dist <= BOT_FLAME_REACH)
            keys |= KEY_ATTACK;

        // Airblast is a reflex, not an attack: it costs 40 ammo and there is no point
        // spending it on empty air.
        if(instance_exists(weapon))
        {
            if(weapon.ammoCount >= 40 and botIncomingProjectile(char, BOT_AIRBLAST_RANGE))
                keys |= KEY_SPECIAL;
        }
        break;

    case CLASS_MEDIC:
        if(subjectIsAlly)
        {
            // The heal beam is the primary. Uber is SPECIAL *while* the primary is held,
            // and it is worth its whole charge only with an enemy close enough to matter.
            keys |= KEY_ATTACK;
            if(instance_exists(weapon))
            {
                if(weapon.uberReady and botEnemyWithin(char, BOT_UBER_RANGE))
                    keys |= KEY_SPECIAL;
            }
        }
        else if(subject != noone)
            keys |= KEY_SPECIAL;   // needles: the Medigun fires them on SPECIAL alone
        break;

    case CLASS_SPY:
        // Cloaked, and close enough to be behind someone: try the stab, which is the
        // ordinary attack while cloaked.
        if(char.cloak and subject != noone and dist <= BOT_STAB_RANGE)
            keys |= KEY_ATTACK;
        else
        {
            enemyNear = (subject != noone and !subjectIsAlly);
            if(char.cloak == enemyNear and char.canCloak and !char.intel)
            {
                // Uncloak to shoot, re-cloak once there is nothing to shoot at. The bit
                // has to arrive as an edge, and readyToStab gates the toggle, so pressing
                // it every tick would both fail and hold the weapon's own SPECIAL down.
                if(tick - player.botCloakAt >= BOT_CLOAK_PERIOD)
                {
                    keys |= KEY_SPECIAL;
                    player.botCloakAt = tick;
                }
            }
            else if(subject != noone and !char.cloak)
                keys |= KEY_ATTACK;
        }
        break;

    default:
        // Scout, Sniper, Heavy, Engineer and Quote all just shoot: their whole band is
        // botClassRange, and the caller has already checked it.
        if(subject != noone)
            keys |= KEY_ATTACK;
        break;
}

return keys;
