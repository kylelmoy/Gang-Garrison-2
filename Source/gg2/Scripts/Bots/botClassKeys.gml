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
var arcSpd, arcClear;

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

// Does the shot this bot is lined up on actually have a path to what it is aimed at?
//
// Nothing in the bot layer ever asked. Every sight test in Scripts/Bots is a straight
// chest-to-chest collision_line_bulletblocking, while botAimSolve deliberately aims ABOVE
// the target to compensate for drop - ~178px of it at 500px for a Minegun round. So a
// Demoman with a clear straight line to a target across a room is aiming a whole storey
// above it, and indoors that is the reported "sometimes shooting at the ceiling", stated
// as a mechanism rather than as a symptom. It is the same test for the Soldier's wasted
// low-ceiling rocket, which is why it is computed once here rather than in two branches.
//
// Only for the two classes whose shot kills them if it goes off next to them, and only
// with a subject to aim at. Everyone else pays nothing: a Scattergun round that clips a
// lintel costs ammo the class has plenty of, and withholding would make a Scout stop
// firing in exactly the corridors it wants to be firing in.
arcClear = true;
if(subject != noone and (player.class == CLASS_SOLDIER or player.class == CLASS_DEMOMAN))
{
    arcSpd = botWeaponBallistics(char, BOT_BALL_SPD);
    if(arcSpd > 0)
        arcClear = botArcClear(char, char.aimDirection, arcSpd,
                               botWeaponBallistics(char, BOT_BALL_GRAV),
                               subject.x, subject.y);
}

switch(player.class)
{
    case CLASS_SOLDIER:
        // Rockets fly flat and hurt whoever is standing next to the impact, including
        // the shooter. Flat means arcClear is very nearly the straight-line test the
        // target search already passed - but not quite, because a rocket fired with lead
        // does not go down the line the target was cleared on.
        if(subject != noone and dist >= botClassMinBand(CLASS_SOLDIER) and arcClear)
            keys |= KEY_ATTACK;
        break;

    case CLASS_DEMOMAN:
        // Withholding rather than re-solving for a flatter shot is deliberate for v1: a
        // flatter solution generally means closing the distance, and where this bot stands
        // is botGoalSpot's decision, not this script's.
        if(subject != noone and dist >= botClassMinBand(CLASS_DEMOMAN) and arcClear)
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
        //
        // readyToBlast is checked first and is not decoration. The blast is on a 40-tick
        // cooldown (blastReloadTime) and the reflect test inside User Event 2 runs only on
        // the frame of the press, so the cost of a press aimed at nothing is not the ammo -
        // it is that the next rocket, the one that was going to land, arrives while the
        // weapon is still reloading. It is also much the cheapest of the three tests and
        // gates the other two regardless of geometry.
        if(instance_exists(weapon))
        {
            if(weapon.readyToBlast and weapon.ammoCount >= 40
               and botIncomingProjectile(char, BOT_AIRBLAST_MIN_TRAVEL))
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
        // Cloaked, and the target is predicted to be standing in the knife when the knife
        // exists: try the stab, which is the ordinary attack while cloaked.
        //
        // ⚠️ The old test was `dist <= BOT_STAB_RANGE` - where the enemy is NOW. The
        // hitbox does not exist until 32 ticks after the press (Revolver's alarm[1],
        // StabreloadTime), lives 6 more, and the Spy is frozen in place for all of it
        // (the press sets owner.runPower and owner.jumpStrength to 0). So that press was
        // aimed a full second early: against anything moving it was close to a guaranteed
        // miss, and it spent 38 frozen ticks in the open to take it. botStabWindow asks
        // about ticks 32-38 instead, and refuses when nothing is predicted to arrive.
        //
        // readyToStab is checked here rather than inside botStabWindow because it is much
        // the cheaper of the two and gates the press regardless of geometry.
        if(char.cloak and subject != noone and !subjectIsAlly
           and instance_exists(weapon) and weapon.readyToStab
           and botStabWindow(char, subject))
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
