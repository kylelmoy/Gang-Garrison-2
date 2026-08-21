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
/// event_user(1) still fires every tick regardless, so pressedKeys/releasedKeys edge
/// detection keeps working in between decisions (F3). Two things depend on it: the path
/// follower jumps on the rising edge of KEY_JUMP, not on the bit being held, and a Spy
/// cloaks on the rising edge of KEY_SPECIAL.

var player, char, tick, navKeys, fireKeys;
player = argument0;
char = player.object;
if(char == -1)
{
    botPathFree(player);
    exit;
}

tick = frame;

if((tick + player) mod BOT_OBJECTIVE_PERIOD == 0)
    botObjectiveUpdate(player);

navKeys = botPathKeys(player);
fireKeys = botCombatUpdate(player);

with(char)
{
    keyState = fireKeys | navKeys;

    event_user(1);
}
