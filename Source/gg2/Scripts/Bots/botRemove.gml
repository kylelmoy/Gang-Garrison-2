/// botRemove(player)
/// Removes a bot from the roster and broadcasts its departure, mirroring the
/// disconnect path in GameServerBeginStep (removePlayer + ServerPlayerLeave).

var player, playerId;
player = argument0;
playerId = ds_list_find_index(global.players, player);

removePlayer(player);
ServerPlayerLeave(playerId, global.sendBuffer);
