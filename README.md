# 🐈‍⬛ All-Catz-Are-Better 🐈‍

This project's purpose is to answer to my FX06-STEGANO homework. I built a bash script that creates a steganography challenge that can be solved by (almost) anyone. This challenge could totally be applied in a real life scenario where (super-secret) sensitive data needs to be communicated securely, with a multi-level obfuscation.

---

## Constructing the enigma

With your storage peripheral connected to your machine launch :

```bash
chmod +x ultimate-stegano.sh
sudo ./ultimate-stegano.sh <path-to-your-storage-device>
```

### How it works

The script takes your storage device and splits it into three distinct partitions. The first one is public and unencrypted (vFAT), containing innocent-looking dog pictures, it seems like it belongs to _DogeCorporation_. The second and third are encrypted vaults (LUKS) nested one after the other.

To secure the vaults, the script employs a "Russian doll" steganography strategy combined with a massive decoy system. It generates random cryptographic keys and passphrases, then hides them inside four specific photos.

To make extraction virtually impossible for an attacker trying to brute-force the device, the script "poisons" all the other remaining photos with random, meaningless data (noise). Finding the secret isn't just about knowing how to extract it, it's about knowing which files contain the actual keys among dozens of fakes that look exactly the same mathematically.

>Here the four photos containing the secrets have obvious names (`angry1.jpg`, `angry2.jpg`, etc.). In reality, since only the recipient of the message would know which one to chose, it would be statistically hard to try to guess which B64 string opens what.

---

## Solving the enigma

If you've received the physical storage device, you will need to make a forensic copy of it using your favorite tool (probably EWF). 

**Only once this is done can you work on the storage device's EWF image !** Well in fact, you can totally work on the physical device directly if you want, but that will not follow the basic guidelines of forensics.

To make the EWF copy and solve the enigma, you can follow the guide in english or french in `./forensic-manuals`.

### How it works

Solving the challenge requires following a precise trail of breadcrumbs. On the first public partition, you must identify the four specific "key" images (the ones with "angry" in their names).

First, you extract hidden steganography passwords from two of these images—these require no initial password to be unlocked. Once you recover them, you use these exact passwords to extract a locked LUKS key and its corresponding passphrase from the other two images. After decrypting the LUKS key, you can finally unlock the second partition (the Katz HQ).

Inside this first encrypted vault, you are faced with the exact same puzzle: a new set of photos, a new set of decoys, and four new specific images to find. Repeating the extraction and decryption process will yield the final master key required to unlock the third and last partition, revealing the ultimate secret message.

### Shortcut

You need to speedrun the challenge for any reason ? Use the solving script on your storage or it's image :

```bash
chmod +x solve-ultimate-stegano.sh
sudo ./ultimate-stegano.sh <path-to-your-storage-device-or-image>
```

