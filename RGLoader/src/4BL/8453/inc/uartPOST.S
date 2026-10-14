.include "lfn.S"

MAKEPATCH 0xE70 # patch loader
0:
    MAKEBRANCH 0x5AC0
9:

MAKEPATCH 0x284 # init uart
0:
    MAKEBRANCH 0x5B10
9:

# =================================================================================
# patch loader
# =================================================================================
MAKEPATCH 0x5AC0
0:
	mfmsr   %r5              # get original machine state
        li      %r6, 0x10
        andc    %r6, %r5, %r6    # and machine state with 0x10
	
	mtmsrd  %r6, 0
	isync
	lis		%r3, -0x8000 		#; 0x80000000
	ori		%r3, %r3, 0x200		#; 0x80000200
	rldicr	%r3, %r3, 32,31		#; 0x80000200_00000000
	oris	%r3, %r3, 0xEA00 	#; 0x80000200_EA000000
	slwi	%r4, %r4, 24
	stw		%r4, 0x1014(%r3) 	#; 0x80000200_EA001014
    waitloop:
	    lwz		%r4, 0x1018(%r3) 	#; 0x80000200_EA001018
	    rlwinm.	%r4, %r4, 0,6,6
	    beq		waitloop
	    lis		%r4, 0x100
	    mtmsrd  %r5, 0
            isync
	    blr
9:

MAKEPATCH 0x5B10
0:
	li        %r7, 0x0200
	oris      %r7, %r7, 0x8000
	sldi      %r7, %r7, 32
	oris      %r7, %r7, 0xEA00
	#ori       %r7, %r7, 0x101C
	lis       %r8, 0
	oris       %r8, %r8, 0xE601       # 115200,8,N,1 
	stw       %r8, 0x101C(%r7)
	sync

	MAKEBRANCH 0x288
9:
