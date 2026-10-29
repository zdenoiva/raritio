# Raritio

Raritio je osobná Android aplikácia na správu zbierky Pokémon a MTG kariet. Umožňuje skenovanie kariet, sledovanie cien, vlastné balíky, vlastné fotky kariet a zdieľanie balíkov s kamošmi.

## Aktuálna verzia

- **0.3.4** (beta)
- Android package: `sk.zdenoiva.raritio`

## Funkcie

- Pokémon a MTG karty, ceny z Cardmarket / TCGdex / Scryfall
- Skenovanie kariet kamerou a OCR
- Vlastné balíky, radenie, presúvanie kariet
- Vlastné fotky kariet s badge **Custom**
- Zdieľané balíky cez Supabase (read-only pre kamošov)
- QR kódy a Android share menu
- Kontrola aktualizácií z GitHub Releases

## Zdieľanie balíkov

Zdieľanie používa **Supabase** (Auth, Postgres, RLS). Pred použitím je potrebné v Supabase:

1. Zapnúť **Authentication → Providers → Anonymous sign-ins**.
2. Spustiť SQL z [`supabase/schema.sql`](supabase/schema.sql) v SQL Editore.
3. Do GitHub Actions secrets pridať `SUPABASE_URL` a `SUPABASE_ANON_KEY`.

V appke: **Spravovať balík → Zdieľať balík**. Kamoš naskenuje QR alebo zadá kód v **Zdieľané**.

## Aktualizácie

Appka pri štarte maximálne raz za 24 hodín skontroluje [`latest.json`](latest.json) a ponúkne novšiu verziu. APK sa stiahne z GitHub Releases, overí sa SHA256 a otvorí sa systémový Android installer.

## Build

```bash
flutter pub get
flutter build apk --release
```

Release podpis vyžaduje `android/key.properties` a keystore mimo repozitára. Súbory `*.jks`, `key.properties` a lokálne APK sú v `.gitignore`.

## Release proces

1. Zvýšiť verziu v `pubspec.yaml` a `lib/app_version.dart`.
2. Doplniť `CHANGELOG.md` a `latest.json`.
3. Commitnúť a pushnúť.
4. Vytvoriť tag `v<verzia>` a pushnúť ho.
5. GitHub Actions postaví APK, podpíše ho, vytvorí Release a aktualizuje `latest.json`.

## Changelog

Pozri [`CHANGELOG.md`](CHANGELOG.md).
