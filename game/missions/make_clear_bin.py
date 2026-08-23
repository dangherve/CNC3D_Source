#!/usr/bin/env python3
"""Generate an all-clear PC-format C&C Tiberian Dawn .BIN for a 64x64 scenario.

Format (see MapClass::Read_Binary_File in tiberiandawn/map.cpp):
  4096 records, row-major over the 64x64 old-format cell grid, 2 bytes each:
     byte 0 = TemplateType (unsigned char); 255 == TEMPLATE_NONE == clear
     byte 1 = TIcon        (unsigned char)
  Total = 8192 bytes exactly. Read_Binary_File returns true only when all
  4096 records were read.
"""
import sys
CELLS = 64 * 64
data = bytes([0xFF, 0x00]) * CELLS
assert len(data) == 8192
for path in sys.argv[1:]:
    open(path, 'wb').write(data)
    print("wrote", path, len(data), "bytes")
