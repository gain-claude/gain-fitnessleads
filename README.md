# gain. leads

Lead-Marktplatz fuer Fitness-Coaches im DACH-Raum - Prototyp.
Statische Single-File-App (HTML/CSS/JS, keine Build-Tools, keine Abhaengigkeiten).

## Inhalt

- `index.html` - komplette Anwendung: Landingpage, Login, Registrierung, Coach-Dashboard
- `vercel.json` - Security-Header und Caching
- `robots.txt`, `sitemap.xml` - SEO-Basis

## Lokal ansehen

Datei per Doppelklick im Browser oeffnen. Alternativ:

    npx serve .

## Deployment

Push auf `main` loest bei verbundenem Vercel-Projekt automatisch ein Deployment aus.
Framework-Preset: Other. Build Command und Output Directory bleiben leer.

## Stand

Alle Daten sind Mock-Daten im Arbeitsspeicher. Kein Backend, keine Persistenz,
keine echte Zahlungsabwicklung. Der Login akzeptiert beliebige Eingaben.
