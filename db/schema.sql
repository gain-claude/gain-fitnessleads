-- ============================================================
-- gain. leads — Datenbankschema (PostgreSQL / Supabase)
-- Stand: Entwurf. Vor Produktivbetrieb pruefen lassen.
-- ============================================================

create extension if not exists "pgcrypto";

-- ------------------------------------------------------------
-- Stammdaten
-- ------------------------------------------------------------

create table categories (
  id            smallserial primary key,
  slug          text not null unique,          -- abnehmen, natural, bodybuilding, ...
  name_de       text not null,
  name_en       text not null,
  base_price_ct integer not null,               -- Basispreis in Cent, netto
  sort_order    smallint not null default 0,
  active        boolean not null default true
);

-- ------------------------------------------------------------
-- Coaches (Kaeuferseite)
-- ------------------------------------------------------------

create type coach_status as enum ('aktiv','pausiert','gesperrt');

create table coaches (
  id                 uuid primary key default gen_random_uuid(),
  auth_user_id       uuid unique,               -- Supabase auth.users
  email              citext not null unique,
  first_name         text not null,
  last_name          text not null,
  phone              text,
  company            text,
  vat_id             text,                      -- USt-IdNr. fuer Rechnung
  billing_address    jsonb,
  zip                text,
  city               text,
  radius_km          smallint not null default 50,
  price_min_ct       integer,                   -- eigener Angebotsrahmen
  price_max_ct       integer,
  monthly_limit_ct   integer not null default 40000,
  auto_unlock        boolean not null default false,
  auto_max_price_ct  integer,
  welcome_left       smallint not null default 3,   -- 50 % auf die ersten drei
  status             coach_status not null default 'aktiv',
  created_at         timestamptz not null default now()
);

-- Welche Kategorien und Formate ein Coach bedient (steuert das Matching)
create table coach_categories (
  coach_id    uuid not null references coaches(id) on delete cascade,
  category_id smallint not null references categories(id),
  primary key (coach_id, category_id)
);

create type coaching_format as enum ('online','vor_ort','hybrid');

create table coach_formats (
  coach_id uuid not null references coaches(id) on delete cascade,
  format   coaching_format not null,
  primary key (coach_id, format)
);

-- Verknuepftes gain.-Konto. Traegt den 30-%-Rabatt und wird laufend
-- neu geprueft — der Rabatt haengt am aktiven Abo, nicht am Haekchen.
create table gain_accounts (
  coach_id        uuid primary key references coaches(id) on delete cascade,
  gain_user_id    text not null,
  gain_email      citext not null,
  plan            text not null,               -- free | pro | ...
  subscription_ok boolean not null default false,
  linked_at       timestamptz not null default now(),
  last_checked_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- Leads (Interessentenseite)
-- ------------------------------------------------------------

create type lead_status as enum ('neu','pruefung','offen','ausverkauft','abgelaufen','abgelehnt');
create type start_timing  as enum ('sofort','zwei_wochen','vier_wochen','flexibel');
create type experience    as enum ('anfaenger','wiedereinsteiger','fortgeschritten','sehr_erfahren');

create table leads (
  id             uuid primary key default gen_random_uuid(),
  public_ref     text not null unique,          -- GL-4123, im UI sichtbar
  first_name     text not null,
  last_name      text not null,
  email          citext not null,
  phone          text not null,
  zip            text not null,
  city           text,
  country        char(2) not null default 'DE',
  lat            numeric(9,6),                  -- fuer Umkreissuche
  lng            numeric(9,6),
  category_id    smallint not null references categories(id),
  format         coaching_format not null,
  budget_min_ct  integer not null,
  budget_max_ct  integer not null,
  start_timing   start_timing not null,
  experience     experience not null,
  birth_year     smallint,                      -- Minderjaehrigkeit pruefen
  free_text      text,
  price_ct       integer not null,              -- Verkaufspreis, bei Anlage berechnet
  max_slots      smallint not null default 4,
  slots_taken    smallint not null default 0,
  status         lead_status not null default 'neu',
  quality_score  smallint,
  created_at     timestamptz not null default now(),
  expires_at     timestamptz not null default now() + interval '14 days',
  constraint slots_ok check (slots_taken <= max_slots),
  constraint budget_ok check (budget_max_ct >= budget_min_ct)
);

create index on leads (status, category_id, created_at desc);
create index on leads (zip);

-- Herkunft: beantwortet, welcher Kanal Leads liefert, die auch gekauft werden
create table lead_sources (
  lead_id      uuid primary key references leads(id) on delete cascade,
  channel      text,                            -- meta | google | instagram | newsletter | organisch
  utm_source   text,
  utm_medium   text,
  utm_campaign text,
  utm_content  text,
  landing_path text,
  referrer     text,
  cost_ct      integer                          -- spaeter aus dem Werbekonto zurueckgeschrieben
);

-- Verifizierung von Telefon und E-Mail
create type verify_channel as enum ('sms','email');

create table lead_verifications (
  id          uuid primary key default gen_random_uuid(),
  lead_id     uuid not null references leads(id) on delete cascade,
  channel     verify_channel not null,
  code_hash   text not null,                    -- nie im Klartext
  attempts    smallint not null default 0,
  expires_at  timestamptz not null,
  verified_at timestamptz
);

-- DSGVO-Nachweis. Muss die Einwilligung so festhalten, dass sie
-- Jahre spaeter noch belegbar ist — inklusive des exakten Textes.
create table lead_consents (
  id            uuid primary key default gen_random_uuid(),
  lead_id       uuid not null references leads(id) on delete cascade,
  purpose       text not null,                  -- weitergabe_coaches | kontaktaufnahme
  text_version  text not null,                  -- z. B. 2026-08-v3
  text_snapshot text not null,                  -- Wortlaut zum Zeitpunkt der Zustimmung
  ip            inet,
  user_agent    text,
  given_at      timestamptz not null default now(),
  revoked_at    timestamptz
);

-- ------------------------------------------------------------
-- Freischaltungen, Pipeline, Abrechnung
-- ------------------------------------------------------------

create type purchase_state as enum ('aktiv','erstattet');
create type sales_stage    as enum ('neu','kontaktiert','im_gespraech','kunde','kein_interesse');
create type discount_kind  as enum ('keiner','willkommen','gain');

create table lead_purchases (
  id             uuid primary key default gen_random_uuid(),
  lead_id        uuid not null references leads(id),
  coach_id       uuid not null references coaches(id),
  list_price_ct  integer not null,
  paid_ct        integer not null,
  discount_kind  discount_kind not null default 'keiner',
  discount_pct   smallint not null default 0,
  state          purchase_state not null default 'aktiv',
  stage          sales_stage not null default 'neu',
  note           text,
  invoice_id     uuid,
  purchased_at   timestamptz not null default now(),
  first_contact_at timestamptz,
  unique (lead_id, coach_id)                     -- niemand kauft denselben Lead zweimal
);

create index on lead_purchases (coach_id, purchased_at desc);

create table purchase_activities (
  id           bigserial primary key,
  purchase_id  uuid not null references lead_purchases(id) on delete cascade,
  kind         text not null,                   -- anruf | whatsapp | email | nachricht | status
  detail       text,
  created_at   timestamptz not null default now()
);

create table purchase_messages (
  id          bigserial primary key,
  purchase_id uuid not null references lead_purchases(id) on delete cascade,
  from_coach  boolean not null,
  body        text not null,
  sent_at     timestamptz not null default now(),
  read_at     timestamptz
);

create type refund_state as enum ('offen','anerkannt','abgelehnt');

create table refund_requests (
  id          uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references lead_purchases(id) on delete cascade,
  reason      text not null,                    -- nummer_falsch | doppelt | kein_interesse | angaben_falsch | minderjaehrig
  note        text,
  state       refund_state not null default 'offen',
  created_at  timestamptz not null default now(),
  decided_at  timestamptz,
  decided_by  uuid
);

create type invoice_state as enum ('entwurf','offen','bezahlt','fehlgeschlagen','storniert');

create table invoices (
  id                uuid primary key default gen_random_uuid(),
  coach_id          uuid not null references coaches(id),
  number            text unique,                -- RE-2026-08-0042
  period_start      date not null,
  period_end        date not null,
  net_ct            integer not null default 0,
  vat_ct            integer not null default 0,
  gross_ct          integer not null default 0,
  state             invoice_state not null default 'entwurf',
  stripe_invoice_id text,
  issued_at         timestamptz,
  paid_at           timestamptz,
  unique (coach_id, period_start, period_end)
);

alter table lead_purchases
  add constraint fk_invoice foreign key (invoice_id) references invoices(id);

-- ------------------------------------------------------------
-- Benachrichtigungen
-- ------------------------------------------------------------

create table notifications (
  id         bigserial primary key,
  coach_id   uuid not null references coaches(id) on delete cascade,
  lead_id    uuid references leads(id),
  channel    text not null,                     -- push | email | sms
  subject    text,
  sent_at    timestamptz not null default now(),
  opened_at  timestamptz
);

-- ------------------------------------------------------------
-- Hinweise zur Umsetzung
-- ------------------------------------------------------------
-- 1) Kontaktdaten eines Leads (email, phone, last_name) duerfen erst
--    nach einer aktiven Zeile in lead_purchases sichtbar sein.
--    In Supabase ueber Row Level Security loesen, nicht im Frontend.
--
-- 2) slots_taken nur in einer Transaktion mit SELECT ... FOR UPDATE
--    hochzaehlen, sonst wird ein Lead bei gleichzeitigen Kaeufen
--    fuenfmal verkauft.
--
-- 3) Der 30-%-Rabatt liest gain_accounts.subscription_ok zum Zeitpunkt
--    des Kaufs — nicht einmalig beim Verknuepfen.
--
-- 4) leads.expires_at raeumt unverkaufte Anfragen ab. Danach anonymisieren
--    statt loeschen, damit lead_sources fuer die Kanalauswertung erhalten bleibt.
--
-- 5) Loeschersuchen nach Art. 17 DSGVO: Klarnamen, E-Mail, Telefon und
--    free_text ueberschreiben, Kennzahlen behalten.
