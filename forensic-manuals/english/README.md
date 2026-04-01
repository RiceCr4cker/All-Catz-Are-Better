# Forensic Investigation Guide: The "Katz vs Doges" Enigma

Welcome, investigator. You are in possession of a suspicious microSD card linked to a feline rebel cell. Your mission is to extract its ultimate secret. 

This guide will walk you through acquiring a forensic image of the card, mounting it virtually, and solving the steganographic Russian doll puzzle.

---

## 1. Forensic Acquisition (Creating the EWF image)

In digital forensics, we **never** work on the original media to avoid altering evidence. We will create an `EWF` (EnCase Image Format) image.

### Required tool: `ewf-tools`
If not already done, install the suite on your Linux machine:
`sudo apt-get install ewf-tools`

### Image Creation
Identify the microSD card (e.g., `/dev/sdb`) using the `lsblk` command. Then, launch the acquisition:
`sudo ewfacquire /dev/sdb`

The tool will ask several questions (case number, investigator's name, etc.). You can leave the default values by pressing Enter. 
*At the end of the process, you will get a compressed and hashed file, usually named `image.E01`.*

---

## 2. Mounting the EWF Image

A Linux system cannot read an `.E01` file directly. It must be "mounted" to expose a virtual RAW file that we can then analyze.

1. Create a mount point for the EWF image:
   `sudo mkdir -p /mnt/ewf_mount`
2. Mount the image:
   `sudo ewfmount image.E01 /mnt/ewf_mount/`
3. Verify the content. You should see a file named `ewf1` (which represents the raw disk):
   `ls -l /mnt/ewf_mount/`

---

## 3. Manual Resolution (Step by Step)

Now that we have our RAW file (`/mnt/ewf_mount/ewf1`), we need to access it as if it were a physical disk using a "loop device".

### Preparing the virtual disk
`sudo losetup --find --show --partscan /mnt/ewf_mount/ewf1`
*Note the returned device, for example `/dev/loop0`. The partitions will be `/dev/loop0p1`, `/dev/loop0p2`, etc.*

### Phase 1: The Doge Sector (Partition 1)
1. Mount the first partition (vFAT):
   `sudo mkdir -p /mnt/doges`
   `sudo mount /dev/loop0p1 /mnt/doges`
2. **The puzzle:** You are looking for the key files `angry1.jpg` to `angry4.jpg`. Extract the hidden passwords from the first two images (with an empty initial password):
   `steghide extract -sf /mnt/doges/angry1.jpg -xf steg_key1.txt -p ""`
   `steghide extract -sf /mnt/doges/angry2.jpg -xf steg_pass1.txt -p ""`
3. Use these passwords to extract the LUKS material from images 3 and 4:
   `steghide extract -sf /mnt/doges/angry3.jpg -xf key1.enc -p "$(cat steg_key1.txt)"`
   `steghide extract -sf /mnt/doges/angry4.jpg -xf pass1.txt -p "$(cat steg_pass1.txt)"`
4. Decrypt the LUKS key:
   `openssl enc -d -aes-256-cbc -pbkdf2 -salt -in key1.enc -out key1.key -pass "pass:$(cat pass1.txt)"`

### Phase 2: Katz HQ (Partition 2)
1. Use the freshly decrypted key to open partition 2:
   `sudo cryptsetup luksOpen --key-file key1.key /dev/loop0p2 katz_hq`
   `sudo mkdir -p /mnt/katz`
   `sudo mount /dev/mapper/katz_hq /mnt/katz`
2. Repeat **exactly** the same steganographic extraction procedure on the `angry1.jpg` to `angry4.jpg` files present in this new folder to obtain `key2.key`.

### Phase 3: The Ultimate Secret (Partition 3)
1. Unlock the last partition with the second key:
   `sudo cryptsetup luksOpen --key-file key2.key /dev/loop0p3 katz_secret`
   `sudo mkdir -p /mnt/secret`
   `sudo mount /dev/mapper/katz_secret /mnt/secret`
2. Read the manifesto:
   `cat /mnt/secret/secret_manifesto.txt`

---

## 4. Automatic Mode (Fallback Script)

If the feline madness has gotten the better of your patience, an automated solving script (`solve-stegano.sh`) is provided.

1. Make sure the EWF image is mounted and exposes the `ewf1` file (see section 2).
2. Make the script executable:
   `chmod +x solve-stegano.sh`
3. Run the script targeting the virtual RAW file:
   `sudo ./solve-stegano.sh /mnt/ewf_mount/ewf1`

The script will take care of creating the loop devices, extracting the passwords, decrypting the keys, mounting the cascading LUKS partitions, and displaying the final message.

---
### Cleaning the forensic environment
Once the investigation is over, cleanly unmount all elements:
`sudo umount /mnt/secret /mnt/katz /mnt/doges`
`sudo cryptsetup luksClose katz_secret`
`sudo cryptsetup luksClose katz_hq`
`sudo losetup -d /dev/loop0`
`sudo umount /mnt/ewf_mount`