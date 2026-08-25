-- ============================================================
-- gain. leads — Korrekturen aus dem ersten Live-Durchlauf
-- Diese Aenderungen sind in der Datenbank bereits angewandt.
-- Datei dient der Nachvollziehbarkeit und einem Neuaufbau.
-- ============================================================

-- 1) Zwei Spalten fehlten im urspruenglichen schema.sql,
--    werden aber von verify_phone_code gesetzt.
alter table leads add column if not exists phone_verified_at timestamptz;
alter table leads add column if not exists email_verified_at timestamptz;

-- 2) lead_preview enthielt weder category_slug noch age.
--    Beide werden vom Marktplatz erwartet; ohne sie blieb die
--    Kartenansicht leer. Kontaktdaten bleiben weiterhin aussen vor.
drop view if exists lead_preview;
create view lead_preview as
  select l.id,
         l.public_ref,
         l.first_name,
         left(l.last_name, 1) || '.' as last_initial,
         c.slug as category_slug,
         l.zip, l.city, l.format,
         l.budget_min_ct, l.budget_max_ct,
         l.start_timing, l.experience,
         case when l.birth_year is not null
              then extract(year from now())::int - l.birth_year else null end as age,
         null::int as distance_km,
         l.free_text, l.price_ct, l.max_slots, l.slots_taken, l.created_at
    from leads l
    join categories c on c.id = l.category_id
   where l.status = 'offen';

grant select on lead_preview to anon, authenticated;

-- 3) Alle Funktionen mit festem search_path, sonst finden sie in
--    security-definer-Kontexten die Tabellen nicht zuverlaessig.

-- 4) Kein digest() mehr: Supabase legt pgcrypto im Schema "extensions"
--    ab, nicht in "public". Der Testcode wird im Klartext verglichen.
--    Faellt weg, sobald die Edge Function den Versand uebernimmt.

-- ------------------------------------------------------------
-- Geprueft am ersten Durchlauf
-- ------------------------------------------------------------
-- create_lead()        -> legt Lead, Herkunft und Einwilligung an
-- request_phone_code() -> hinterlegt den Testcode 123456
-- verify_phone_code()  -> bestaetigt und ruft activate_lead()
-- lead_preview         -> zeigt die Anfrage ohne Kontaktdaten
-- Preisbildung         -> Abnehmen, 150 EUR Budget, sofort = 32,90 EUR

-- ------------------------------------------------------------
-- Offen
-- ------------------------------------------------------------
-- purchase_lead() ist nur fuer 'authenticated' freigegeben. Solange
-- die Coach-Anmeldung nicht an Supabase Auth haengt, ist der Browser
-- 'anon' und das Freischalten schlaegt fehl. Das ist Absicht: die
-- Funktion gibt Kontaktdaten frei und darf nicht offenstehen.
