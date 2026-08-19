/// botReteamAll()
/// Assigns every bot a team and class after a full map change (bots have no team-select
/// menu to answer themselves), broadcasting each change like a real pick would.

var i, player, team, class;
for(i = 0; i < ds_list_size(global.players); i += 1)
{
    player = ds_list_find_value(global.players, i);
    if(player.isBot)
    {
        team = botPickTeam();
        class = checkClasslimits(player, team, irandom(8));
        player.team = team;
        player.class = class;
        ServerPlayerChangeteam(i, team, global.sendBuffer);
        ServerPlayerChangeclass(i, class, global.sendBuffer);
    }
}
