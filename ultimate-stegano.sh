#!/usr/bin/env bash
#
# ultimate-stegano.sh - Setup for the "Katz vs Doges" forensic challenge.
#
# This script creates 3 partitions:
# 1. vFAT (Public) - Contains Doge photos with hidden hints.
# 2. LUKS (Encrypted) - Katz Level 1 HQ.
# 3. LUKS (Encrypted) - Top Secret Level 2.
#
set -euo pipefail

TARGET="${1:-}"

# Improved Usage description
show_usage() {
    echo "Usage: sudo $0 <target_device>"
    echo ""
    echo "Arguments:"
    echo "  target_device    The block device to wipe (e.g., /dev/sdb)"
    echo ""
    echo "Examples:"
    echo "  sudo $0 /dev/sdb       # Setup a physical SD card"
    echo "  sudo $0 /dev/mmcblk0   # Setup a physical MMC card"
    echo ""
    echo "Note: This script requires a 'photos/' directory with 'doges/' and 'katz/' subdirectories."
}

if [[ -z "${TARGET}" || ! -b "${TARGET}" ]]; then
    show_usage
    exit 1
fi

echo "[!] WARNING: This will WIPE ALL DATA on ${TARGET}."
echo "Type 'WIPE' to confirm and continue:"
read -r CONFIRM
[[ "${CONFIRM}" != "WIPE" ]] && { echo "Aborted."; exit 1; }

# Setup temporary working directory
WORKING_DIR=$(mktemp -d)
trap 'rm -rf "${WORKING_DIR}"' EXIT

# --- 1. UTILITY FUNCTIONS ---

# Generates a random base64 string for passwords/keys
generate_random_payload() {
    openssl rand -base64 48
}

# --- 2. PARTITIONING ---
# Layout: P1 (500MB vFAT), P2 (1.5GB LUKS), P3 (Remaining LUKS)
echo "[*] Creating partition table on ${TARGET}..."
sfdisk "${TARGET}" <<EOF
label: dos
size=500M, type=c
size=1.5G, type=83
type=83
EOF
sleep 2

PART1="${TARGET}1"
PART2="${TARGET}2"
PART3="${TARGET}3"

# Fix partition naming for NVMe/MMC/Loop devices (e.g., /dev/loop0p1)
if [[ "${TARGET}" == *loop* || "${TARGET}" == *mmcblk* || "${TARGET}" == *nvme* ]]; then
    PART1="${TARGET}p1"
    PART2="${TARGET}p2"
    PART3="${TARGET}p3"
fi

# --- 3. CRYPTOGRAPHIC PREPARATION ---
LUKS_KEY_1="${WORKING_DIR}/level1.key"
LUKS_KEY_2="${WORKING_DIR}/level2.key"
LUKS_PASS_1=$(generate_random_payload)
LUKS_PASS_2=$(generate_random_payload)

# Create raw keys
generate_random_payload > "${LUKS_KEY_1}"
generate_random_payload > "${LUKS_KEY_2}"

# Encrypt keys using passphrases (PBKDF2)
openssl enc -aes-256-cbc -pbkdf2 -salt -in "${LUKS_KEY_1}" -out "${LUKS_KEY_1}.enc" -pass "pass:${LUKS_PASS_1}"
openssl enc -aes-256-cbc -pbkdf2 -salt -in "${LUKS_KEY_2}" -out "${LUKS_KEY_2}.enc" -pass "pass:${LUKS_PASS_2}"

# --- 4. LEVEL 1: DOGE PARTITION (vFAT) ---
echo "[*] Processing Doge Level Steganography..."

# Generate Steghide passwords for the "hints"
STEG_PASS_FOR_KEY=$(generate_random_payload)
STEG_PASS_FOR_PASS=$(generate_random_payload)

# Embed hints (Level 1)
steghide embed -cf "photos/doges/angry1.jpg" -ef <(echo "${STEG_PASS_FOR_KEY}") -p "" -q
steghide embed -cf "photos/doges/angry2.jpg" -ef <(echo "${STEG_PASS_FOR_PASS}") -p "" -q

# Embed encrypted LUKS elements using the generated Steghide passwords
steghide embed -cf "photos/doges/angry3.jpg" -ef "${LUKS_KEY_1}.enc" -p "${STEG_PASS_FOR_KEY}" -q
steghide embed -cf "photos/doges/angry4.jpg" -ef <(echo "${LUKS_PASS_1}") -p "${STEG_PASS_FOR_PASS}" -q

# Fill remaining photos with decoys
for img in photos/doges/*.jpg; do
    if [[ "$img" != *"angry"* ]]; then
        DECOY_DATA=$(generate_random_payload)
        # Randomly choose between empty or random password for decoys
        if (( RANDOM % 2 )); then
            steghide embed -cf "$img" -ef <(echo "${DECOY_DATA}") -p "" -q
        else
            steghide embed -cf "$img" -ef <(echo "${DECOY_DATA}") -p "$(generate_random_payload)" -q
        fi
    fi
done

# Format and Populate P1
mkfs.vfat -F 32 -n "DOGE_CORP" "${PART1}"
MOUNT_P1=$(mktemp -d)
mount "${PART1}" "${MOUNT_P1}"
cp photos/doges/*.jpg "${MOUNT_P1}/"
umount "${MOUNT_P1}"

# --- 5. LEVEL 2: KATZ HQ (LUKS1) ---
echo "[*] Setting up Katz HQ (Encrypted)..."
cryptsetup luksFormat --type luks2 --key-file "${LUKS_KEY_1}" "${PART2}"
cryptsetup luksOpen --key-file "${LUKS_KEY_1}" "${PART2}" katz_hq_mapping
mkfs.ext4 -L "KATZ_HQ" /dev/mapper/katz_hq_mapping

echo "[*] Processing Katz Level Steganography..."
STEG_KATZ_PASS_KEY=$(generate_random_payload)
STEG_KATZ_PASS_PASS=$(generate_random_payload)

# Embed hints (Level 2)
steghide embed -cf "photos/katz/angry1.jpg" -ef <(echo "${STEG_KATZ_PASS_KEY}") -p "" -q
steghide embed -cf "photos/katz/angry2.jpg" -ef <(echo "${STEG_KATZ_PASS_PASS}") -p "" -q

# Embed Level 2 LUKS elements
steghide embed -cf "photos/katz/angry3.jpg" -ef "${LUKS_KEY_2}.enc" -p "${STEG_KATZ_PASS_KEY}" -q
steghide embed -cf "photos/katz/angry4.jpg" -ef <(echo "${LUKS_PASS_2}") -p "${STEG_KATZ_PASS_PASS}" -q

# Decoy injection for Katz folder
for img in photos/katz/*.jpg; do
    if [[ "$img" != *"angry"* ]]; then
        DECOY_DATA=$(generate_random_payload)
        steghide embed -cf "$img" -ef <(echo "${DECOY_DATA}") -p "" -q
    fi
done

# Populate P2
MOUNT_P2=$(mktemp -d)
mount /dev/mapper/katz_hq_mapping "${MOUNT_P2}"
cp -r photos/katz/* "${MOUNT_P2}/"
umount "${MOUNT_P2}"
cryptsetup luksClose katz_hq_mapping

# --- 6. LEVEL 3: TOP SECRET (LUKS2) ---
echo "[*] Setting up Top Secret Partition..."
cryptsetup luksFormat --type luks2 --key-file "${LUKS_KEY_2}" "${PART3}"
cryptsetup luksOpen --key-file "${LUKS_KEY_2}" "${PART3}" katz_secret_mapping
mkfs.ext4 -L "TOP_SECRET" /dev/mapper/katz_secret_mapping

MOUNT_P3=$(mktemp -d)
mount /dev/mapper/katz_secret_mapping "${MOUNT_P3}"
echo "To destroy capitalism we must unite! ACAB: All Catz Are Better!!!" > "${MOUNT_P3}/secret_manifesto.txt"
umount "${MOUNT_P3}"
cryptsetup luksClose katz_secret_mapping

echo "[*] Challenge Deployment Complete!"