// argument0 - name of the next map
// argument1 - winning team
// argument2 - map area the next map starts in
// argument3 - buffer

write_ubyte(argument3, MAP_END);
write_ubyte(argument3, string_length(argument0));
write_string(argument3, argument0);
write_ubyte(argument3, argument1);
write_ubyte(argument3, argument2);
