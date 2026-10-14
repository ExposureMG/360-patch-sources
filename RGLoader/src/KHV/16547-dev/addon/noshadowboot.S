.include "macros.S"

		.globl _start
_start:
# ============================================================================
#	Disable shadowboots
#      (speeds up boot times a little)
# ============================================================================

	KMAKEPATCH 0x80081888
0:
	nop
9:


	
	
	
	
	
	