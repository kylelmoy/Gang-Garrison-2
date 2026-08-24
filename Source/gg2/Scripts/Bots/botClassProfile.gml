/// botClassProfile(class, field)
/// One scalar per (class, question): the single home for every per-class fact that is not
/// already owned by a named table script. Returns 0 for anything a class has no opinion
/// about, so a caller can treat the answer as a flag without checking for a default.
///
/// Why this exists. Six per-class tests used to live inline in shared scripts -
/// botCombatUpdate had four, botInputUpdate and botObjectiveUpdate one each - and each was
/// defensible where it sat, because each changed aiming or movement rather than trigger
/// bits. Collectively, though, "what does a Pyro do differently" was a four-file grep, and
/// per-class tuning adds to that set rather than shrinking it. Consolidating six is cheap;
/// consolidating twenty is not, so this was built before the seventh.
///
/// A class's knowledge now lives in exactly five places, and this header is the index:
///
///   botClassRange     the outer edge of the engagement band (attention and firing)
///   botClassMinBand   the inner edge - self-harm, and aim degeneracy at zero separation
///   botClassKeys      the trigger policy: what ATTACK and SPECIAL do
///   botServerActions  the behaviours that are commands rather than keys - zoom, build, eat
///   botClassProfile   everything else, which is this file
///
/// The four above keep their own scripts because each is named for its one question and
/// each is read from several places; folding them in here would trade four clear names for
/// four more field constants and buy nothing.
///
/// The fields, and who reads each:
///
///   BOT_CP_POTSHOT       botCombatUpdate. Whether this class takes speculative shots at a
///                        target outside its ordinary attention radius (M7 3.5). Off for a
///                        Pyro, whose Flame dies at ~130 px so a long shot is pure ammo
///                        waste that also lights up exactly where it is standing, and off
///                        for a Medic, whose primary is a heal beam.
///   BOT_CP_HEALS         botCombatUpdate. Whether a hurt team-mate outranks an enemy as
///                        the thing to aim at. The Medic is the one class for which not
///                        engaging is correct play.
///   BOT_CP_SPLASH        botCombatUpdate. Whether a grounded target should be aimed at the
///                        feet rather than the chest - a rocket or a mine that lands at the
///                        feet damages regardless of where the target steps next. Gated
///                        again by the difficulty knob botSplashAim, which is Quake III's
///                        own gate; this field is the class half of that test.
///   BOT_CP_SPECIAL_FIRE  botCombatUpdate. Whether SPECIAL is this class's trigger and so
///                        must answer to the fire gates. Only the Medic: its needles are on
///                        SPECIAL alone. Every other class's SPECIAL is a reflex - an
///                        airblast, a detonation - and deliberately is not gated, because a
///                        reaction that arrives 1.5 s late is not a reaction.
///   BOT_CP_AIRJUMP       No consumer. It described the class that had a second jump worth
///                        spending on evasion (M7 4.1); that behaviour was removed from
///                        botInputUpdate along with the rest of the voluntary combat
///                        jumping. The row is kept because it is still true about the
///                        Scout, and because a NAV_EDGE_DOUBLEJUMP generator - the
///                        navigation half of the feature, which was never built - is the
///                        one caller that would want it back.
///   BOT_CP_FOLLOW        botObjectiveUpdate. Whether this class's goal is a moving ally
///                        rather than the game mode's objective (M7 6.2).
///   BOT_CP_DEFEND_EVERY  botRoleAssign. One bot in every N of this class's lean group
///                        defends. See that script for what a lean group is and why the
///                        rule is a count rather than a die roll.
///   BOT_CP_SPOT_MODE     botObjectiveUpdate. How this class positions itself relative to
///                        the objective, as one of BOT_SPOT_NONE / STANDOFF / CHOKE /
///                        FLANK. See below.
///   BOT_CP_SPOT_HIGH     botObjectiveUpdate. How much this class values height when
///                        choosing that position, in botGoalSpot's highBonus units.
///   BOT_CP_SUPPRESS      botCombatUpdate. Whether this class, holding a target it cannot
///                        see, aims at the point the enemy must cross to come back into
///                        view (botSuppressSpot) rather than at the stale last-seen
///                        position. Costs an A* call, so it is opt-in per class.
///   BOT_CP_AIM_ERR       botCombatUpdate. Multiplier on this class's angular aim error,
///                        applied to botAimErrorDeg and botAimConeDeg together. 1 is the
///                        tier's own number and is the default.
///   BOT_CP_AIM_SETTLE    botCombatUpdate. Multiplier on BOT_AIM_SETTLE_DEG - how nearly
///                        the slew has to have caught up with the solved aim before the
///                        trigger is allowed. Above 1 is a class that shoots while still
///                        turning.
///   BOT_CP_CLOSE_IN      botInputUpdate. How near this class wants to be before it stops
///                        walking its route and fights, in px. 0 - the default - means
///                        stand and fight where you are.
///
/// ⚠️ The two aim fields are multipliers applied where the knob is USED, not written into
/// the knob by botSkillApply. Two reasons. botSkillApply runs once, from botAdd, so a
/// value baked in there goes stale the moment a bot's class changes; and the difficulty
/// tier and the class are meant to be independent axes - test_botskill asserts the tier's
/// published numbers land on the Player exactly, and they still do. This is the same
/// shape as BOT_CP_SPLASH, which is the class half of a test whose other half is the
/// difficulty knob botSplashAim.
///
/// The aim-error assignments, and why they are opposite:
///
///   Soldier (0.6)   Four rockets in a clip, a slow reload, and a projectile that does
///                   most of its damage on a direct hit. The solver behind it is already
///                   a full iterated intercept validated against a forward simulation
///                   (botAimLead), so what limits a Soldier is the error sprayed on top
///                   of a good answer. This is "make every shot count", and it is the
///                   whole of it - botLeadMode is already BOT_LEAD_FULL at every tier
///                   (M7 3.4), so there is nothing left to ungate there.
///   Heavy (1.6)     The opposite request, and it is not a handicap. The Minigun fires a
///                   continuous stream at 200 hp of health; a Heavy that lands every
///                   bullet is a hitscan sniper with no counterplay, and area denial does
///                   not want a tight cone. Paired with a loose settle (2.0), so it opens
///                   up while still turning rather than tracking silently and then
///                   deleting someone.
///   Sniper (0.3)    The tightest in the table, and it corrects an omission rather than
///                   expressing a preference. Aim error here is ANGULAR and the same at
///                   every distance, but botClassRange is 900 for this class against 500
///                   for a Heavy or Demoman and 220 for a Scout - so the identical number
///                   of degrees buys four times the linear miss, on the one class that is
///                   true hitscan and therefore has nothing else to blame. At tier 3 the
///                   spread on the first legal shot was +/-6.8 deg, which is +/-71 px at
///                   600 and +/-107 px at 900 against a body ~46 px tall: the shot lands a
///                   storey high about as often as it lands. Reported from play as snipers
///                   shooting well off target, often at the ceiling, and the upward half of
///                   a symmetric error is exactly what that looks like indoors. 0.3 brings
///                   the first legal shot to +/-2.0 deg, or +/-25 px at 700 - about one
///                   body width. Paired with BOT_CP_SETTLE_TIGHT for the reason given at
///                   that row: at this range the settle gate was the wider of the two.
///
///                   Still open, and deliberately not changed here: BOT_POTSHOT_MULT is
///                   1.7, so this class speculates out to 1530 px, where even 2 deg is
///                   +/-53 px. Tightening the cone does not make a potshot at half the map
///                   a good shot; if that reads badly it wants its own gate rather than a
///                   smaller multiplier for everyone.
///
/// The positioning modes, and the reasoning behind each assignment:
///
///   STANDOFF (Sniper, Heavy,  stand back from the objective, inside the weapon's reach and
///             Demoman)
///                             with line of sight to it. A Sniper's whole kit is a 900 px
///                             sightline and a charge that wants three and a half seconds
///                             of standing still; walking onto the point is the one thing
///                             that throws both away. A Heavy is 200 hp at run 0.8 - it is
///                             the worst class in the game at chasing an objective and the
///                             best at holding ground near one.
///   CHOKE (Engineer)          stand on the route between the objective and where the enemy
///                             will come from. A sentry is a static defence, so where it is
///                             built is most of its value, and building it on top of the
///                             thing it guards means it only fires once the point is already
///                             being taken.
///   FLANK (Spy)               stand near the objective but out of sight of it. The Spy is
///                             the one class whose kit is entirely about arriving from a
///                             direction nobody is watching, and a cloaked Spy walking up
///                             the same corridor as its team is a Spy wasting a cloak.
///
/// A class with no positioning opinion returns BOT_SPOT_NONE and gets the shared behaviour,
/// which is the right answer for the classes whose job is to reach the objective: a Scout
/// caps at capStrength 2, twice as fast as anyone else, and standing it off from the point
/// would be turning off the single best reason to have one.

var class, field;

class = argument0;
field = argument1;

switch(field)
{
    case BOT_CP_POTSHOT:
        if(class == CLASS_PYRO)
            return 0;
        if(class == CLASS_MEDIC)
            return 0;
        return 1;

    case BOT_CP_HEALS:
        if(class == CLASS_MEDIC)
            return 1;
        return 0;

    case BOT_CP_SPLASH:
        if(class == CLASS_SOLDIER)
            return 1;
        if(class == CLASS_DEMOMAN)
            return 1;
        return 0;

    case BOT_CP_SPECIAL_FIRE:
        if(class == CLASS_MEDIC)
            return 1;
        return 0;

    case BOT_CP_AIRJUMP:
        if(class == CLASS_SCOUT)
            return 1;
        return 0;

    case BOT_CP_FOLLOW:
        if(class == CLASS_MEDIC)
            return 1;
        return 0;

    case BOT_CP_DEFEND_EVERY:
        // Keen: a sentry is a fixed emplacement, and 200 hp at run 0.8 is ground-holding
        // rather than objective-running.
        if(class == CLASS_ENGINEER)
            return BOT_DEFEND_KEEN;
        if(class == CLASS_HEAVY)
            return BOT_DEFEND_KEEN;
        // Averse: capStrength 2 makes the Scout the fastest capper in the game, and a Spy
        // standing next to its own flag is a Spy doing a job any class could do.
        if(class == CLASS_SCOUT)
            return BOT_DEFEND_AVERSE;
        if(class == CLASS_SPY)
            return BOT_DEFEND_AVERSE;
        return BOT_DEFEND_EVERY;

    case BOT_CP_SPOT_MODE:
        if(class == CLASS_SNIPER)
            return BOT_SPOT_STANDOFF;
        if(class == CLASS_HEAVY)
            return BOT_SPOT_STANDOFF;
        if(class == CLASS_ENGINEER)
            return BOT_SPOT_CHOKE;
        if(class == CLASS_SPY)
            return BOT_SPOT_FLANK;
        // The Demoman's Minegun sags ~178px over 500px, so its shots are worth most from
        // the far end of its band and worst point-blank, where its own blast radius is the
        // thing that kills it. It was BOT_SPOT_NONE for no stated reason. STANDOFF derives
        // its band from botClassRange and already exists, which is why this is a row in a
        // table rather than a new mode: the alternative was raising botClassMinBand for the
        // Demoman alone, and that constant means self-harm, not preference.
        if(class == CLASS_DEMOMAN)
            return BOT_SPOT_STANDOFF;
        return BOT_SPOT_NONE;

    case BOT_CP_SUPPRESS:
        // Only the Heavy, and only because the case was measured before it was built
        // (botSuppressSpot's header carries the numbers). A Minigun is the one weapon in
        // the game whose whole job can be denying a doorway nobody is standing in yet;
        // for everything else this would be an A* call per blind target to make a shot
        // that was going to be wasted either way. M9 §9.5 is the reason that matters -
        // twelve bots is not far from the 33.3ms frame.
        if(class == CLASS_HEAVY)
            return 1;
        return 0;

    case BOT_CP_AIM_ERR:
        if(class == CLASS_SOLDIER)
            return BOT_CP_AIM_ERR_TIGHT;
        if(class == CLASS_HEAVY)
            return BOT_CP_AIM_ERR_LOOSE;
        if(class == CLASS_SNIPER)
            return BOT_CP_AIM_ERR_SNIPER;
        return 1;

    case BOT_CP_AIM_SETTLE:
        // Area denial does not want to wait for the slew to catch up at all.
        if(class == CLASS_HEAVY)
            return BOT_CP_SETTLE_LOOSE;
        // The Sniper is the opposite end of the same argument - see BOT_CP_AIM_ERR above.
        // Tightening the error alone would have bought nothing, because the settle gate is
        // the wider of the two at this class's range: BOT_AIM_SETTLE_DEG is a flat 3 deg,
        // which is 47 px at 900 and would have swamped a 0.3 error multiplier whole.
        if(class == CLASS_SNIPER)
            return BOT_CP_SETTLE_TIGHT;
        return 1;

    case BOT_CP_CLOSE_IN:
        // The distance this class wants to be at before it stops walking and fights, for
        // the engage hold in botInputUpdate. 0 is "no opinion": hold wherever the hold
        // caught you, which is right for everyone whose weapon already reaches across its
        // whole attention band.
        //
        // Only the Pyro, and it is not a preference - without this row the engage hold makes
        // the Pyro strictly worse. botClassRange is 200 for this class deliberately, so it
        // keeps tracking a target while it closes, but BOT_FLAME_REACH is 165 and
        // botClassKeys refuses the trigger past it. A hold that fires at 200 therefore stops
        // the Pyro 35 px short of being able to shoot at all, and it stands there. Closing
        // to the reach and then holding is what the 200 was for in the first place.
        if(class == CLASS_PYRO)
            return BOT_FLAME_REACH;
        return 0;

    case BOT_CP_SPOT_HIGH:
        // A Sniper values height more than anything else does: elevation is what turns a
        // long sightline into one nobody can walk out of. A Heavy wants it for the same
        // reason at a shorter range, an Engineer only mildly - a sentry's value is the
        // corridor it covers, not the storey it stands on - and a Spy not at all, since a
        // flank is about being unseen rather than about being above.
        if(class == CLASS_SNIPER)
            return BOT_SPOT_HIGH_SNIPER;
        if(class == CLASS_HEAVY)
            return BOT_SPOT_HIGH_BONUS;
        if(class == CLASS_ENGINEER)
            return BOT_SPOT_HIGH_BONUS / 2;
        return 0;
}

return 0;
