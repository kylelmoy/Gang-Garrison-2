/// botInputUpdate(player)
/// Applies one bot's input for this virtual tick, mirroring the INPUTSTATE case in
/// processClientCommands.gml - but a bot has no socket to read a command from, so this
/// writes keyState/aimDirection onto its Character directly.
///
/// Three cadences, deliberately different, coarsest first:
///
///   every BOT_OBJECTIVE_PERIOD  botObjectiveUpdate reads the game mode's objective and
///                               issues a goal when it changes. Run before botPathKeys so
///                               a freshly issued goal is what this tick's movement plans
///                               against, rather than being one tick behind.
///   every tick                  botPathKeys follows the route. A missed jump window is a
///                               bot standing at the edge of a gap forever, and there is
///                               nothing human-looking about that.
///   every tick                  botCombatUpdate aims and shoots - but only per-tick in
///                               the sense that it decides per tick; the gates inside it
///                               run on the bot's own difficulty cadences.
///
/// The two halves are ORed into one keyState. They cannot conflict - combat owns ATTACK
/// and SPECIAL, navigation owns LEFT/RIGHT/JUMP/DOWN - so the bot shoots while it walks,
/// exactly as a player does.
///
/// On top of those sit four small movement behaviours that are neither route-following
/// nor firing policy, and that all belong here because here is the only place that can
/// see both halves at once:
///
///   dodge      (M7 4.3) jump when something dangerous is incoming. A rocket fired flat
///              across open ground cannot be dodged any other way.
///   fidget     (M7 4.2) a low-rate random hop while in a fight. Cheap, and
///              disproportionately human-looking: nothing else in the model makes a
///              bot's feet leave the ground for no tactical reason.
///   air jump   (M7 4.1) a Scout's second, mid-air jump - the evasion half of the
///              feature. The navigation half (a NAV_EDGE_DOUBLEJUMP generator) is a
///              graph question and is not this.
///   back off   (M7 2.4/3.2) walk away from an enemy that is inside this class's minimum
///              band. Two bots that walk into each other otherwise stand nose to nose
///              with a degenerate aim solve and neither can shoot; and a Soldier pinned
///              at point-blank range cannot fire at all without killing itself.
///
/// KEY_JUMP is edge-triggered in Character's Begin Step (pressedKeys & $80), which is
/// what makes ORing the first three in safe: a press cannot double a jump the follower
/// already wants, and the ground gate on the first two keeps them out of a planned arc
/// without needing to know anything about that arc. The air jump is the one that *does*
/// need to know, because it fires precisely when the bot is airborne - hence
/// botFlyingEdge, which botPathKeys sets while it is flying a trajectory the graph
/// validated, and which any nudge in the air would permanently ruin (M6 part 5).
///
/// event_user(1) still fires every tick regardless, so pressedKeys/releasedKeys edge
/// detection keeps working in between decisions (F3). Two things depend on it: the path
/// follower jumps on the rising edge of KEY_JUMP, not on the bit being held, and a Spy
/// cloaks on the rising edge of KEY_SPECIAL.

var player, char, tick, navKeys, fireKeys, evadeKeys, alive;
var subject, minBand, mates, holding;

player = argument0;
char = player.object;
if(char == -1)
{
    botPathFree(player);
    player.botAliveLast = false;
    exit;
}

tick = frame;

// Arrive in clumps rather than in single file (M7 5.1). Bots stream toward the objective
// one at a time and get killed piecemeal because each one leaves spawn the instant it can;
// a human waits a moment for whoever else is about to spawn. The hold is short and it is
// randomised per life, so a whole team does not leave on the same frame either - and it
// ends early the moment enough team-mates are actually nearby, which is the condition it
// is really waiting for. Only movement is held: the bot still aims, still shoots and
// still dodges, so it never reads as frozen.
alive = (char.hp > 0);
if(alive and !player.botAliveLast)
    player.botRegroupUntil = tick + random(BOT_REGROUP_TICKS);
player.botAliveLast = alive;

if((tick + player) mod BOT_OBJECTIVE_PERIOD == 0)
    botObjectiveUpdate(player);

navKeys = botPathKeys(player);
fireKeys = botCombatUpdate(player);

holding = false;
if(tick < player.botRegroupUntil)
{
    mates = 0;
    with(Character)
    {
        if(id != char and team == char.team and hp > 0)
        {
            if(point_distance(x, y, char.x, char.y) <= BOT_REGROUP_RADIUS)
                mates += 1;
        }
    }
    if(mates < BOT_REGROUP_MATES)
        holding = true;
    else
        player.botRegroupUntil = 0;
}

if(holding)
    navKeys = navKeys & ~(KEY_LEFT | KEY_RIGHT);

evadeKeys = 0;
if(char.onground)
{
    player.botAirJumpUsed = false;

    // A rocket fired flat across open ground cannot be dodged without jumping, and a bot
    // that just stands there reads as having no self-preservation at all - checked first
    // and widened to any direction, since you dodge things behind you too (M7 4.3).
    if(botIncomingProjectile(char, BOT_AIRBLAST_RANGE, true))
        evadeKeys |= KEY_JUMP;
    // Jump when the shot is blocked (M7 4.4, the cheap fragment of it). Holding a target
    // the bot cannot currently see means something is between them - a lip, a crate, the
    // edge of a roof - and hopping is what a player does about that. It reproduces the
    // useful half of a jump-peek (get the shot over the obstacle) with no cover model at
    // all, and it costs nothing extra to ask: botVisible is already maintained every
    // perception tick by the target-memory window (M7 3.8), so there is no second
    // collision_line here. What it does *not* do is the deliberate return to cover, which
    // is the half that needs per-node sightlines and is still deferred.
    //
    // Rolled per tick rather than held. KEY_JUMP is edge-triggered, so a bit held down
    // for as long as the obstruction lasts produces exactly one jump and then a bot
    // standing there with the key pressed - the roll is what keeps releasing it, and a
    // ~15% chance a tick both bobs at about the rate a player does and gets the first hop
    // out inside a few frames.
    else if(player.botTarget != noone and !player.botVisible and random(1) < 0.15)
        evadeKeys |= KEY_JUMP;
    // A low-rate random hop while in a fight (M7 4.2), independent of whether anything is
    // actually incoming right now - cheap, and disproportionately human-looking: nothing
    // else in the model makes a bot's feet leave the ground for no tactical reason. ~1%
    // a tick averages one hop every three seconds of active combat.
    else if(player.botTarget != noone and random(1) < 0.01)
        evadeKeys |= KEY_JUMP;
}
else if(player.class == CLASS_SCOUT and !player.botFlyingEdge and !player.botAirJumpUsed)
{
    // The Scout's second jump, as evasion (M7 4.1): erratic by design, which is what makes
    // it hard to lead. Three gates, and each one is load-bearing:
    //
    //   canDoublejump/doublejumpUsed  the engine's own state (Character's Begin Step), so
    //                                 this never presses for a jump that cannot happen.
    //   vspeed > 0                    only on the way down. Partly because that is where a
    //                                 second jump buys the most height, and partly because
    //                                 several ticks have necessarily passed since the
    //                                 takeoff press - a press on the tick after that one
    //                                 would not be a rising edge and would do nothing.
    //   botFlyingEdge                 never while following a jump edge. The follower is
    //                                 flying a position-per-tick arc the graph validated,
    //                                 and any nudge in the air is permanent (M6 part 5).
    //
    // Once per airborne period, so an unlucky roll cannot spend it twice.
    if(char.canDoublejump and !char.doublejumpUsed and char.vspeed > 0)
    {
        if(player.botTarget != noone and random(1) < BOT_DOUBLEJUMP_CHANCE)
        {
            evadeKeys |= KEY_JUMP;
            player.botAirJumpUsed = true;
        }
    }
}

// Back away from anything inside this class's minimum band (M7 2.4/3.2). Only from a
// target the bot can actually see - a remembered one behind a wall (M7 3.8) is not a
// reason to retreat - and only on the ground, which keeps it out of every planned arc for
// the same reason the dodge is gated that way. It replaces the follower's horizontal keys
// rather than being ORed with them, since pressing both directions at once is pressing
// neither.
subject = player.botTarget;
if(subject != noone and char.onground and player.botVisible)
{
    if(instance_exists(subject))
    {
        minBand = botClassMinBand(player.class);
        if(minBand > 0 and point_distance(char.x, char.y, subject.x, subject.y) < minBand)
        {
            navKeys = navKeys & ~(KEY_LEFT | KEY_RIGHT);
            if(subject.x > char.x)
                navKeys |= KEY_LEFT;
            else
                navKeys |= KEY_RIGHT;
        }
    }
}

with(char)
{
    keyState = fireKeys | navKeys | evadeKeys;

    event_user(1);
}
