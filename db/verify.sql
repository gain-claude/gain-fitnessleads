-- ============================================================
-- gain. leads — Telefonbestaetigung
--
-- ACHTUNG: Testfassung ohne SMS-Versand und ohne Hashing.
-- Der Code ist fest auf 123456 gesetzt, damit die Kette vom
-- Fragebogen bis in den Marktplatz durchlaeuft.
--
-- Bewusst ohne digest(): Supabase legt pgcrypto im Schema
-- "extensions" ab, nicht in "public". Ein blosser Aufruf von
-- digest() scheitert deshalb in security-definer-Funktionen.
-- Die spaetere Edge Function hasht ohnehin ausserhalb der
-- Datenbank — dann faellt das Thema weg.
-- ============================================================

create or replace function request_phone_code(p_lead_id uuid)
returns void language plpgsql security definer
set search_path = public as $$
begin
  delete from lead_verifications
   where lead_id = p_lead_id and channel = 'sms' and verified_at is null;

  insert into lead_verifications (lead_id, channel, code_hash, expires_at)
  values (p_lead_id, 'sms', '123456', now() + interval '30 minutes');
end $$;

create or replace function verify_phone_code(p_lead_id uuid, p_code text)
returns boolean language plpgsql security definer
set search_path = public as $$
declare
  v lead_verifications%rowtype;
begin
  select * into v
    from lead_verifications
   where lead_id = p_lead_id and channel = 'sms' and verified_at is null
   order by expires_at desc limit 1;

  if not found       then return false; end if;
  if v.expires_at < now() then return false; end if;
  if v.attempts >= 5 then return false; end if;

  update lead_verifications set attempts = attempts + 1 where id = v.id;

  if v.code_hash <> p_code then
    return false;
  end if;

  update lead_verifications set verified_at = now() where id = v.id;
  update leads set phone_verified_at = now(), email_verified_at = now()
   where id = p_lead_id;

  perform activate_lead(p_lead_id);
  return true;
end $$;

-- activate_lead und create_lead ebenfalls auf festen search_path setzen,
-- damit sie unabhaengig vom Aufrufer dieselben Tabellen finden
alter function activate_lead(uuid) set search_path = public;
alter function create_lead(jsonb)  set search_path = public;
alter function purchase_lead(uuid, uuid) set search_path = public;

grant execute on function request_phone_code(uuid)      to anon;
grant execute on function verify_phone_code(uuid, text) to anon;

-- ------------------------------------------------------------
-- Pruefen
-- ------------------------------------------------------------
-- 1) Kam ueberhaupt etwas an?
--    select public_ref, first_name, status, price_ct, created_at
--      from leads order by created_at desc limit 5;
--
-- 2) Haengengebliebene Anfragen freischalten:
--    select activate_lead(id) from leads where status = 'neu';
--
-- 3) Sieht der Marktplatz sie?
--    select public_ref, first_name, last_initial, price_ct from lead_preview;
--
-- Liefert 3) Zeilen, aber die Seite bleibt leer, liegt es nicht an
-- der Datenbank, sondern an der Verbindung im Browser.
