# Torino Events — app Flutter

Tre tab: **Scopri** (carte swipe stile Tinder), **Calendario**, **Fonti**
(gestione sources.yaml del repo scraper direttamente dall'app).

## Setup

```bash
flutter create . --platforms=android,ios   # genera le cartelle piattaforma
flutter pub get
flutter run
```

Poi nell'app: tab **Fonti → Repo GitHub** → inserisci owner, repo (quello
dello scraper) e, se vuoi modificare le fonti dall'app, un fine-grained PAT
con permessi **Contents: read/write** e **Actions: write** sul solo repo.

- **Senza token**: l'app legge events.json e gli switch delle fonti filtrano
  solo localmente.
- **Con token**: switch = modifica `enabled` nello yaml; "+" aggiunge fonti
  RSS; swipe a sinistra su una fonte la elimina. Ogni modifica rilancia
  subito lo scraper (workflow_dispatch), eventi freschi in ~1 minuto.

## Permessi piattaforma

**Android** (`android/app/src/main/AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

**iOS**: nessun permesso extra; `url_launcher` per aprire link/Maps funziona
out of the box.

## Note

- Swipe destro = salvato (cuore), sinistro = scartato. Le decisioni sono
  persistite in locale (shared_preferences).
- Il badge arancione "data da verificare" = `date_confidence: low` dallo
  scraper.
- La mappa (OpenStreetMap via flutter_map) appare solo quando l'evento ha
  lat/lon — arriveranno col geocoding in fase 2. Nel frattempo "Portami lì"
  apre Maps cercando venue/titolo + Torino.
- Riscrivendo sources.yaml dall'app, i commenti nel file YAML vengono persi.
