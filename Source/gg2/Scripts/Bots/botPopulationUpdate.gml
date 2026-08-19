/// botPopulationUpdate()
/// Server-side population manager: finalizes bots previously marked for removal (on death
/// or timeout), then adds or removes bots to reach the configured target count.

if(!global.botsEnabled)
    exit;

var changed;
changed = false;

with(Player)
    if(isBot and botRemovalPending and (object == -1 or current_time >= botRemovalDeadline))
    {
        botRemove(id);
        changed = true;
    }

var humans, botCount, target;
humans = getNumberOfOccupiedSlots();
botCount = 0;
with(Player)
    if(isBot)
        botCount += 1;

if(humans < global.botMinHumans)
    target = 0;
else
    target = min(global.botMaxBots, max(0, global.botFillToPlayers - humans));

if(botCount < target and spawningAllowed())
{
    repeat(target - botCount)
    {
        global.botNameCounter += 1;
        botAdd(botPickTeam(), irandom(8), global.botNamePrefix + string(global.botNameCounter));
    }
    changed = true;
}
else if(botCount > target)
{
    var toRemove;
    toRemove = botCount - target;
    with(Player)
    {
        if(toRemove > 0 and isBot and !botRemovalPending)
        {
            if(!global.botRemoveOnDeath or object == -1)
            {
                botRemove(id);
                changed = true;
            }
            else
            {
                botRemovalPending = true;
                botRemovalDeadline = current_time + global.botRemoveTimeoutSeconds*1000;
            }
            toRemove -= 1;
        }
    }
}

if(changed)
    sendLobbyRegistration();
