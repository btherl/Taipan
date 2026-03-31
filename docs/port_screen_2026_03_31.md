### Authentic Apple 2 port screen layout

The below is the exact layout, with some notes.

"===" is a combined bottom and top box horizontal bar.
"|" is a box vertical bar, "-" box bottom horizontal bar, "\_" is a box top horizontal bar
"+" is a box corner, you can infer which type of corner it is from the position.

The first line is horizontally centered.  All other lines are fixed position.

The top 16 lines have fixed layout and information.  The bottom 8 lines are reserved for dialogue and so on.

Line 1 begins immediately below and ends with the full width line:
        Firm: ABCDEFGH, Hong Kong
+__________________________+
|Hong Kong Warehouse       |    Date
|   Opium   0       In use:| 15 Jan 1860
|   Silk    0        0     |
|   Arms    0       Vacant:|  Location
|   General 0        10000 |  Hong Kong
+==========================+
|Hold 60        Guns 0     |    Debt
|   Opium   0              |    5000
|   Silk    0              |
|   Arms    0              | Ship status
|   General 0              | Perfect: 100
+--------------------------+
Cash:400            Bank:0
_________________________________________

## Static data

The Firm name and firm location are static, it always shows Hong Kong.

## Inverted text

The month from the date is always inverted, black text on white background.

Location and debt are also inverted text.

Ship status is in inverted text once below a specific level. (TBC)

Ship status is centered, but when it is inverted, then the entire block is inverted, 11 characters in total.  Not just the text.

## Ship status

Examples:
Perfect: 100
  Poor: 25      (Inverted text, full 11 character length)

Full rules:
Critical: 0-19  (Inverted text)
Poor: 20-39     (Inverted text)
Fair: 40-59
Good: 60-79
Prime: 80-99
Perfect: 100

## Location

The location is horizontally centered always.  For example, a short port name like Manila will have the "M" aligned with the "o" of "Location".  A longer name like Hong Kong will have the "H" aligned with the "L" of Location.

While travelling, location shows "At sea", also centered.

## Display of high numbers

Numbers under 1 million are whosn as plain integers.
1 million and above are shown with 3-4 significant digits plus a suffix (Thousand, Million, Billion, Trillion)

Refer to BASIC_ANNOTATED.txt for full details

## Bottom panel

Keep the bottom panel for existing dialogue.  In another phase we will rewrite all of this to match the original Apple II Hires version.
