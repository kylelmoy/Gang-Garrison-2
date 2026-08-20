/// botInputUpdate(player)
/// Applies one bot's input for this virtual tick, mirroring the INPUTSTATE case in
/// processClientCommands.gml - but a bot has no socket to read a command from, so this
/// writes keyState/aimDirection onto its Character directly.
///
/// Two cadences, deliberately different. Aim and target re-evaluate only every
/// decisionPeriod ticks, staggered per bot, so aim visibly snaps rather than tracking
/// continuously - that is the whole difficulty knob until milestone 6 builds a real
/// one. Movement re-decides every single tick: a missed jump window is a bot standing
/// at the edge of a gap forever, and there is nothing human-looking about that.
///
/// The two halves are ORed into one keyState. They cannot conflict - one owns ATTACK,
/// the other LEFT/RIGHT/JUMP/DOWN - so the bot shoots while it walks, exactly as a
/// player does.
///
/// event_user(1) still fires every tick regardless, so pressedKeys/releasedKeys edge
/// detection keeps working in between decisions (F3). The path follower depends on it:
/// Character jumps on the rising edge of $80, not on the bit being held.
///
/// Where to aim, once a target is picked, is botAimSolve's job: almost every GG2
/// projectile falls, so a straight point_direction at the target shoots high at range
/// on nearly every weapon in the game.
///
/// A third, coarser cadence decides *where* to walk: botObjectiveUpdate (M6) reads the
/// game mode's objective and calls botSetGoal when it changes. Run it before
/// botPathKeys so a freshly issued goal is already what this tick's movement plans
/// against, instead of one tick behind.

var player, char, decisionPeriod, tick, navKeys;
player = argument0;
char = player.object;
if(char == -1)
{
    botPathFree(player);
    exit;
}

decisionPeriod = 15;
tick = frame;

if((tick + player) mod BOT_OBJECTIVE_PERIOD == 0)
    botObjectiveUpdate(player);

navKeys = botPathKeys(player);

with(char)
{
    if((tick + player) mod decisionPeriod == 0)
    {
        var target;
        target = botFindTarget(id);

        if(target != noone)
        {
            aimDirection = botAimSolve(id, target);
            netAimDirection = aimDirection*65536/360;
            player.botAttackKeys = KEY_ATTACK;
        }
        else
            player.botAttackKeys = 0;
    }

    keyState = player.botAttackKeys | navKeys;

    event_user(1);
}
