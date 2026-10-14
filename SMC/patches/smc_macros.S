;==============================================================================
; smc_macros.S - macros for Xbox 360 SMC (8051) patchsets
;
; Assembler: sdas8051 (ASxxxx, ships with SDCC). Patch sources are written as
; normal 8051 assembly placed at the real image offset of each patch, so the
; assembler encodes every jump itself. tools/smcpatch.py then packs the linked
; image (Intel HEX) into an SMC patch blob:
;
;   0x00  'SMCP'                       magic (not a valid xeBuild patch address)
;   0x04  u16 format version (1)       u16 flags (0)
;   0x08  u8 revision, u8 major, u8 minor (image bytes 0x100-0x102), u8 0
;   0x0C  u32 CRC32 of the clean raw base dump
;   0x10  records until EOF: u32 address, u32 length in bytes, data
;
; All fields are big-endian. Addresses are offsets into the raw dump, which is
; also the code address everywhere except 0x0000-0x0003: in a raw dump those
; hold the image header, and the loader copies the real reset/timer vectors
; there from (size - 8).
;
; Build a variant with tools/build_patches.sh; feature switches (CR4, JTAG,
; AUD_CLAMP, ...) are symbols defined before the patchset is included.
;==============================================================================

	.area	SMC (ABS,CODE)

; SMCPATCH addr
;   Start a patch at raw image offset addr. Everything up to the next
;   SMCPATCH is emitted at consecutive addresses.
	.macro	SMCPATCH addr
	.org	addr
	.endm

; SMCNOP addr, count
;   Overwrite count bytes at addr with NOPs.
	.macro	SMCNOP addr, count
	.org	addr
	.rept	count
	nop
	.endm
	.endm

; SMCHOOK addr, dest
;   Replace the 3 bytes at addr with ljmp dest.
	.macro	SMCHOOK addr, dest
	.org	addr
	ljmp	dest
	.endm

; SMCHOOKL addr, dest
;   Replace the 3 bytes at addr with lcall dest.
	.macro	SMCHOOKL addr, dest
	.org	addr
	lcall	dest
	.endm
