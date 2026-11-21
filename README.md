# ImageSort

En Mac-app for å rydde i bilder fort. Når du har tatt 5–10 bilder av samme motiv, samler ImageSort dem i en gruppe og foreslår det beste. Du bekrefter med ett tastetrykk, og resten flyttes til **Papirkurven**.

## Slik fungerer det
1. **Åpne en mappe** (⌘O eller dra den inn i vinduet), for eksempel Dropbox/Camera Uploads.
2. Appen analyserer alle bildene **lokalt** med Apples innebygde bilde-AI (Vision):
   - **Gruppering:** bilder tatt tett i tid *og* som ligner visuelt.
   - **Kvalitet:** skarphet, ansiktskvalitet, åpne/lukkede øyne og estetikk.
3. I hver gruppe er det beste bildet allerede valgt (⭐ *Forslag*). Juster om du vil, og trykk **Enter**.
4. Er du usikker, trykker du **C** for å la Claude vurdere gruppen (se under).

Bilder som ikke ligner noen andre, ligger under **Enkeltbilder** i sidefeltet, delt opp per måned. Der kan du bla, se i fullskjerm og merke bilder til en samling med K. Med ⌫ eller 🗑 sletter du ett og ett bilde (⌘Z angrer).

Analysene lagres, så det går mye raskere neste gang samme mappe åpnes.

## Tastatursnarveier
| Tast | Handling |
|---|---|
| ← → | Flytt mellom bildene |
| ↑ ↓ | Forrige/neste gruppe |
| Mellomrom | Velg/fjern valg på bildet |
| 1–9 | Velg *kun* bilde nr. n |
| Enter | Behold valgte, flytt resten til Papirkurven, gå til neste gruppe |
| S | Hopp over gruppen (behold alt) |
| F | Fullskjerm med zoom (+/−, 0, dobbeltklikk = 100 %) |
| V | I fullskjerm: bla kun mellom valgte bilder (bytt fram og tilbake) |
| C | Spør Claude |
| ⌫ | Flytt bildet i fokus til Papirkurven med en gang (virker også for enkeltbilder) |
| K | Kopier bildet til aktiv samling / fjern det igjen |
| ⌘Z | Angre siste sletting (gruppe eller enkeltbilde) |

## Samlinger (kalender, fotobok …)
Velg **📌 Samling** i verktøylinjen og lag en mappe, for eksempel `Julekalender2026`. Trykk **K**, eller 📌 på bildet, så **kopieres** bildet dit med navnet

```
Sommerferie_2026-07-14_16-44-18_20260714_164418.jpg
<mappen bildet lå i>_<opptaksdato>_<originalt filnavn>
```

Originalen røres ikke. Trykker du K igjen, flyttes kopien til Papirkurven. Merkede bilder blir automatisk valgt som «behold». Merkingen leses fra mappen selv, så den huskes mellom gangene. Du kan bytte mellom flere samlinger i menyen.

## Installere
Krever macOS 15 eller nyere og Xcode (eller Command Line Tools). Du trenger **ikke** betalt Apple Developer-konto.

```bash
scripts/build-app.sh --install
```

Appen havner i `/Applications/ImageSort.app` og kan startes fra Spotlight.

## «Spør Claude»
Bruker [Claude Code](https://claude.com/claude-code) på Macen, og dermed Claude-abonnementet ditt. Ingen API-nøkkel trengs.
1. Installer Claude Code og kjør `claude` én gang i Terminal for å logge inn.
2. I ImageSort trykker du **C** i en gruppe. Små kopier (768 px) av bildene sendes til Claude, som velger det beste og forklarer hvorfor.

Modell velges i Innstillinger (⌘,). Uten Claude fungerer alt annet helt offline.

## Innstillinger (⌘,)
- **Tidsvindu:** hvor lang pause det kan være mellom bilder i samme serie.
- **Likhet:** hvor like bildene må være for å havne i samme gruppe.

## Utvikling
```bash
swift build && swift run          # kjør i utviklingsmodus
swift test                        # enhetstester
IMAGESORT_CALIBRATE_DIR=~/bilder swift test --filter Calibration   # skriv ut avstander/scorer
```
