# Guide d'Investigation Forensique : L'Énigme "Katz vs Doges"

Bienvenue, enquêteur. Vous êtes en possession d'une carte microSD suspecte liée à une cellule rebelle féline. Votre mission est d'en extraire le secret ultime. 

Ce guide vous expliquera comment acquérir l'image forensique de la carte, la monter virtuellement, et résoudre l'énigme des poupées russes stéganographiques.

---

## 1. Acquisition Forensique (Création de l'image EWF)

En investigation numérique, on ne travaille **jamais** sur le support original pour éviter d'en altérer les preuves. Nous allons créer une image au format `EWF` (EnCase Image Format).

### Outil requis : `ewf-tools`
Si ce n'est pas déjà fait, installez la suite sur votre machine Linux :
`sudo apt-get install ewf-tools`

### Création de l'image
Identifiez la carte microSD (par exemple `/dev/sdb`) via la commande `lsblk`. Puis, lancez l'acquisition :
`sudo ewfacquire /dev/sdb`

L'outil vous posera plusieurs questions (numéro de dossier, nom de l'enquêteur, etc.). Vous pouvez laisser les valeurs par défaut en appuyant sur Entrée. 
*À la fin du processus, vous obtiendrez un fichier compressé et haché, généralement nommé `image.E01`.*

---

## 2. Montage de l'image EWF

Le système Linux ne peut pas lire directement un fichier `.E01`. Il faut le "monter" pour exposer un fichier RAW virtuel que nous pourrons ensuite analyser.

1. Créez un point de montage pour l'image EWF :
   `sudo mkdir -p /mnt/ewf_mount`
2. Montez l'image :
   `sudo ewfmount image.E01 /mnt/ewf_mount/`
3. Vérifiez le contenu. Vous devriez voir un fichier nommé `ewf1` (qui représente le disque brut) :
   `ls -l /mnt/ewf_mount/`

---

## 3. Résolution Manuelle (Étape par Étape)

Maintenant que nous avons notre fichier RAW (`/mnt/ewf_mount/ewf1`), nous devons y accéder comme s'il s'agissait d'un disque physique à l'aide d'un "périphérique boucle" (loop device).

### Préparation du disque virtuel
`sudo losetup --find --show --partscan /mnt/ewf_mount/ewf1`
*Notez le périphérique renvoyé, par exemple `/dev/loop0`. Les partitions seront `/dev/loop0p1`, `/dev/loop0p2`, etc.*

### Phase 1 : Le Secteur Doge (Partition 1)
1. Montez la première partition (vFAT) :
   `sudo mkdir -p /mnt/doges`
   `sudo mount /dev/loop0p1 /mnt/doges`
2. **L'énigme :** Vous cherchez les fichiers clés `angry1.jpg` à `angry4.jpg`. Extrayez les mots de passe cachés dans les deux premières images (sans mot de passe initial) :
   `steghide extract -sf /mnt/doges/angry1.jpg -xf steg_key1.txt -p ""`
   `steghide extract -sf /mnt/doges/angry2.jpg -xf steg_pass1.txt -p ""`
3. Utilisez ces mots de passe pour extraire le matériel LUKS des images 3 et 4 :
   `steghide extract -sf /mnt/doges/angry3.jpg -xf key1.enc -p "$(cat steg_key1.txt)"`
   `steghide extract -sf /mnt/doges/angry4.jpg -xf pass1.txt -p "$(cat steg_pass1.txt)"`
4. Déchiffrez la clé LUKS :
   `openssl enc -d -aes-256-cbc -pbkdf2 -salt -in key1.enc -out key1.key -pass "pass:$(cat pass1.txt)"`

### Phase 2 : Le QG Katz (Partition 2)
1. Utilisez la clé fraîchement déchiffrée pour ouvrir la partition 2 :
   `sudo cryptsetup luksOpen --key-file key1.key /dev/loop0p2 katz_hq`
   `sudo mkdir -p /mnt/katz`
   `sudo mount /dev/mapper/katz_hq /mnt/katz`
2. Répétez **exactement** la même procédure d'extraction stéganographique sur les fichiers `angry1.jpg` à `angry4.jpg` présents dans ce nouveau dossier pour obtenir `key2.key`.

### Phase 3 : Le Secret Ultime (Partition 3)
1. Déverrouillez la dernière partition avec la seconde clé :
   `sudo cryptsetup luksOpen --key-file key2.key /dev/loop0p3 katz_secret`
   `sudo mkdir -p /mnt/secret`
   `sudo mount /dev/mapper/katz_secret /mnt/secret`
2. Lisez le manifeste :
   `cat /mnt/secret/secret_manifesto.txt`

---

## 4. Mode Automatique (Script de Secours)

Si la folie féline a eu raison de votre patience, un script automatisé de résolution (`solve-stegano.sh`) est fourni.

1. Assurez-vous que l'image EWF est montée et expose le fichier `ewf1` (voir la section 2).
2. Rendez le script exécutable :
   `chmod +x solve-stegano.sh`
3. Lancez le script en ciblant le fichier RAW virtuel :
   `sudo ./solve-stegano.sh /mnt/ewf_mount/ewf1`

Le script s'occupera de créer les loop devices, d'extraire les mots de passe, de déchiffrer les clés, de monter les partitions LUKS en cascade et d'afficher le message final.

---
### Nettoyage de l'environnement forensique
Une fois l'investigation terminée, démontez proprement tous les éléments :
`sudo umount /mnt/secret /mnt/katz /mnt/doges`
`sudo cryptsetup luksClose katz_secret`
`sudo cryptsetup luksClose katz_hq`
`sudo losetup -d /dev/loop0`
`sudo umount /mnt/ewf_mount`