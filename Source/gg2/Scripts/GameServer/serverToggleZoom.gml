/// serverToggleZoom(player, playerId)
/// The server side of a Sniper zooming: check the preconditions, broadcast it, apply it.
///
/// Extracted from processClientCommands' TOGGLE_ZOOM case so that a bot can zoom without
/// a socket to send itself a packet on. Zoom is not part of the input byte - it is its
/// own client command - so there is no key a bot could press instead, and duplicating
/// the case body in the bot code would leave two copies of the precondition to disagree.

var player, playerId;

player = argument0;
playerId = argument1;

if(player.object == -1)
    exit;

if(player.class != CLASS_SNIPER)
    exit;

write_ubyte(global.sendBuffer, TOGGLE_ZOOM);
write_ubyte(global.sendBuffer, playerId);
toggleZoom(player.object);
