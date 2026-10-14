.include "macros.S"

		.globl _start
_start:

	KMAKEPATCH 0x800BEFE8
0:
	li   %r10,  0x6000
9:
