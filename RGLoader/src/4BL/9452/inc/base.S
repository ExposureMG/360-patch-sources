.include "macros.S"

# =================================================================================
# Extend the loader (used to be 0x6000, that could cause problems though)
# =================================================================================

MAKEPATCH 0x0000000C
0:
	.long 0x5F00
9:

# =================================================================================
# remove CE hash check
# (branch conditionally -> branch)
# =================================================================================

MAKEPATCH 0xC4C
0:
    .long 0x60000000
9:


# =================================================================================
# remove CF signature check
# (branch conditionally -> nop)
# =================================================================================
MAKEPATCH 0xD9C
0:
    .long 0x60000000
9:

# =================================================================================
# remove CF/CG hash check
# (li r3, 0 -> li r3, 1)
# =================================================================================
#MAKEPATCH 0xDA4
#0:
#    .long 0x48000084
#9:

#fix zero pair issue
#MAKEPATCH 0xC8C
#0:
#    .long 0x39400000
#9:

#MAKEPATCH 0xE28
#0:
#    .long 0x39600000
#9:


#MAKEPATCH 0xE40
#0:
#    .long 0x60000000
#9:

MAKEPATCH 0xCA8
0:
    .long 0x4800019C
9:

# =================================================================================
# remove unpaired bit from bootloader flags
# =================================================================================
MAKEPATCH 0xE54
0:
    MAKEBRANCH 0x00004F30
9:


MAKEPATCH 0x00004F30
0:
    or        %r11, %r11, %r10 # do what we patched did originally
	li        %r4, 0x21
	andc      %r11, %r11, %r4 # clear bit
	ori       %r11, %r11, 0xC
    MAKEBRANCH 0xE58
9:
