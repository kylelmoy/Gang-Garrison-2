// Opens a modal text prompt with OK and Cancel buttons, styled after Source's VGUI dialogs.
// argument0 - title
// argument1 - message shown above the text field; wraps to fit
// argument2 - text the field starts with
// argument3 - maximum length of the text, or 0 for no limit
// argument4 - GML code to run when the dialog closes: argument0 is true if the text was
//             accepted (OK or Enter) and false if cancelled (Cancel, the close button or
//             Escape), argument1 is the text, argument2 is argument5 passed through
// argument5 - any value the closing code needs, since it cannot see the caller's variables
// Returns the dialog instance.

var dialog;
dialog = instance_create(0, 0, InputDialog);
dialog.dialogTitle = argument0;
dialog.dialogMessage = argument1;
dialog.inputText = argument2;
dialog.maxLength = argument3;
dialog.onClose = argument4;
dialog.userData = argument5;
keyboard_string = argument2;
return dialog;
