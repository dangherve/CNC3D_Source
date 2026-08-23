# Changelog

## C&C 3D v0.6.0 "Clear Skies" (2026-08-22)

### New features

- Aircraft appear in the game for the first time: Orcas, Apaches, Chinooks and A-10s
- The Airstrike now arrives: three A-10s fly in and attack the cell you picked
- Orcas built on a helipad are visible, and can be selected and ordered
- Orcas and Apaches show their ammo as pips, from the cartridge's own count of five
- Aircraft fly at the cartridge's own altitude, with their shadows on the ground below

### Improvements

- Health bars and pip rows on an aircraft sit at its altitude instead of on the ground
- Aircraft move smoothly between simulation steps, like every other unit
- Band select picks up aircraft
- Clicking an aircraft parked on a helipad selects the aircraft, not the pad
- A selected Orca or Apache shows its ammo strip
- The Game Speed slider works; it did nothing before
- Health bars and storage pips sit clear of the building they belong to

### Platforms and builds

- The macOS build now copies the engine into the package and refuses to build without it
- Windows now writes cnc3d-log.txt, which the READ-ME has always asked players to send

### Bugs fixed

- The Airstrike fired but nothing ever appeared
- An Orca built on a helipad was invisible
- A build could ship a renderer and an engine that disagreed, with every test still green
- Pressing Cancel in the Special Ops screen quit the whole game
- The minimap was visible before you had built a Communications Center
- The power meter read full whenever output met demand, whatever the numbers were
- The second East territory on the GDI map led to the same mission as the first

---

