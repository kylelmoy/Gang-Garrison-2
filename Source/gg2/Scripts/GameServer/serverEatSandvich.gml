/// serverEatSandvich(player, playerId)
/// The server side of a Heavy eating: check the preconditions, broadcast it, start the
/// animation that heals him.
///
/// Extracted from processClientCommands' OMNOMNOMNOM case so that a bot can eat. Like
/// zoom and build, it is a client command rather than a key bit, so pressing something
/// is not an option for a bot.

var player, playerId;

player = argument0;
playerId = argument1;

if(player.object == -1)
    exit;

if(!player.humiliated
    and !player.object.taunting
    and !player.object.omnomnomnom
    and player.object.canEat
    and player.class==CLASS_HEAVY)
{
    write_ubyte(global.sendBuffer, OMNOMNOMNOM);
    write_ubyte(global.sendBuffer, playerId);
    with(player.object)
    {
        omnomnomnom = true;
        omnomnomnomindex=0;
        omnomnomnomend=32;
        xscale=image_xscale;
    }
}
