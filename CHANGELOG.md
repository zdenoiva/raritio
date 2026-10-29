# Changelog

## [0.3.7] - 2026-10-29

- QR kódy pre zdieľanie a pozvánky fungujú cez HTTPS stránku.
- Pri mojom profile pribudla ikonka **Môj QR kód**.
- Ak kamoš Raritio nemá, stránka mu ponúkne aktuálne APK na stiahnutie.
- Pridaná jednoduchá Raritio landing page na GitHub Pages.
- Opravené načítanie QR z webového odkazu v appke.

## [0.3.6] - 2026-10-29

- Moderné výberové okno radenia kariet namiesto natívneho selectu.
- Zálohy sa ukladajú do `Downloads/Raritio`.
- Automatické aj manuálne zálohy sa v Downloads držia maximálne 5.
- Opravené a doplnené Supabase RLS migrácie.

## [0.3.5] - 2026-10-29

- Opravené RLS pravidlá pre zdieľané balíky (infinite recursion).
- Opravené pridávanie a odoberanie kamošov.
- Manuálna kontrola aktualizácií v Nastaveniach.
- Zdieľaný zoznam sa automaticky obnovuje každých 30 sekúnd.
- Doplnené bezpečnejšie Supabase migrácie.

## [0.3.4] - 2026-10-29

Prvý Raritio beta build.

- Rebrand z Holodex TCG na **Raritio**.
- Nový package `sk.zdenoiva.raritio`.
- Nová ikona aplikácie.
- Nové číslovanie verzií: `0.3.4` bez zátvoriek.
- Vlastné balíky, radenie a presúvanie kariet.
- Vlastné fotky kariet s badge **Custom**.
- Zdieľané balíky cez Supabase (read-only pre kamošov).
- QR kódy, Android share menu a friend kódy.
- Automatická kontrola aktualizácií z GitHub Releases.
- Supabase keepalive workflow pre free tier.
