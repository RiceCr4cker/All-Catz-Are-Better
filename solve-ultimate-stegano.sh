#!/usr/bin/env bash
#
# solve-stegano.sh - Automated solver for the "Katz vs Doges" challenge.
#
# Supports physical devices and raw disk images via loop devices.
#
set -euo pipefail

TARGET="${1:-}"

show_usage() {
    echo "Usage: sudo $0 <source>"
    echo ""
    echo "Arguments:"
    echo "  source    Path to a block device or a raw disk image file."
    echo ""
    echo "Examples:"
    echo "  sudo $0 /dev/sdb            # Solve from physical SD card"
    echo "  sudo $0 /path/to/disk.img   # Solve from a forensic disk image"
}

if [[ -z "${TARGET}" ]]; then
    show_usage
    exit 1
fi

IS_LOOP_DEVICE=0
LOOP_DEV_PATH=""

# --- 1. TARGET DETECTION ---
if [[ -f "${TARGET}" ]]; then
    echo "[*] Image file detected. Setting up loop device..."
    LOOP_DEV_PATH=$(losetup --find --show --partscan "${TARGET}")
    FINAL_TARGET="${LOOP_DEV_PATH}"
    IS_LOOP_DEVICE=1
    sleep 1 # Wait for kernel to populate partitions
    
    PART_1="${FINAL_TARGET}p1"
    PART_2="${FINAL_TARGET}p2"
    PART_3="${FINAL_TARGET}p3"
    
elif [[ -b "${TARGET}" ]]; then
    echo "[*] Block device detected: ${TARGET}"
    FINAL_TARGET="${TARGET}"
    
    if [[ "${FINAL_TARGET}" == *loop* || "${FINAL_TARGET}" == *mmcblk* || "${FINAL_TARGET}" == *nvme* ]]; then
        PART_1="${FINAL_TARGET}p1"
        PART_2="${FINAL_TARGET}p2"
        PART_3="${FINAL_TARGET}p3"
    else
        PART_1="${FINAL_TARGET}1"
        PART_2="${FINAL_TARGET}2"
        PART_3="${FINAL_TARGET}3"
    fi
else
    echo "Error: Target is neither a file nor a block device."
    exit 1
fi

SOLVER_WORKDIR=$(mktemp -d)
GENERIC_MOUNT_POINT=$(mktemp -d)

# Cleanup logic
cleanup_env() {
    echo "[*] Cleaning up resources..."
    umount "${GENERIC_MOUNT_POINT}" 2>/dev/null || true
    cryptsetup luksClose solve_level2 2>/dev/null || true
    cryptsetup luksClose solve_level1 2>/dev/null || true
    rm -rf "${SOLVER_WORKDIR}" "${GENERIC_MOUNT_POINT}"
    
    if [[ ${IS_LOOP_DEVICE} -eq 1 && -n "${LOOP_DEV_PATH}" ]]; then
        echo "[*] Detaching loop device ${LOOP_DEV_PATH}..."
        losetup -d "${LOOP_DEV_PATH}" 2>/dev/null || true
    fi
}
trap cleanup_env EXIT

# --- 2. STEP 1: DOGE LEVEL (P1) ---
echo "[*] Accessing Doge Partition (Level 1)..."
mount "${PART_1}" "${GENERIC_MOUNT_POINT}"

echo "[*] Extracting hidden passwords from angry1/2.jpg..."
steghide extract -sf "${GENERIC_MOUNT_POINT}/angry1.jpg" -xf "${SOLVER_WORKDIR}/steg_p_key1.txt" -p "" -q
steghide extract -sf "${GENERIC_MOUNT_POINT}/angry2.jpg" -xf "${SOLVER_WORKDIR}/steg_p_pass1.txt" -p "" -q

SP_KEY1=$(cat "${SOLVER_WORKDIR}/steg_p_key1.txt")
SP_PASS1=$(cat "${SOLVER_WORKDIR}/steg_p_pass1.txt")

echo "[*] Extracting LUKS elements from angry3/4.jpg..."
steghide extract -sf "${GENERIC_MOUNT_POINT}/angry3.jpg" -xf "${SOLVER_WORKDIR}/key1.enc" -p "${SP_KEY1}" -q
steghide extract -sf "${GENERIC_MOUNT_POINT}/angry4.jpg" -xf "${SOLVER_WORKDIR}/pass1.txt" -p "${SP_PASS1}" -q

LUKS_PWD1=$(cat "${SOLVER_WORKDIR}/pass1.txt")
openssl enc -d -aes-256-cbc -pbkdf2 -salt -in "${SOLVER_WORKDIR}/key1.enc" -out "${SOLVER_WORKDIR}/key1.key" -pass "pass:${LUKS_PWD1}"

umount "${GENERIC_MOUNT_POINT}"

# --- 3. STEP 2: KATZ HQ (P2) ---
echo "[*] Opening Katz HQ Partition (Level 2)..."
cryptsetup luksOpen --key-file "${SOLVER_WORKDIR}/key1.key" "${PART_2}" solve_level1
mount /dev/mapper/solve_level1 "${GENERIC_MOUNT_POINT}"

echo "[*] Extracting hidden passwords from internal Katz photos..."
steghide extract -sf "${GENERIC_MOUNT_POINT}/angry1.jpg" -xf "${SOLVER_WORKDIR}/steg_p_key2.txt" -p "" -q
steghide extract -sf "${GENERIC_MOUNT_POINT}/angry2.jpg" -xf "${SOLVER_WORKDIR}/steg_p_pass2.txt" -p "" -q

SP_KEY2=$(cat "${SOLVER_WORKDIR}/steg_p_key2.txt")
SP_PASS2=$(cat "${SOLVER_WORKDIR}/steg_p_pass2.txt")

steghide extract -sf "${GENERIC_MOUNT_POINT}/angry3.jpg" -xf "${SOLVER_WORKDIR}/key2.enc" -p "${SP_KEY2}" -q
steghide extract -sf "${GENERIC_MOUNT_POINT}/angry4.jpg" -xf "${SOLVER_WORKDIR}/pass2.txt" -p "${SP_PASS2}" -q

LUKS_PWD2=$(cat "${SOLVER_WORKDIR}/pass2.txt")
openssl enc -d -aes-256-cbc -pbkdf2 -salt -in "${SOLVER_WORKDIR}/key2.enc" -out "${SOLVER_WORKDIR}/key2.key" -pass "pass:${LUKS_PWD2}"

umount "${GENERIC_MOUNT_POINT}"

# --- 4. STEP 3: FINAL SECRET (P3) ---
echo "[*] Accessing Top Secret Partition..."
cryptsetup luksOpen --key-file "${SOLVER_WORKDIR}/key2.key" "${PART_3}" solve_level2
mount /dev/mapper/solve_level2 "${GENERIC_MOUNT_POINT}"

echo ""
echo "================================================================="
echo " CHALLENGE COMPLETE - RECOVERED SECRET DATA:"
echo "================================================================="
echo ""
cat "${GENERIC_MOUNT_POINT}/secret_manifesto.txt"
echo "================================================================="
echo ""