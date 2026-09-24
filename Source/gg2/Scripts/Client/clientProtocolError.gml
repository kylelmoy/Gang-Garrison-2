// Called when the client can no longer make sense of the server's message stream.
// Messages have no framing, so once one has been read with the wrong length
// every following byte is misread and there is no way to resynchronize.
// The message ids received last are shown, because the message that caused the
// problem is usually several messages before the one that noticed it.
//
// Sets global.serverStreamBroken; code that detects the error from inside a
// nested deserializer must exit, and its callers must check the flag and exit too,
// so that nothing else is read from the stream.
//
// argument0: description of what went wrong

var text, i, first;

if(global.serverStreamBroken)
    exit;
global.serverStreamBroken = true;

text = argument0 + "##Last messages received from the server, oldest first:#";
first = max(0, global.recentServerMessageCount - RECENT_SERVER_MESSAGES);
for(i = first; i < global.recentServerMessageCount; i += 1)
{
    if(i > first)
        text += ", ";
    text += string(global.recentServerMessages[i mod RECENT_SERVER_MESSAGES]);
}

promptRestartOrQuit(text);
