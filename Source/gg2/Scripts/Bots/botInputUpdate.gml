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
/// ⚠️ There is now exactly ONE exception to that, and it is negotiated here rather than
/// taken: a **rocket jump**. NAV_EDGE_ROCKETJUMP is an arc that only exists because the
/// bot fires a rocket at its own feet on the tick it jumps, so following one needs the
/// trigger (combat's) and the aim (combat's, and rewritten by it every single tick)
/// pointed somewhere combat would never choose.
///
/// botPathKeys does not reach into either. It sets player.botRocketAim and
/// player.botRocketFire and returns its own keys as usual; this script applies them after
/// BOTH halves have run and decided for themselves. That ordering is the whole design -
/// it keeps the two scripts independent, and it puts the one place they genuinely conflict
/// in the one script whose job is already to see both. It is also why the override is
/// written after the engage and back-off blocks below: those touch LEFT/RIGHT only, and a
/// rocket jump wants them left exactly as the follower set them.
///
/// On top of those sit two small movement behaviours that are neither route-following nor
/// firing policy, and that both belong here because here is the only place that can see
/// both halves at once:
///
///   dodge      (M7 4.3) jump when a rocket is incoming. One fired flat across open ground
///              cannot be dodged any other way.
///   engage     stop walking the route and fight an enemy that is in front of you.
///   back off   (M7 2.4/3.2) walk away from an enemy that is inside this class's minimum
///              band. Two bots that walk into each other otherwise stand nose to nose
///              with a degenerate aim solve and neither can shoot; and a Soldier pinned
///              at point-blank range cannot fire at all without killing itself.
///
/// The engage hold is the newest of the three and the one that changes how the bots read
/// most, so the reasoning is worth stating. Before it, the two halves ORed above never
/// negotiated at all: botPathKeys contains no reference to botTarget, so a bot with a live
/// enemy in front of it kept walking its A* route and fired sideways as it went. Reported
/// from play as bots running past a player rather than engaging, which is exactly what the
/// code did - the only thing that had ever overridden route-following was the back-off, and
/// that fires inside 40 px.
///
/// Four things stop it deciding the round on its own, and each is load-bearing:
///
///   the carrier    a bot holding the intel never holds. A capture is the thing that ends a
///                  round, and a carrier that stops to duel is a round that does not end.
///   the objective  within BOT_ENGAGE_GOAL_NEAR of its own goal a bot keeps walking. Close
///                  to the point, taking the point beats winning the fight in front of it.
///   the clock      the hold expires BOT_ENGAGE_TICKS after the target was acquired. A
///                  firefight normally resolves well inside that; the cap is there for the
///                  one that does not - two bots either side of a gap, each visible to the
///                  other and neither able to finish it - which would otherwise be two bots
///                  standing still for the rest of the round, and with twelve of them, a map
///                  that quietly stops playing. Measured from botTargetAt rather than from
///                  when the hold began, so re-acquiring is what buys another window and a
///                  bot cannot renew its own stalemate by looking away and back.
///   the ground     a class with a BOT_CP_CLOSE_IN walks at its target instead of holding,
///                  and that is the first press in this file that no route validated. It
///                  goes through botStepSafe for that reason.
///
/// KEY_JUMP is edge-triggered in Character's Begin Step (pressedKeys & $80), which is what
/// makes ORing the dodge in safe: a press cannot double a jump the follower already wants,
/// and the ground gate keeps it out of a planned arc without needing to know anything
/// about that arc.
///
/// event_user(1) still fires every tick regardless, so pressedKeys/releasedKeys edge
/// detection keeps working in between decisions (F3). Two things depend on it: the path
/// follower jumps on the rising edge of KEY_JUMP, not on the bit being held, and a Spy
/// cloaks on the rising edge of KEY_SPECIAL.

var player, char, tick, navKeys, fireKeys, evadeKeys, alive;
var subject, minBand, mates, holding, engaging, closeIn, subjDist, goalDist, stepDir;

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

// botGoalLocked suspends this for one bot, so that a goal set from outside stays set.
// Nothing in the game sets it; see Player's Create event for what it is for.
if(!player.botGoalLocked and (tick + player) mod BOT_OBJECTIVE_PERIOD == 0)
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
    // Wait for company, but not for a crowd. BOT_REGROUP_MATES is 1 rather than 2 so the
    // unit that forms is a pair: with 2 every bot on a freshly spawned team satisfied the
    // test on the same frame and the whole team left as one body, which is the clumping
    // reported from play - and a team moving as one body has one goal, so it also has one
    // decision to make and nothing to break a tie with.
    //
    // BOT_REGROUP_CROWD is the other end of the same idea. A bot that spawns into a pile
    // that is already big enough does not add itself to it; it stops holding at once and
    // goes, which is what keeps the hold from compounding into the whole roster.
    if(mates >= BOT_REGROUP_CROWD)
        player.botRegroupUntil = 0;
    else if(mates < BOT_REGROUP_MATES)
        holding = true;
    else
        player.botRegroupUntil = 0;
}

// WARNING: only with both feet on the ground, and never part-way through an edge the graph
// validated. Stripping LEFT/RIGHT while the follower is tracking a jump arc is not a pause,
// it is a different jump: botPathKeys is holding a position-per-tick trajectory that needs a
// key almost every tick to stay on, and a bot that stops pressing at the apex lands short of
// where the arc was proved to reach. Reported from play as "bot seems to stop trying to move
// left mid-jump - might be interacting with the stay-in-a-group behaviour", which is exactly
// what it was: the hold was applied to whatever botPathKeys returned, with no idea whether
// the bot was walking or airborne. Same reasoning as every other behaviour here (M6 part 5),
// and this one simply predated the rule.
//
// ⚠️ And clear the stuck counter, which is the other half of the same mistake. botPathKeys
// runs its detector on the keys it INTENDS to press - `if(!moved and keys != 0)` - and then
// returns them for this line to throw away. So a bot in the regroup hold is standing still
// on purpose while the follower believes it is pressing a direction and going nowhere, and
// every BOT_STUCK_TICKS it blacklists one of its own spawn room's exits. A 90-tick hold is
// seven of those windows, which is why the census finds one spawn node with five or six
// exits banned twelve ticks apart, on eight different maps. Measured 2026-08-23: the
// position trace through such a window decays 0.49, 0.42, 0.37, 0.32, 0.27, 0.24, 0.20
// px/tick - pure friction, no input, and every tick of it under the detector's half-pixel
// floor. The counter is cleared here rather than gated inside botPathKeys because this is
// the line that decides the bot is not trying to move, and the detector's question is only
// meaningful about keys that were actually delivered.
if(holding and char.onground and !player.botFlyingEdge)
{
    navKeys = navKeys & ~(KEY_LEFT | KEY_RIGHT);
    player.botStuckTicks = 0;
}

// Dodge an incoming rocket (M7 4.3). One fired flat across open ground cannot be dodged
// without jumping, and a bot that just stands there reads as having no self-preservation
// at all. Grounded only, which keeps it out of every planned jump arc, and never throttled,
// because it is a reflex to a thing that is actually in the air.
//
// botRocketDodge, not a proximity test: it flies both futures out and presses only when the
// standing bot is hit and the jumping one is not. A radius test cannot distinguish a rocket
// coming in at the knees (jump) from one passing over the head (jumping is what puts the bot
// in front of it), and getting that backwards made a bot a guaranteed hit for anyone who
// aimed high.
//
// This is the *only* thing that presses JUMP outside the path follower. The voluntary combat
// hops that used to sit here - a blocked-shot peek, an ambient fidget while in a fight, and
// the Scout's mid-air second jump - have been removed. Between them they fired often enough,
// and precisely in the situation where botPathKeys has already arrived and is returning no
// movement keys at all, that bots in a firefight read as stuck in place jumping.
evadeKeys = 0;
if(char.onground and botRocketDodge(char))
    evadeKeys = KEY_JUMP;

// Stand and fight, instead of walking past (see the header for why each gate is here).
//
// The same onground and !botFlyingEdge guard as the regroup hold above, for the same
// reason: stripping LEFT/RIGHT part-way through a validated jump arc is not a pause, it is
// a different jump. And the same botStuckTicks clear, for the other half of that same
// mistake - botPathKeys runs its stuck detector on the keys it INTENDS to press, so a bot
// deliberately standing still looks to the detector like a bot pressing a direction and
// going nowhere, and it starts blacklisting the edges under its own feet.
subject = player.botTarget;
engaging = false;
subjDist = 0;
if(subject != noone and char.onground and player.botVisible and !player.botFlyingEdge
   and !char.intel)
{
    if(instance_exists(subject))
    {
        subjDist = point_distance(char.x, char.y, subject.x, subject.y);
        goalDist = BOT_ENGAGE_GOAL_NEAR + 1;
        if(player.botHasGoal)
            goalDist = point_distance(char.x, char.y, player.botGoalX, player.botGoalY);

        if(subjDist <= botClassRange(player.class)
           and goalDist > BOT_ENGAGE_GOAL_NEAR
           and tick - player.botTargetAt <= BOT_ENGAGE_TICKS)
            engaging = true;
    }
}

if(engaging)
{
    navKeys = navKeys & ~(KEY_LEFT | KEY_RIGHT);
    player.botStuckTicks = 0;

    // A class that has to be nearer than its attention band before it can shoot walks at
    // the target rather than stopping where the hold caught it. Only the Pyro today; the
    // row explains itself in botClassProfile.
    closeIn = botClassProfile(player.class, BOT_CP_CLOSE_IN);
    if(closeIn > 0 and subjDist > closeIn)
    {
        stepDir = 1;
        if(subject.x < char.x)
            stepDir = -1;
        if(botStepSafe(char, stepDir))
        {
            if(stepDir > 0)
                navKeys |= KEY_RIGHT;
            else
                navKeys |= KEY_LEFT;
        }
    }
}

// Back away from anything inside this class's minimum band (M7 2.4/3.2). Only from a
// target the bot can actually see - a remembered one behind a wall (M7 3.8) is not a
// reason to retreat - and only on the ground, which keeps it out of every planned arc for
// the same reason the dodge is gated that way. It replaces the follower's horizontal keys
// rather than being ORed with them, since pressing both directions at once is pressing
// neither.
//
// After the engage hold, and it has to stay that way: the two disagree only between a
// class's minimum band and its close-in distance, and there the retreat is right. A Pyro
// closing on someone already standing in its own face should back off first and close
// second, not alternate.
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

// The rocket-jump hand-off (see the header). botPathKeys sets these on the one tick it
// wants to take off, and clears them on every other tick and every early return, so this
// is inert for every bot that is not leaving the ground on a NAV_EDGE_ROCKETJUMP edge
// right now.
//
// The aim is written AFTER botCombatUpdate rather than instead of it, and it SNAPS. Both
// matter:
//
//   after   botCombatUpdate writes char.aimDirection unconditionally, in two separate
//           branches, on every tick. Asking it politely to make an exception would mean a
//           third branch in a script that has no idea a nav graph exists. Overwriting the
//           value it just wrote is one line and cannot be got wrong.
//
//   snaps   player.botAimDir is the slewed aim and botTurnRate is 8 degrees a tick at the
//           top tier, so turning from level to straight down is eleven ticks of a bot
//           standing motionless staring at the floor before every single rocket jump.
//           That is not what tracking lag is for and it is not what a player looks like:
//           a player flicks the crosshair down and fires in the same motion. botAimDir is
//           moved with it rather than around it, so the slew resumes from where the aim
//           actually is once the jump is over, instead of snapping back on the next tick.
//
// ⚠️ Character's Begin Step reads aimDirection when it fires the weapon, and reads
// keyState for the ATTACK bit, in that same event and on this same tick - the ordering
// every other bot weapon already depends on. Rocketlauncher/User Event 3 spawns the rocket
// 20px along aimDirection, so the aim must be down BEFORE the trigger is seen, which is
// exactly what writing both here achieves.
if(player.botRocketAim >= 0)
{
    player.botAimDir = player.botRocketAim;
    player.botAimWant = player.botRocketAim;
    with(char)
    {
        aimDirection = player.botRocketAim;
        netAimDirection = aimDirection*65536/360;
    }
    if(player.botRocketFire)
        fireKeys |= KEY_ATTACK;
}

with(char)
{
    keyState = fireKeys | navKeys | evadeKeys;

    event_user(1);
}
