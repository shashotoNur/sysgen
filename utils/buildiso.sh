# Variables
ROOT_DIR=$1
ARCHISO_DIR="$ROOT_DIR/archiso"
CUSTOM_PROFILE="releng"
PROFILE_DIR="$ARCHISO_DIR/configs/$CUSTOM_PROFILE"
OUTPUT_ISO_NAME="sysgen_archlinux.iso"

# Clone ArchISO repository
if [[ ! -d $ARCHISO_DIR ]]; then
    git clone --depth=1 https://gitlab.archlinux.org/archlinux/archiso.git "$ARCHISO_DIR"
fi

# Copy user scripts into airootfs
mkdir -p "$PROFILE_DIR/airootfs/root/sysgen"
cp -r "$ROOT_DIR/sysgen"/* "$PROFILE_DIR/airootfs/root/sysgen"

# Ensure the script runs on boot
echo "cd ./sysgen && bash install.sh" >> "$PROFILE_DIR/airootfs/root.zshrc"

# Define the path to loader.conf
LOADER_CONF="$PROFILE_DIR/efiboot/loader/loader.conf"

# Ensure the file exists before modifying
if [[ -f "$LOADER_CONF" ]]; then
    # Modify the timeout value and beep setting
    sed -i 's/^timeout .*/timeout 1/' "$LOADER_CONF"
    sed -i 's/^beep on$/beep off/' "$LOADER_CONF"

    echo "Updated $LOADER_CONF:"
    grep -E '^timeout|^beep' "$LOADER_CONF"
else
    echo "Error: $LOADER_CONF not found!"
    exit 1
fi

# Include fuzzy finder in the iso
echo "fzf" >> "$PROFILE_DIR/packages.x86_64"

# Build the custom ISO
sudo mkarchiso -v -w work -o out $PROFILE_DIR

# Rename the output ISO
mkdir -p "$ROOT_DIR/iso"
mv out/archlinux-*.iso "$ROOT_DIR/iso/$OUTPUT_ISO_NAME"

# Output final ISO location
echo "Custom Arch ISO created at: $ROOT_DIR/iso/$OUTPUT_ISO_NAME"
