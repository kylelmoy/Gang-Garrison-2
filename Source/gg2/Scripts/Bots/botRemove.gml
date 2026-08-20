/// botRemove(player)
/// Removes a bot from the roster and broadcasts its departure, mirroring the
/// disconnect path in GameServerBeginStep (removePlayer + ServerPlayerLeave).

var player, playerId;
player = argument0;
playerId = ds_list_find_index(global.players, player);

// Before removePlayer destroys the instance: the navigation layer's route list and
// blacklist are ds_ structures on the Player, and GM8 frees none of that with the
// instance. A server cycling bots would otherwise leak a couple per departure.
botNavRelease(player);

removePlayer(player);
ServerPlayerLeave(playerId, global.sendBuffer);
