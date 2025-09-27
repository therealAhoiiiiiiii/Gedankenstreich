```text
Runbook: Restore / Quick developer checklist
Branch: restore/runbook
Commit message suggestion: "chore(runbook): add restore/runbook with quick start steps"

Zweck
- Kurz und versioniert im Repo: die wichtigsten Befehle zum sicheren Wechseln auf restore-geniestreich, Testen des Dev-Servers, Diagnose des body‑Hintergrunds und Wiederherstellen deines WIP.

1) Safety — falls noch ungesicherte Änderungen vorhanden:
   git status
   git stash push -u -m "WIP before restore-runbook"
   Erwartet: "Saved working directory and index state..."

2) Holen + Checkout des Remote-Branches:
   git fetch origin
   git checkout restore-geniestreich
   git pull --ff-only origin restore-geniestreich
   Stop‑If: Git verlangt Stash wegen Überschreibungen → git stash push -u -m "WIP before switching (auto)" und wiederhole.

3) Dev-Server starten:
   npm run dev
   - Im Browser: DevTools → Network → Disable cache → Hard‑Reload (Ctrl+Shift+R)

4) Browser-Check: Hintergrund prüfen (Pflichtausgabe)
   In Console:
     console.log(getComputedStyle(document.body).backgroundImage)
   - Erwartet: url("...")  (NICHT "none")
   - Bitte hier die komplette Console‑Zeile als Ergebnis einfügen.

5) Falls result === "none" → Diagnose (Console):
   (function(){
     const out=[];
     for(const ss of document.styleSheets){
       try{
         const rules = ss.cssRules;
         for(const r of rules){
           if(r && r.selectorText && r.selectorText.includes('body') && /background/.test(r.cssText)){ 
             out.push({sheet:ss.href||'inline', selector:r.selectorText, css:r.cssText});
           }
         }
       }catch(e){}
     }
     console.log(out);
     console.log('stylesheets:', [...document.styleSheets].map(s=>s.href||'inline'));
   })();
   - Pflicht: kopiere die komplette Ausgabe (out array + stylesheets list).

6) Prüfe, ob die Bilddatei vorhanden ist (Projekt-Root):
   - Windows: dir public\hintergrund.jpg
   - Unix: ls -l public/hintergrund.jpg
   - Browser Network Tab: lade /hintergrund.jpg → Status 200 oder 404
   - Pflicht: Datei vorhanden? (ja/nein) + Network-Status (200/404)

7) WIP wiederherstellen (sicherer Weg in eigenen Branch):
   git stash list
   (Notiere: z.B. stash@{0})
   git stash branch wip-before-restore-geniestreich stash@{0}
   - Erwartet: neuer Branch erzeugt und Stash angewendet
   - Bei Konflikten: löse sie, git add <files>, git commit -m "Resolve conflicts from stash"

8) Abschließender Quick-Check:
   git status --short
   git branch --show-current
   - Erwartet: du stehst nun auf wip-before-restore-geniestreich (oder restore-geniestreich, je nach Wahl)

Was hier als Antwort nötig ist (Pflichtausgaben, damit ich gezielt weiterhelfe)
- Die exakte Console‑Zeile: console.log(getComputedStyle(document.body).backgroundImage)
- Die git stash list Ausgabe (komplett)
- Falls Diagnose ausgeführt: die Console‑Ausgabe des Diagnose‑Snippets (out array + stylesheets list)
- Ob public/hintergrund.jpg vorhanden ist (ja/nein) und der Network-Status (200/404)

Optional: lokale Erstellung der Datei (falls du nicht remote willst)
- Kopiere den Inhalt dieses RUNBOOK.md in dein Projekt‑Root und committe:
  git add RUNBOOK.md
  git commit -m "chore(runbook): add restore/runbook"
  git push origin <branch>

Ende.