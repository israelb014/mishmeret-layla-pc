## משמרת לילה — מהדורת PC {TAG}

משחק יריות ארקייד על מסילה, בעברית, ל־Linux ול־Windows (Godot 4.7.2, Forward+ / Vulkan).

### Linux Mint
```bash
wget https://github.com/israelb014/mishmeret-layla-pc/releases/download/{TAG}/MishmeretLayla-linux.tar.gz
mkdir -p ~/Games/MishmeretLayla && tar -xzf MishmeretLayla-linux.tar.gz -C ~/Games/MishmeretLayla
~/Games/MishmeretLayla/install-desktop-entry.sh && ~/Games/MishmeretLayla/MishmeretLayla.x86_64
```

### Windows
מחלצים את `MishmeretLayla-windows.zip` ומפעילים את `MishmeretLayla.exe`.

### בדיקת ביצועים
```bash
~/Games/MishmeretLayla/MishmeretLayla.x86_64 --benchmark
```
התוצאות נכתבות לקובץ `benchmark.txt` ליד קובץ ההפעלה.

עמוד ההורדה: https://israelb014.github.io/mishmeret-layla-pc/
