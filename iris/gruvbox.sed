# Aura (upstream default) -> gruvbox dark, hex for hex.
#
# IRIS has no theme setting -- the palette is hardcoded in
# integration/overlay.go -- so build.sh rewrites the colours before compiling.
# Comments must sit on their own lines; sed rejects trailing ones.

# border / scroll info / key hints / tag accents -> bright yellow
s/#a277ff/#fabd2f/gI

# accent + fuzzy-match highlight -> bright green
s/#61ffca/#b8bb26/gI

# muted (icons, dim text) -> gray
s/#6d6a7f/#928374/gI

# body text -> fg1
s/#edecee/#ebdbb2/gI

# selected row text -> fg0
s/#ffffff/#fbf1c7/gI

# descriptions -> fg4
s/#9692a8/#a89984/gI

# selected row background -> bg2
s/#3d375e/#504945/gI

# ghost text -> bg3
s/#4B4A4C/#665c54/gI

# tag chip backgrounds (alias / history / spec) -> bg1
s/#2a2342/#3c3836/gI
s/#1a2d36/#3c3836/gI
s/#1e1d28/#3c3836/gI

# text on a highlighted chip -> bg0
s/#110f18/#282828/gI
