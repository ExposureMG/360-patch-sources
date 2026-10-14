.include "macros.S"

		.globl _start
_start:

	KMAKEPATCH 0x800BEF88
0:
	li   %r10,  0x6000
9:
