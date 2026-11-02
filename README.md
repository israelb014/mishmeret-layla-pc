# משמרת לילה — מהדורת PC

משחק יריות תלת־ממדי על מסילה (light-gun shooter) למחשב, בעברית, בהשראת משחקי ארקייד משנות ה־90.
שלושה שלבים בישראל — רחוב ראשי בצהריים, נמל חיפה בשקיעה ותחנת רכבת בלילה — עם בחירת מסלול בכל שלב, בוסים, נשקים מיוחדים, בני ערובה ואזרחים שאסור לפגוע בהם.

זוהי גרסה מקורית ל־PC, בנויה ב־Godot 4.7.2 (Forward+ / Vulkan), עם תוכן זהה לגרסת הדפדפן ואיכות גרפיקה של מחשב שולחני.

**עמוד ההורדה:** https://israelb014.github.io/mishmeret-layla-pc/

## הורדה והפעלה

### Linux (נבדק על Linux Mint)

```bash
wget https://github.com/israelb014/mishmeret-layla-pc/releases/download/v1.0.1/MishmeretLayla-linux.tar.gz
mkdir -p ~/Games/MishmeretLayla && tar -xzf MishmeretLayla-linux.tar.gz -C ~/Games/MishmeretLayla
~/Games/MishmeretLayla/install-desktop-entry.sh && ~/Games/MishmeretLayla/MishmeretLayla.x86_64
```

הסקריפט `install-desktop-entry.sh` מוסיף את המשחק לתפריט היישומים (לתיקייה `~/.local/share/applications`), בלי sudo.

### Windows

מורידים את `MishmeretLayla-windows.zip` מעמוד ה־[Release](https://github.com/israelb014/mishmeret-layla-pc/releases/tag/v1.0.1), מחלצים ומפעילים את `MishmeretLayla.exe`.

## דרישות מערכת

- מעבד: ‏4 ליבות, 64 ביט (x86_64).
- כרטיס מסך עם Vulkan 1.2: ‏NVIDIA GTX 1060 / AMD RX 580 ומעלה. מומלץ RTX 2060 Super ומעלה ל־1080p "גבוה" ב־120 FPS.
- זיכרון: ‏8GB RAM, ‏4GB VRAM.
- מקום פנוי: ‏1.5GB.
- עכבר ומקלדת.

## שליטה

- **עכבר שמאלי** — ירי. **עכבר ימני / R / רווח** — טעינה.
- **Esc** — השהיה. **F1** — מונה ביצועים (FPS ממוצע, ‏1% low, הפריים האיטי ביותר).

## בדיקת ביצועים

```bash
~/Games/MishmeretLayla/MishmeretLayla.x86_64 --benchmark
```

הפעלה עם שמירת יומן (למשל כדי לדווח על זמן הטעינה — השורה `LOAD_TIME_MS=`):

```bash
~/Games/MishmeretLayla/MishmeretLayla.x86_64 --verbose > ~/ml.log 2>&1
```

בבדיקת הביצועים המשחק עובר אוטומטית על כל הזונות של כל השלבים בפריסט "גבוה", כותב את הקובץ `benchmark.txt` ליד קובץ ההפעלה, ויוצא.

## בנייה מקוד המקור

1. מתקינים את Godot ‏4.7.2 ואת תבניות הייצוא שלו (מ־https://github.com/godotengine/godot/releases).
2. משכפלים את המאגר:
   ```bash
   git clone https://github.com/israelb014/mishmeret-layla-pc.git && cd mishmeret-layla-pc
   ```
3. מייבאים את הנכסים ומייצאים:
   ```bash
   godot --headless --import --path .
   godot --headless --path . --export-release "Linux" build/linux/MishmeretLayla.x86_64
   godot --headless --path . --export-release "Windows" build/windows/MishmeretLayla.exe
   ```
4. בדיקה אוטומטית של כל הזונות (בלי חלון):
   ```bash
   godot --headless --path . --fixed-fps 60 -- --autotest
   ```

הנכסים המוכנים כבר נמצאים ב־`assets/`. צינור ההכנה שלהם (המרת הדמויות, האנימציות והאביזרים, והורדת הטקסטורות, המודלים וה־HDRI מ־Poly Haven) נמצא ב־`tools/`.

## מבנה הקוד

- `scripts/core/` — הגדרות, אודיו, כלי עזר.
- `scripts/world/` — בוני הסטים, זונות, חומרים, אביזרים ואפקטים.
- `scripts/actors/` — דמויות, אויבים, אזרחים ובוסים.
- `scripts/gameplay/` — מהלך המשחק, מסילת המצלמה, נשקים, ניקוד, אובייקטים ובוט הבדיקות.
- `scripts/ui/` — מסכים, HUD וטבעות האיום.
- `data/` — תוכן השלבים כנתונים (מסלולי מצלמה, אויבים, תזמונים).

## נכסים ורישיונות

כל הנכסים הם CC0, והגופנים (Secular One, ‏Rubik) ברישיון OFL. הרשימה המלאה: [CREDITS.md](CREDITS.md) (וגם במסך הקרדיטים במשחק).
החלטות המימוש: [DECISIONS.md](DECISIONS.md). רשימת ההעברה מגרסת הדפדפן: [PORT-CHECKLIST.md](PORT-CHECKLIST.md).
