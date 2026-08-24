# Datenbank

Postgres-Schema und Logik fuer gain. leads. Ausgelegt auf Supabase,
laeuft aber auf jedem Postgres ab Version 14.

## Reihenfolge

1. `schema.sql` — Tabellen, Typen, Indizes
2. `logic.sql` — Kategorien, Preisbildung, Freischaltung, Matching, Row Level Security

Im Supabase-Projekt unter SQL Editor nacheinander ausfuehren.

## Danach verbinden

In beiden HTML-Dateien stehen oben zwei leere Konstanten:

    const SUPABASE_URL = '';
    const SUPABASE_ANON_KEY = '';

Beide Werte stehen im Supabase-Projekt unter Settings → API.
Solange sie leer sind, laufen beide Seiten im Testbetrieb mit
erzeugten Beispieldaten — nichts wird geschrieben oder gelesen.

- `anfrage.html` ruft dann `create_lead()` auf und fordert den SMS-Code an
- `index.html` liest den Marktplatz aus der View `lead_preview`
  und schaltet ueber `purchase_lead()` frei

## Was noch fehlt

Drei Dinge lassen sich nicht in SQL loesen, weil sie externe
Dienste ansprechen. Sie gehoeren in Supabase Edge Functions,
damit die Zugangsdaten nicht im Browser landen:

- `request_phone_code()` und `verify_phone_code()` — SMS ueber Twilio
  oder MessageBird, Code nur als Hash speichern
- Benachrichtigung passender Coaches nach `activate_lead()`
  (Push und E-Mail an die Treffer aus `matching_coaches()`)
- Monatsabrechnung: alle `lead_purchases` mit `state = 'aktiv'`
  des Vormonats zu einer Rechnung buendeln und ueber Stripe einziehen

## Zwei Fallen

**Slots.** `purchase_lead()` sperrt die Lead-Zeile mit `for update`.
Wer die Freischaltung an dieser Funktion vorbei baut, verkauft
denselben Lead bei gleichzeitigen Klicks an mehr als vier Coaches.

**Kontaktdaten.** Die View `lead_preview` enthaelt bewusst keine
Telefonnummer und keinen vollstaendigen Namen. Der Marktplatz darf
ausschliesslich diese View lesen. Die Tabelle `leads` ist per Policy
an eine aktive Freischaltung gebunden — diese Regel nicht lockern,
sonst stehen alle Kontaktdaten im Netzwerk-Tab des Browsers.
