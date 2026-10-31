# Supabase setup pre Raritio

Projekt: **Raritio** (`tqcqxestnrucblwtwkck`)

## 1. Vytvorenie tabuliek

1. Otvor [SQL Editor](https://supabase.com/dashboard/project/tqcqxestnrucblwtwkck/sql/new).
2. Skopíruj celý obsah [`schema.sql`](schema.sql).
3. Vlož ho do editora a klikni **Run**.
4. Po úspechu by mali existovať tabuľky `profiles`, `friendships`, `shared_binders`, `shared_binder_access` a `keepalive`.

## 2. Anonymous sign-in

1. Otvor [Authentication → Providers](https://supabase.com/dashboard/project/tqcqxestnrucblwtwkck/auth/providers).
2. Zapni **Anonymous sign-ins**.
3. Ulož zmeny.

Raritio používa anonymný Supabase účet + prezývku a friend kód. Bez zapnutého anonymous sign-in sa Zdieľané neprihlási.

## 3. Keepalive

GitHub Actions workflow `supabase-keepalive.yml` pingne tabuľku `keepalive` v pondelok a štvrtok. Free projekt sa tak nezastaví po 7 dňoch nečinnosti.

Workflow potrebuje repository secrets:

- `SUPABASE_URL` = `https://tqcqxestnrucblwtwkck.supabase.co`
- `SUPABASE_ANON_KEY` = anon public key

Anon key je verejný, ale držíme ho v secrets, aby nebol v kóde.

## 4. Migrácia 0.4.1\n\nPre skryté štatistiky spusti v SQL Editore aj:\n\n```text\nsupabase/2026-10-31_public_stats.sql\n```\n\n## 5. Migrácia 0.3.16

Pred inštaláciou verzie 0.3.16 spusti v SQL Editore:

```text
supabase/2026-10-31_account_privacy.sql
```

Migrácia:

- odstráni z profilu stĺpec `email`,
- pridá `delete_my_account()`,
- skryje `share_token` pred bežnými používateľmi a sprístupní ho len ownerovi cez RPC,
- opraví odobratie kamoša tak, aby mu zrušilo aj prístup k zdieľaným balíkom,
- opraví hromadné nastavenie kamošov.

## 5. Overenie

V SQL Editore môžeš spustiť:

```sql
select id, last_ping from public.keepalive;
```

Alebo manuálne spustiť workflow **Supabase keepalive** v GitHub Actions.

## Free tier

Free projekt má 500 MB DB, 1 GB storage a po 7 dňoch úplnej nečinnosti sa pauzne. Keepalive ping ho udrží aktívny. Ak by sa napriek tomu pauznul, treba ho v Supabase manuálne resume.
