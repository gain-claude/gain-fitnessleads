-- ============================================================
-- gain. leads — Rechte
-- Nach 01: schema.sql und 02: logic.sql ausfuehren.
--
-- Ohne diese Vergabe darf der oeffentliche Schluessel (anon)
-- nichts aufrufen und der Fragebogen laeuft ins Leere.
-- Grundsatz: so wenig wie moeglich freigeben.
-- ============================================================

-- Niemand kommt direkt an die Tabellen. Alles laeuft ueber die
-- View bzw. ueber Funktionen, die genau eine Sache tun.
revoke all on leads           from anon, authenticated;
revoke all on lead_consents   from anon, authenticated;
revoke all on lead_sources    from anon, authenticated;
revoke all on lead_verifications from anon, authenticated;

-- Marktplatz: Vorschau ohne Kontaktdaten, nur fuer angemeldete Coaches
grant select on lead_preview to authenticated;

-- Interessenten legen Anfragen an, ohne angemeldet zu sein.
-- create_lead laeuft als security definer und schreibt nur das,
-- was im Fragebogen steht — lesen kann anon damit nichts.
grant execute on function create_lead(jsonb) to anon;

-- Freischaltung ausschliesslich fuer angemeldete Coaches
grant execute on function purchase_lead(uuid, uuid) to authenticated;
grant execute on function coach_discount(uuid)      to authenticated;
grant execute on function matching_coaches(uuid)    to authenticated;

-- Aktivierung nach bestaetigter Nummer laeuft serverseitig,
-- nicht aus dem Browser
revoke execute on function activate_lead(uuid) from anon, authenticated;

-- Eigene Daten des Coaches
grant select, update on coaches            to authenticated;
grant select         on lead_purchases     to authenticated;
grant select, insert on purchase_messages  to authenticated;
grant select, insert on purchase_activities to authenticated;
grant select, insert on refund_requests    to authenticated;
grant select         on invoices           to authenticated;
grant select         on categories         to anon, authenticated;

-- ------------------------------------------------------------
-- Hinweis zur View
-- ------------------------------------------------------------
-- lead_preview laeuft mit den Rechten ihres Besitzers und umgeht
-- damit die Row Level Security auf leads — genau so gewollt, denn
-- sie enthaelt bewusst keine Kontaktdaten. Die View NICHT auf
-- security_invoker umstellen und ihr NIEMALS phone, email oder
-- last_name hinzufuegen, sonst stehen alle Kontaktdaten offen.

-- ------------------------------------------------------------
-- Pruefen, ob es sitzt
-- ------------------------------------------------------------
-- Als anon (oeffentlicher Schluessel) sollte gelten:
--   select * from lead_preview;   -> Fehler, keine Berechtigung
--   select * from leads;          -> Fehler, keine Berechtigung
--   select create_lead('{}'::jsonb); -> Fehler wegen fehlender Felder,
--                                       aber NICHT wegen Berechtigung
