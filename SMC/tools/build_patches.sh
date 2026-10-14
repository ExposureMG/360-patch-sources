#!/usr/bin/env bash
# Assemble every SMC patchset variant in patches/variants.tsv, pack it into
# patches/build/<VARIANT>.smcpatch, apply it to the clean base dump, and verify:
#   verify=dump           result is byte-identical to <VARIANT>.bin
#   verify=delta:<ref>:.. result differs from <ref>'s applied image at exactly
#                         the listed offsets/values (for SMC+, which has no dump)
#
# Usage: tools/build_patches.sh [VARIANT ...]
# Needs sdas8051/sdld (SDCC).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
P="$ROOT/patches"
mkdir -p "$P/build"
fail=0

# assemble+pack+apply <variant> <base> <patchset> <flags-csv>; writes work image
build_one() {
	local variant="$1" base="$2" patchset="$3" flags="$4"
	local w="$ROOT/work/patches/$variant"
	rm -rf "$w" && mkdir -p "$w"
	{
		echo "	.module	$variant"
		echo "	.include	\"smc_macros.S\""
		IFS=, read -ra fl <<<"$flags"
		for f in "${fl[@]}"; do echo "	$f = 1"; done
		echo "	.include	\"$patchset\""
	} >"$w/$variant.S"
	(cd "$w" && sdas8051 -I"$P" -l -o "$variant.rel" "$variant.S" >asm.log 2>&1 &&
		sdld -i "$variant.ihx" "$variant.rel" >link.log 2>&1) || {
		echo "FAIL $variant: assembly/link error"
		grep -v '^ASlink' "$w"/asm.log "$w"/link.log 2>/dev/null | head -20; return 1; }
	python3 -I "$ROOT/tools/smcpatch.py" pack "$ROOT/$base.bin" "$w/$variant.ihx" -o "$P/build/$variant.smcpatch" >/dev/null
	python3 -I "$ROOT/tools/smcpatch.py" apply "$ROOT/$base.bin" "$P/build/$variant.smcpatch" -o "$w/$variant.bin" >/dev/null
}

while IFS=$'\t' read -r variant base patchset flags verify; do
	[[ "$variant" == variant ]] && continue
	if [[ $# -gt 0 && ! " $* " =~ " $variant " ]]; then continue; fi
	build_one "$variant" "$base" "$patchset" "$flags" || { fail=1; continue; }
	w="$ROOT/work/patches/$variant"
	info="$(python3 -I "$ROOT/tools/smcpatch.py" info "$P/build/$variant.smcpatch" | tail -1)"

	if [[ "$verify" == dump ]]; then
		if cmp -s "$w/$variant.bin" "$ROOT/$variant.bin"; then
			printf "OK   %-14s %-14s %s\n" "$variant" "$base" "$info"
		else
			echo "FAIL $variant: rebuilt image differs from $variant.bin:"
			python3 -I "$ROOT/tools/smcpatch.py" diff "$ROOT/$variant.bin" "$w/$variant.bin" | head -10
			fail=1
		fi
	elif [[ "$verify" == delta:* ]]; then
		ref="${verify#delta:}"; expect="${ref#*:}"; ref="${ref%%:*}"
		build_one "$ref" "$base" "$patchset" "$(awk -F'\t' -v r="$ref" '$1==r{print $4}' "$P/variants.tsv")" ||
			{ fail=1; continue; }
		if python3 -I - "$w/$variant.bin" "$ROOT/work/patches/$ref/$ref.bin" "$expect" <<'PY'; then
import sys
new, old, expect = open(sys.argv[1], "rb").read(), open(sys.argv[2], "rb").read(), sys.argv[3]
want = {int(o, 16): int(v, 16) for o, v in (p.split("=") for p in expect.split(","))}
diff = {i: new[i] for i in range(len(new)) if new[i] != old[i]}
ok = diff == want and all(new[o] == v for o, v in want.items())
print(("OK   delta " if ok else "FAIL delta ") + " ".join(f"0x{o:04x}={new[o]:02x}" for o in sorted(want)) +
      ("" if ok else f"  got changed={{{', '.join(f'0x{o:04x}={diff[o]:02x}' for o in sorted(diff))}}}"))
sys.exit(0 if ok else 1)
PY
			printf "OK   %-14s %-14s %s (SMC+ vs %s)\n" "$variant" "$base" "$info" "$ref"
		else
			fail=1
		fi
	fi
done <"$P/variants.tsv"
exit $fail
