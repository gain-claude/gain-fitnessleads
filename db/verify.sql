-- ============================================================
-- gain. leads — Telefonbestaetigung
--
-- ACHTUNG: Testfassung ohne SMS-Versand.
-- Der Code ist fest auf 123456 gesetzt, damit die Kette vom
-- Fragebogen bis in den Marktplatz durchlaeuft, solange kein
-- SMS-Anbieter angebunden ist.
-- Vor dem Livegang durch eine Edge Function ersetzen, die einen
-- Zufallscode erzeugt, ihn per Twilio verschickt und nur den
-- Hash speichert. Die Stelle ist unten markiert.
-- ============================================================

-- Nach 01: schema.sql, 02: logic.sql, 03: grants.sql ausfuehren.

create or replace function request_phone_code(p_lead_id uuid)
returns void language plpgsql security definer as $$
declare
  code text := '123456';   -- TESTFASSUNG. Spaeter: lpad((floor(random()*1000000))::text, 6, '0')
begin
  delete from lead_verifications
   where lead_id = p_lead_id and channel = 'sms' and verified_at is null;

  insert into lead_verifications (lead_id, channel, code_hash, expires_at)
  values (p_lead_id, 'sms', encode(digest(code, 'sha256'), 'hex'), now() + interval '15 minutes');

  -- HIER wuerde die Edge Function den Code per SMS verschicken.
end $$;

create or replace function verify_phone_code(p_lead_id uuid, p_code text)
returns boolean language plpgsql security definer as $$
declare
  v lead_verifications%rowtype;
begin
  select * into v
    from lead_verifications
   where lead_id = p_lead_id and channel = 'sms' and verified_at is null
   order by expires_at desc limit 1;

  if not found then return false; end if;
  if v.expires_at < now() then return false; end if;
  if v.attempts >= 5 then return false; end if;

  update lead_verifications set attempts = attempts + 1 where id = v.id;

  if v.code_hash <> encode(digest(p_code, 'sha256'), 'hex') then
    return false;
  end if;

  update lead_verifications set verified_at = now() where id = v.id;
  update leads set phone_verified_at = now(), email_verified_at = now() where id = p_lead_id;

  -- Setzt den Status auf 'offen' und berechnet den Preis mit
  -- Verifizierungszuschlag neu — ab hier erscheint die Anfrage
  -- im Marktplatz.
  perform activate_lead(p_lead_id);
  return true;
end $$;

grant execute on function request_phone_code(uuid)       to anon;
grant execute on function verify_phone_code(uuid, text)  to anon;

-- ------------------------------------------------------------
-- Bereits angelegte Testanfragen nachtraeglich freischalten
-- ------------------------------------------------------------
-- Anfragen, die vor dieser Datei angelegt wurden, haengen im
-- Status 'neu' fest. Diese Zeile holt sie nach:
--
--   select activate_lead(id) from leads where status = 'neu';
--
-- Danach im Marktplatz sichtbar.
