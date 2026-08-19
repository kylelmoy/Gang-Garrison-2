var noOfSlots;
noOfSlots = ds_list_size(global.players);
if(global.dedicatedMode)
    noOfSlots -= 1;
with(Player)
    if(isBot)
        noOfSlots -= 1;
with(JoiningPlayer)
    if(occupiesSlot)
        noOfSlots += 1;
return noOfSlots;
