/// botInputUpdate(player)
/// Applies one bot's input for this virtual tick, mirroring the INPUTSTATE case in
/// processClientCommands.gml - but a bot has no socket to read a command from, so this
/// writes keyState/aimDirection onto its Character directly.
///
/// Aim/target only re-evaluate every decisionPeriod ticks, staggered per bot, so aim
/// visibly snaps rather than tracking continuously. event_user(1) still fires every tick
/// so pressedKeys/releasedKeys edge detection keeps working correctly in between.

var player, char, decisionPeriod, tick;
player = argument0;
char = player.object;
if(char == -1)
    exit;

decisionPeriod = 15;
tick = frame;

with(char)
{
    if((tick + player) mod decisionPeriod == 0)
    {
        var target;
        target = botFindTarget(id);

        if(target != noone)
        {
            aimDirection = point_direction(x, y, target.x, target.y);
            netAimDirection = aimDirection*65536/360;
            keyState = KEY_ATTACK;
        }
        else
            keyState = 0;
    }

    event_user(1);
}
