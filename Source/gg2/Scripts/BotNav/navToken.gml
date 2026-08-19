/// navToken(str, index)
/// Returns the index-th space separated token of str, 1 based, or "" if there are
/// fewer than that many. GM8 has no string split, and the cache header is the only
/// place this feature needs one.

var str, want, seen, start, i, ch, len;
str = argument0;
want = argument1;

len = string_length(str);
seen = 0;
start = 0;

for(i = 1; i <= len + 1; i += 1)
{
    if(i > len)
        ch = " ";
    else
        ch = string_char_at(str, i);

    if(ch == " ")
    {
        if(start > 0)
        {
            seen += 1;
            if(seen == want)
                return string_copy(str, start, i - start);
            start = 0;
        }
    }
    else
    {
        if(start == 0)
            start = i;
    }
}

return "";
