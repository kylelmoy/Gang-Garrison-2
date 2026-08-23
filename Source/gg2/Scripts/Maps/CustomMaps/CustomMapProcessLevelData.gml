// - Create all instances
// - Create the walkmask sprite

// argument0: the leveldata string
// argument1: the filename of the walkmask sprite


    var entityString, walkmaskString, walkmaskSurface;
    var a, b;
    var ENTITYTAG, ENDENTITYTAG, DIVIDER;
    ENTITYTAG = "{ENTITIES}";
    ENDENTITYTAG = "{END ENTITIES}";
    DIVIDER = chr(10);
    
    // Load the walkmask into a sprite
    if (room == BuilderRoom) {
        background_replace(BuilderWMB, argument1, true, false);
        background_xscale[1] = 6;
        background_yscale[1] = 6;
    } else {
        if(global.CustomMapCollisionSprite != -1) sprite_delete(global.CustomMapCollisionSprite);
        global.CustomMapCollisionSprite = sprite_add(argument1, 1, true, false, 0, 0);

        // This line is the only moment in the game at which a map's collision geometry
        // comes into existence, so it is also the only honest definition of "a map was
        // loaded". navServerTick reloads the bot nav cache whenever this counter moves,
        // which is what makes re-loading the SAME map pick up a regenerated graph -
        // navCacheKey cannot notice that, since the key is the map's identity and the
        // map's identity has not changed. See navServerTick for why that matters.
        if(!variable_global_exists("navMapGen")) global.navMapGen = 0;
        global.navMapGen += 1;
    }
    
    // grab the entity data
    a = string_pos(ENTITYTAG, argument0);
    b = string_pos(ENDENTITYTAG, argument0);
    if(a == 0 || b == 0) {
      show_message("Error: This file does not contain valid level data.");
      return false;
    }
    entityString = string_copy(argument0, a + string_length(ENTITYTAG) + string_length(DIVIDER), b - a - string_length(ENTITYTAG) - string_length(DIVIDER) - 1);
    
    CustomMapCreateEntitiesFromEntityData(entityString);
    return true;

