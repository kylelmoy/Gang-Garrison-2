/// botAdd(team, class, name)
/// Creates a bot Player and joins it to the game exactly like a real client would:
/// roster insertion, PLAYER_JOIN/CHANGETEAM/CHANGECLASS broadcasts, then queues a spawn.
/// Returns the new Player instance.

var team, class, name, player, playerId;
team = argument0;
class = argument1;
name = argument2;

player = instance_create(0,0,Player);
player.isBot = true;
player.name = name;

playerId = ds_list_size(global.players);
ds_list_add(global.players, player);
ServerPlayerJoin(player.name, global.sendBuffer);

class = checkClasslimits(player, team, class);
player.team = team;
player.class = class;
ServerPlayerChangeteam(playerId, player.team, global.sendBuffer);
ServerPlayerChangeclass(playerId, player.class, global.sendBuffer);

if(team != TEAM_SPECTATOR)
    player.alarm[5] = 1; // Will spawn in the same step (between Begin Step and Step)

return player;
