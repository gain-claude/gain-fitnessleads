-- ============================================================
-- gain. leads — Logik, Sicherheit, Stammdaten
-- Nach 01: schema.sql ausfuehren.
-- ============================================================

-- ------------------------------------------------------------
-- Kategorien und Basispreise (Cent, netto)
-- ------------------------------------------------------------
insert into categories (slug, name_de, name_en, base_price_ct, sort_order) values
  ('ernaehrung',   'Ernährungsberatung',              'Nutrition Coaching',             1300, 10),
  ('reha',         'Rücken & Reha',                   'Back & Rehab',                   1500, 20),
  ('muskel',       'Muskelaufbau',                    'Muscle Building',                1800, 30),
  ('kraft',        'Kraftsport & Powerlifting',       'Strength & Powerlifting',        2000, 40),
  ('abnehmen',     'Abnehmen & Körperfett',           'Weight Loss & Body Fat',         2200, 50),
  ('pt',           'Personal Training',               'Personal Training',              3400, 60),
  ('wettkampf',    'Wettkampfvorbereitung',           'Contest Prep',                   4500, 70),
  ('natural',      'Natural Bodybuilding',            'Natural Bodybuilding',           4500, 80),
  ('bodybuilding', 'Bodybuilding',                    'Bodybuilding',                   5000, 90),
  ('exec',         'Führungskräfte & Vielbeschäftigte','Executives & Busy Professionals', 5800, 100),
  ('firma',        'Firmenfitness',                   'Corporate Fitness',              9500, 110)
on conflict (slug) do nothing;

-- ------------------------------------------------------------
-- Preisbildung
-- Basispreis der Kategorie plus Zuschlaege fuer Auftragswert,
-- Dringlichkeit und Verifizierung. Eine Stelle, an der der Preis
-- entsteht — nicht im Frontend.
-- ------------------------------------------------------------
create or replace function calc_lead_price(
  p_category_id smallint,
  p_budget_min_ct integer,
  p_start start_timing,
  p_phone_verified boolean
) returns integer language plpgsql immutable as $$
declare
  base integer;
  price integer;
begin
  select base_price_ct into base from categories where id = p_category_id;
  if base is null then raise exception 'Unbekannte Kategorie %', p_category_id; end if;

  price := base + round(p_budget_min_ct / 40.0);
  if p_budget_min_ct >= 25000 then price := price + 400; end if;   -- hoher Auftragswert
  if p_start = 'sofort'        then price := price + round(price * 0.20); end if;
  if p_phone_verified          then price := price + 200;
                               else price := round(price * 0.70); end if;
  return price;
end $$;

-- ------------------------------------------------------------
-- Rabattermittlung
-- Die beiden Nachlaesse addieren sich nicht — es gilt der hoehere.
-- Der gain.-Rabatt liest den Abo-Status zum Zeitpunkt des Kaufs.
-- ------------------------------------------------------------
create or replace function coach_discount(p_coach_id uuid)
returns table (kind discount_kind, pct smallint) language plpgsql stable as $$
declare
  welcome smallint := 0;
  gain    smallint := 0;
begin
  select case when welcome_left > 0 then 50 else 0 end into welcome
    from coaches where id = p_coach_id;

  select case when ga.subscription_ok then 30 else 0 end into gain
    from gain_accounts ga where ga.coach_id = p_coach_id;
  gain := coalesce(gain, 0);

  if welcome >= gain and welcome > 0 then
    return query select 'willkommen'::discount_kind, welcome;
  elsif gain > 0 then
    return query select 'gain'::discount_kind, gain;
  else
    return query select 'keiner'::discount_kind, 0::smallint;
  end if;
end $$;

-- ------------------------------------------------------------
-- Freischaltung
-- Sperrt die Lead-Zeile, damit bei gleichzeitigen Kaeufen niemals
-- mehr als max_slots Coaches denselben Lead bekommen.
-- ------------------------------------------------------------
create or replace function purchase_lead(p_lead_id uuid, p_coach_id uuid)
returns uuid language plpgsql security definer as $$
declare
  l           leads%rowtype;
  d_kind      discount_kind;
  d_pct       smallint;
  pay         integer;
  spent       integer;
  limit_ct    integer;
  new_id      uuid;
begin
  select * into l from leads where id = p_lead_id for update;   -- Sperre
  if not found then raise exception 'Lead nicht gefunden'; end if;
  if l.status <> 'offen' then raise exception 'Lead ist nicht mehr verfuegbar'; end if;
  if l.slots_taken >= l.max_slots then raise exception 'Alle Plaetze vergeben'; end if;

  if exists (select 1 from lead_purchases where lead_id = p_lead_id and coach_id = p_coach_id) then
    raise exception 'Lead bereits freigeschaltet';
  end if;

  select kind, pct into d_kind, d_pct from coach_discount(p_coach_id);
  pay := round(l.price_ct * (100 - d_pct) / 100.0);

  -- Monatslimit pruefen
  select monthly_limit_ct into limit_ct from coaches where id = p_coach_id;
  select coalesce(sum(paid_ct), 0) into spent
    from lead_purchases
   where coach_id = p_coach_id
     and state = 'aktiv'
     and purchased_at >= date_trunc('month', now());
  if spent + pay > limit_ct then raise exception 'Monatslimit erreicht'; end if;

  insert into lead_purchases (lead_id, coach_id, list_price_ct, paid_ct, discount_kind, discount_pct)
  values (p_lead_id, p_coach_id, l.price_ct, pay, d_kind, d_pct)
  returning id into new_id;

  update leads
     set slots_taken = slots_taken + 1,
         status = case when slots_taken + 1 >= max_slots then 'ausverkauft' else status end
   where id = p_lead_id;

  if d_kind = 'willkommen' then
    update coaches set welcome_left = welcome_left - 1 where id = p_coach_id;
  end if;

  return new_id;
end $$;

-- ------------------------------------------------------------
-- Matching: welche Coaches passen zu einem Lead
-- ------------------------------------------------------------
create or replace function matching_coaches(p_lead_id uuid)
returns setof uuid language sql stable as $$
  select c.id
    from leads l
    join coach_categories cc on cc.category_id = l.category_id
    join coaches c           on c.id = cc.coach_id
    join coach_formats cf    on cf.coach_id = c.id and cf.format = l.format
   where l.id = p_lead_id
     and c.status = 'aktiv'
     and (c.price_min_ct is null or c.price_min_ct <= l.budget_max_ct)
     and (c.price_max_ct is null or c.price_max_ct >= l.budget_min_ct)
$$;

-- ------------------------------------------------------------
-- Anfrage anlegen (wird vom Fragebogen aufgerufen)
-- Legt Lead, Herkunft und Einwilligung in einer Transaktion an.
-- ------------------------------------------------------------
create or replace function create_lead(payload jsonb)
returns jsonb language plpgsql security definer as $$
declare
  cat_id smallint;
  new_id uuid;
  ref    text;
  price  integer;
  bmin   integer := (payload->>'budget_min_ct')::integer;
  bmax   integer := (payload->>'budget_max_ct')::integer;
  st     start_timing := (payload->>'start_timing')::start_timing;
begin
  select id into cat_id from categories where slug = payload->>'category' and active;
  if cat_id is null then raise exception 'Unbekannte Kategorie'; end if;

  price := calc_lead_price(cat_id, bmin, st, false);   -- vor Verifizierung reduziert
  ref := 'GL-' || lpad((floor(random()*90000) + 10000)::text, 5, '0');

  insert into leads (public_ref, first_name, last_name, email, phone, zip, city,
                     category_id, format, budget_min_ct, budget_max_ct,
                     start_timing, experience, free_text, price_ct, status)
  values (ref, payload->>'first_name', payload->>'last_name', payload->>'email',
          payload->>'phone', payload->>'zip', payload->>'city',
          cat_id, (payload->>'format')::coaching_format, bmin, bmax,
          st, (payload->>'experience')::experience,
          nullif(payload->>'free_text',''), price, 'neu')
  returning id into new_id;

  insert into lead_sources (lead_id, channel, utm_source, utm_medium, utm_campaign, utm_content, landing_path, referrer)
  values (new_id, payload->'source'->>'channel', payload->'source'->>'utm_source',
          payload->'source'->>'utm_medium', payload->'source'->>'utm_campaign',
          payload->'source'->>'utm_content', payload->'source'->>'landing',
          payload->'source'->>'referrer');

  insert into lead_consents (lead_id, purpose, text_version, text_snapshot, ip, user_agent)
  values (new_id, 'weitergabe_coaches',
          payload->>'consent_version', payload->>'consent_text',
          nullif(payload->>'ip','')::inet, payload->>'user_agent');

  return jsonb_build_object('id', new_id, 'ref', ref);
end $$;

-- Nach bestaetigter Telefonnummer: Preis neu berechnen und freigeben
create or replace function activate_lead(p_lead_id uuid)
returns void language plpgsql security definer as $$
declare l leads%rowtype;
begin
  select * into l from leads where id = p_lead_id;
  update leads
     set price_ct = calc_lead_price(l.category_id, l.budget_min_ct, l.start_timing, true),
         status = 'offen'
   where id = p_lead_id;
end $$;

-- ------------------------------------------------------------
-- Row Level Security
-- Der Kern: Kontaktdaten eines Leads sind erst nach einer aktiven
-- Freischaltung sichtbar. Das gehoert in die Datenbank, nicht ins
-- Frontend — sonst liest jeder die Daten aus dem Netzwerk-Tab.
-- ------------------------------------------------------------
alter table leads           enable row level security;
alter table lead_purchases  enable row level security;
alter table coaches         enable row level security;
alter table purchase_messages enable row level security;
alter table invoices        enable row level security;

-- Vorschau ohne Kontaktdaten: eigene View fuer den Marktplatz
create or replace view lead_preview as
  select l.id, l.public_ref, l.first_name,
         left(l.last_name, 1) || '.' as last_initial,
         l.zip, l.city, l.category_id, l.format,
         l.budget_min_ct, l.budget_max_ct, l.start_timing, l.experience,
         l.free_text, l.price_ct, l.max_slots, l.slots_taken, l.created_at
    from leads l
   where l.status = 'offen';

create policy coach_reads_own on coaches
  for select using (auth_user_id = auth.uid());

create policy purchases_own on lead_purchases
  for select using (coach_id in (select id from coaches where auth_user_id = auth.uid()));

-- Vollstaendiger Lead nur mit aktiver Freischaltung
create policy lead_full_after_purchase on leads
  for select using (
    exists (
      select 1 from lead_purchases p
       join coaches c on c.id = p.coach_id
      where p.lead_id = leads.id
        and c.auth_user_id = auth.uid()
        and p.state = 'aktiv'
    )
  );

create policy messages_own on purchase_messages
  for all using (
    purchase_id in (
      select p.id from lead_purchases p
       join coaches c on c.id = p.coach_id
      where c.auth_user_id = auth.uid()
    )
  );

create policy invoices_own on invoices
  for select using (coach_id in (select id from coaches where auth_user_id = auth.uid()));
