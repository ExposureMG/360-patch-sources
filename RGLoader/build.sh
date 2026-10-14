#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

USE_LFN=true

for arg in "$@"; do
    case "$arg" in
        -nolfn|--nolfn)
            USE_LFN=false
            ;;
        -h|--help)
            echo "Usage: ./build.sh [-nolfn]"
            echo "  Default: Builds 4BL patches with LFN (XeLL dual boot) enabled."
            echo "  -nolfn:  Builds 4BL base patches without LFN."
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: ./build.sh [-nolfn]"
            exit 1
            ;;
    esac
done

echo "***************************************"
echo "*  RGLoader Patchset Builder (Bash)  *"
echo "***************************************"
if [ "$USE_LFN" = true ]; then
    echo "Mode: LFN (XeLL Dual Boot) ENABLED (Default)"
else
    echo "Mode: Base Patches ONLY (-nolfn requested)"
fi
echo ""

BUILD_DIR="$SCRIPT_DIR/build_tmp"
mkdir -p "$BUILD_DIR"

AS_BIN="$SCRIPT_DIR/bin/xenon-as"
OBJCOPY_BIN="$SCRIPT_DIR/bin/xenon-objcopy"

if [ ! -x "$AS_BIN" ]; then
    chmod +x "$AS_BIN"
fi
if [ ! -x "$OBJCOPY_BIN" ]; then
    chmod +x "$OBJCOPY_BIN"
fi

# Function to compile assembly file into a binary blob
compile_patch() {
    local src_file="$1"
    local out_bin="$2"
    local inc_dir="$(dirname "$src_file")"
    local elf_file="${out_bin}.elf"

    echo "Assembling $src_file ..."
    "$AS_BIN" -I "$SCRIPT_DIR/include" -I "$inc_dir" -I "$inc_dir/inc" "$src_file" -o "$elf_file"
    "$OBJCOPY_BIN" "$elf_file" -O binary "$out_bin"
    rm -f "$elf_file"
}

# -----------------------------------------------------------------------------
# 1. Build 2BL Patches
# -----------------------------------------------------------------------------
echo "[1/4] Building 2BL patches..."
mkdir -p "$BUILD_DIR/2BL"
compile_patch "src/2BL/4577.S"  "$BUILD_DIR/2BL/4577.bin"
compile_patch "src/2BL/5772.S"  "$BUILD_DIR/2BL/5772.bin"
compile_patch "src/2BL/6752.S"  "$BUILD_DIR/2BL/6752.bin"
compile_patch "src/2BL/9188.S"  "$BUILD_DIR/2BL/9188.bin"
compile_patch "src/2BL/13121.S" "$BUILD_DIR/2BL/13121.bin"

# -----------------------------------------------------------------------------
# 2. Build 4BL Patches
# -----------------------------------------------------------------------------
echo "[2/4] Building 4BL patches..."
mkdir -p "$BUILD_DIR/4BL"

if [ "$USE_LFN" = true ]; then
    compile_patch "src/4BL/9452/9452-lfn.S" "$BUILD_DIR/4BL/9452.bin"
else
    compile_patch "src/4BL/9452/9452.S"     "$BUILD_DIR/4BL/9452.bin"
fi

# -----------------------------------------------------------------------------
# 3. Build KHV Patches & Assemble XeBuild Patchsets & Addons
# -----------------------------------------------------------------------------
echo "[3/4] Assembling patchsets and addons for qualified -dev build folders..."

TARGET_VERSIONS=(
    "13599-dev"
    "14699-dev"
    "14719-dev"
    "15574-dev"
    "16202-dev"
    "16203-dev"
    "16547-dev"
    "17150-dev"
    "17349-dev"
    "17489-dev"
)

for VER in "${TARGET_VERSIONS[@]}"; do
    echo "Processing $VER ..."
    
    OUT_DIR="$SCRIPT_DIR/xebuild-folders/$VER/bin"
    mkdir -p "$OUT_DIR"
    
    # Locate matching KHV main source file
    KHV_SRC=""
    if [ -f "src/KHV/$VER/$VER.S" ]; then
        KHV_SRC="src/KHV/$VER/$VER.S"
    elif [ -f "src/KHV/$VER/RGLoader-$VER.S" ]; then
        KHV_SRC="src/KHV/$VER/RGLoader-$VER.S"
    elif [ -f "src/KHV/$VER/${VER%-dev}.S" ]; then
        KHV_SRC="src/KHV/$VER/${VER%-dev}.S"
    elif [ -f "src/KHV/$VER/RGLoader-${VER%-dev}.S" ]; then
        KHV_SRC="src/KHV/$VER/RGLoader-${VER%-dev}.S"
    else
        echo "ERROR: KHV main patch file not found for $VER" >&2
        exit 1
    fi
    
    KHV_BIN="$BUILD_DIR/KHV_${VER}.bin"
    compile_patch "$KHV_SRC" "$KHV_BIN"
    
    BL4_BIN="$BUILD_DIR/4BL/9452.bin"
    
    # Assemble the 5 motherboard patchsets (2BL + 4BL + KHV)
    # Falcon RGH2 (CB 5772)
    cat "$BUILD_DIR/2BL/5772.bin" "$BL4_BIN" "$KHV_BIN" > "$OUT_DIR/patches_g2mfalcon.bin"
    
    # Jasper RGH2 (CB 6752)
    cat "$BUILD_DIR/2BL/6752.bin" "$BL4_BIN" "$KHV_BIN" > "$OUT_DIR/patches_g2mjasper.bin"
    
    # Zephyr RGH2 (CB 4577)
    cat "$BUILD_DIR/2BL/4577.bin" "$BL4_BIN" "$KHV_BIN" > "$OUT_DIR/patches_g2mzephyr.bin"
    
    # Trinity RGH / RGH2 (CB 9188)
    cat "$BUILD_DIR/2BL/9188.bin" "$BL4_BIN" "$KHV_BIN" > "$OUT_DIR/patches_g2mtrinity.bin"
    
    # Corona RGH / RGH2 (CB 13121)
    cat "$BUILD_DIR/2BL/13121.bin" "$BL4_BIN" "$KHV_BIN" > "$OUT_DIR/patches_g2mcorona.bin"
    
    # Compile optional addon patches in src/KHV/$VER/addon/
    if [ -d "src/KHV/$VER/addon" ]; then
        for addon_file in src/KHV/$VER/addon/*.S; do
            if [ -f "$addon_file" ]; then
                addon_name="$(basename "$addon_file" .S)"
                compile_patch "$addon_file" "$OUT_DIR/${addon_name}.bin"
            fi
        done
    fi
    
    echo "  Generated patchsets & addons in $OUT_DIR/"
done

# -----------------------------------------------------------------------------
# 4. Build XAM Patches
# -----------------------------------------------------------------------------
echo "[4/4] Building XAM patches into xebuild-folders..."

find src/XAM -type f -name "rglXam.S" | sort | while read -r xam_src; do
    xam_dir="$(dirname "$xam_src")"
    ver="$(basename "$xam_dir")"
    OUT_DIR="$SCRIPT_DIR/xebuild-folders/$ver/fs/"
    mkdir -p "$OUT_DIR"
    rglp_out="$OUT_DIR/rglXam.rglp"
    compile_patch "$xam_src" "$rglp_out"
    echo "  Generated $rglp_out"
done

rm -rf "$BUILD_DIR"

echo ""
echo "======================================="
echo " All patchsets, addons & XAM patches built successfully!"
echo "======================================="
