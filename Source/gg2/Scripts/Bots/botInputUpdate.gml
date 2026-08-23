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
/// On top of those sit two small movement behaviours that are neither route-following nor
/// firing policy, and that both belong here because here is the only place that can see
/// both halves at once:
///
///   dodge      (M7 4.3) jump when a rocket is incoming. One fired flat across open ground
///              cannot be dodged any other way.
///   back off   (M7 2.4/3.2) walk away from an enemy that is inside this class's minimum
///              band. Two bots that walk into each other otherwise stand nose to nose
///              with a degenerate aim solve and neither can shoot; and a Soldier pinned
///              at point-blank range cannot fire at all without killing itself.
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
if(holding and char.onground and !player.botFlyingEdge)
    navKeys = navKeys & ~(KEY_LEFT | KEY_RIGHT);

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
