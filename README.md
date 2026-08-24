# gain. leads

Lead-Marktplatz für Fitness-Coaches im DACH-Raum — Prototyp.
Statische Single-File-App (HTML/CSS/JS, keine Build-Tools, keine Abhängigkeiten).

## Inhalt

- `index.html` — komplette Anwendung: Landingpage, Login, Registrierung, Coach-Dashboard
- `vercel.json` — Security-Header und Caching
- `robots.txt`, `sitemap.xml` — SEO-Basis

## Lokal ansehen

Datei per Doppelklick im Browser öffnen. Alternativ:

    npx serve .

## Deployment

Push auf `main` löst bei verbundenem Vercel-Projekt automatisch ein Deployment aus.

## Stand

Alle Daten sind Mock-Daten im Arbeitsspeicher. Kein Backend, keine Persistenz,
keine echte Zahlungsabwicklung. Login funktioniert mit beliebigen Eingaben.
