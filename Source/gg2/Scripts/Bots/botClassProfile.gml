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
///
/// The positioning modes, and the reasoning behind each assignment:
///
///   STANDOFF (Sniper, Heavy)  stand back from the objective, inside the weapon's reach and
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
        return BOT_SPOT_NONE;

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
