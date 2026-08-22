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
/// Minimum bands live in botClassMinBand, which is botClassRange's counterpart: that one
/// owns the outer edge of the firing band, this one reads the inner edge from there. The
/// gate here is self-harm - a Rocket's explosion has a 65 px radius and a Mine's is
/// similar, so a Soldier or Demoman that fires at something standing on top of it kills
/// itself. botClassMinBand also carries a much smaller floor for everyone else, which is
/// about the aim solve degenerating at zero separation rather than about damage (M7 2.4),
/// and which botInputUpdate - not this script - acts on by backing the bot away.
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
        if(subject != noone and dist >= botClassMinBand(CLASS_SOLDIER))
            keys |= KEY_ATTACK;
        break;

    case CLASS_DEMOMAN:
        if(subject != noone and dist >= botClassMinBand(CLASS_DEMOMAN))
            keys |= KEY_ATTACK;

        // SPECIAL detonates every mine this bot has out at once, so it is worth pressing
        // the moment any one of them has an enemy inside its blast - which is what a
        // chokepoint full of mines is for.
        if(botMinesArmed(player, char))
            keys |= KEY_SPECIAL;
        break;

    case CLASS_PYRO:
        // Open fire while still closing, not on arrival. A Flame takes ticks to fly and
        // most of a Pyro's damage is the afterburn it lights, so the shot that matters is
        // the one already in the air when the enemy walks into it - which is why
        // BOT_FLAME_REACH sits at the far end of the flame's travel (~165 of a possible
        // ~175) rather than safely inside it. Some of those flames fall short; the ammo
        // pool is 200 at 1.8 a shot and refills on its own, so they cost nothing that
        // matters.
        //
        // Nothing here stops on a lost sightline, and that is deliberate. dist and the aim
        // both come off the target snapshot, which botCombatUpdate freezes at the last
        // position actually seen and keeps for 30 ticks (M7 3.8) - so a Pyro whose target
        // ducks behind a corner keeps washing that corner for a second, which is what a
        // player does and what afterburn rewards.
        if(subject != noone and dist <= BOT_FLAME_REACH)
            keys |= KEY_ATTACK;

        // Airblast is a reflex, not an attack: it costs 40 ammo and there is no point
        // spending it on empty air.
        if(instance_exists(weapon))
        {
            if(weapon.ammoCount >= 40 and botIncomingProjectile(char, BOT_AIRBLAST_RANGE, false))
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

    case CLASS_SNIPER:
        // The charge trades time for damage - baseDamage 45 at t=0 up to maxDamage 75 at
        // a full chargeTime (105 ticks/3.5s), on a sqrt curve where half the charge
        // already buys most of the difference (Rifle's own Begin Step). Firing at t=0,
        // which is what the shared default branch below does for every class including
        // this one, throws away up to 40% of the shot's damage on every single shot (M7
        // 3.7) - zoom (botServerActions) already gets a bot into range and charging; this
        // is the other half, actually waiting for the charge before pulling the trigger.
        // Only applies with the Rifle out - the melee and secondary have no charge to
        // wait for, so they fall through to the shared default's shoot-on-sight cases.
        //
        // ⚠️ Neither does an *unzoomed* Rifle, and missing that made a Sniper useless at
        // anything but long range for as long as this branch has existed. The charge only
        // accumulates while zoomed - Rifle's Begin Step is `if(owner.zoomed and
        // readyToShoot) t += 1` with `else t = 0` - and botServerActions only zooms at
        // BOT_ZOOM_RANGE, unzooming again at BOT_UNZOOM_RANGE. So for a target between the
        // minimum band and ~250-400px, t is pinned at 0, the threshold below is always
        // above it, and the trigger was simply never pulled: the bot acquired an enemy
        // closing on it, tracked it all the way in, and never fired a shot. Measured with
        // the behaviour harness, same bot and window with only the distance changed - a
        // dummy at 200px took 0 damage over four runs while a generator at 460px took 67.
        //
        // Firing unzoomed is not a compromise, it is the game's own close-range answer:
        // the Rifle carries a separate unscopedDamage (35) that Begin Step selects
        // whenever the owner is not zoomed. Waiting would be waiting for a number that
        // cannot change. Zoom stays where it is - it is a liability up close on purpose
        // (botServerActions), so the fix belongs here rather than in the zoom thresholds.
        if(subject != noone)
        {
            if(instance_exists(weapon) and weapon.object_index == Rifle)
            {
                if(!char.zoomed)
                    keys |= KEY_ATTACK;
                // Scale the wait with distance: a target out near botClassRange is not
                // closing fast enough to punish a full charge, one much closer is close
                // to a melee problem by the time a full charge would land.
                else if(weapon.t >= weapon.chargeTime * min(1, dist / botClassRange(CLASS_SNIPER)))
                    keys |= KEY_ATTACK;
            }
            else
                keys |= KEY_ATTACK;
        }
        break;

    default:
        // Scout, Heavy, Engineer and Quote all just shoot: their whole band is
        // botClassRange, and the caller has already checked it.
        if(subject != noone)
            keys |= KEY_ATTACK;
        break;
}

return keys;
