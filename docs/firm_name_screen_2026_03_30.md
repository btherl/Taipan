### Adding Firm Name selection

We will be adding a screen to select Firm Name.


## Modern UI

In the modern UI, this can be done in whatever way suits the existing UI.

## Apple 2 UI

In the Apple 2 UI, I have a very specific way I want the Firm Name selection screen to look.  This is to exactly match the original Apple II Hires version.

There will be a 10 high, 40 wide box in the middle of the screen.  Since the screen is 40 wide and 24 characters tall, there will be 7 empty lines above, and 7 empty lines below the box.

Let's call the top line of the box "line 0"

Line 2 will have "     Taipan," being 5 spaces at the start
Line 4 will have " What will you name your" being 1 space at the start
Line 6 will be the text input prompt, "     Firm: " being 5 spaces at the start, and a text input of size 22 characters
Line 7 will be "           ----------------------" being 10 spaces at the start, followed by 22 dashes.  These dashes match where text can be entered by the user.

Text input will be in TaipanThickFont.  All other characters will be in TaipanStandardFont

This will be the first screen shown after selecting an interface style, for both UI.

Displaying the Firm name is out of scope for now, we will handle that after adding this screen.  Storing the firm name in data is IN scope.
