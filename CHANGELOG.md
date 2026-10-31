# Changelog

## [0.3.19] - 2026-10-31

- OCR už nepoužíva generický auto-crop skenera; vracia sa osvedčený výrez na kartu.
- Pridané viac variantov výrezu a záložné OCR.
- Detekcia karty kontroluje pomer strán 63 : 88, takže odmietne TV, stôl alebo podložku.
- Automatické zachytenie sa spustí len pri karte so správnym pomerom.
- Výsledky zobrazujú typ karty: Pokémon / Trainer / Energy / MTG.
- Spodný rad zobrazí všetky dostupné návrhy, až 6 kariet.

## [0.3.18] - 2026-10-31

- Skener je celý na šírku aj výšku obrazovky, bez čiernych pásov.
- Výraznejší neonový rámik s rohovými akcentmi a stmavením okolia.
- Automatické zachytenie je citlivejšie na menšie karty.
- Rozpoznávanie skúsi aj záložný výrez, keď sa karta nedetekuje celá.
- Vyššie rozlíšenie spracovania pre lepšie OCR.

## [0.3.17] - 2026-10-31

- Skener má dynamický rámik, ktorý sleduje obrys karty.
- Automatické zachytenie, keď je karta zaostrená a stabilná.
- Po zachytení sa zobrazia 2–3 návrhy karty priamo v skeneri.
- Kartu pridáš jedným tlačidlom do aktuálneho balíka a skenuješ ďalej.
- Ak rozpoznanie zlyhá, skener ponúkne staré ručné hľadanie.
- Ponechaný manuálny spúšť, blesk, zoom a galéria.

## [0.3.16] - 2026-10-31

- Účet už neobsahuje email; zostáva anonymný Supabase účet, prezývka a vygenerovaný friend kód.
- Pribudla možnosť zmazať účet a všetky zdieľané dáta.
- RLS: share token je dostupný len ownerovi, odobratý kamoš stratí prístup a opravené je hromadné nastavenie kamošov.
- Externé odkazy (PriceCharting, eBay a ďalšie) sa otvárajú v oddelenom prehliadači s funkčným tlačidlom Späť.
- WebView má CSP, obrázky a externé URL sú sanitizované.
- Aktualizácie overujú nielen SHA256, ale aj podpis APK.
- Zálohy sú šifrované heslom (manuálne) alebo kľúčom zariadenia (automatické) a obsahujú profil, prihlásenie, zdieľania aj nové polia kariet.
- Opravené rozloženie hlavičky, širšie like srdce a nový full-screen skener s výberom typu, zoomom a galériou.
- Aktualizované závislosti (camera, ML Kit, intl, mobile_scanner a ďalšie).
- Pred použitím je potrebné spustiť SQL migráciu `supabase/2026-10-31_account_privacy.sql`.

## [0.3.15] - 2026-10-29

- Ikonky nastavení a obnovy cien sú hore; názov balíka, ... a cena sú pod nimi.
- Like srdce je širšie.
- Prevedenie sa vyberá kliknutím na políčko Prevedenie; samostatné ďalšie pole zmizlo.
- Na výber sú len prevedenia, ktoré karta naozaj má (Normal, Reverse Holo, Holo, Cosmos, set-logo a podobne).
- Pri zmene prevedenia sa načíta cena a obrázok konkrétneho variantu.
- Cena sa už neberie ako maximum zo všetkých variantov; odstránil sa falošný set-logo variant z bežnej ceny.
- Ceny z Cardmarketu sa zobrazujú v €.

## [0.3.14] - 2026-10-29

- Názov balíka a cena sú v jednom riadku, tlačidlo ... je vedľa názvu.
- Ceruzka a + pribudli z hlavičky preč; premenovanie je v menu balíka cez ceruzku.
- V detaile karty sa dá ručne zvoliť prevedenie (Normal, Holo, Reverse, Gold a ďalšie).
- Ceny sa prioritne ťahajú z Cardmarketu; PriceCharting je len núdzová alternatíva.
- História cien už neobsahuje PriceCharting skoky a staré chybné body sa čistia.
- Android tlačidlo Späť zatvorí otvorené okno namiesto ukončenia aplikácie.

## [0.3.13] - 2026-10-29

- Názov balíka a cena sú v jednom riadku, tlačidlo ... je vedľa názvu.
- Ceruzka a + pribudli z hlavičky preč; premenovanie je v menu balíka cez ceruzku.
- V detaile karty sa dá ručne zvoliť prevedenie (Normal, Holo, Reverse, Gold a ďalšie).
- Ceny sa prioritne ťahajú z Cardmarketu; PriceCharting je len núdzová alternatíva.
- História cien už neobsahuje skoky z PriceChartingu a staré PriceCharting body sa čistia.
- Android tlačidlo Späť zatvorí otvorené okno namiesto ukončenia aplikácie.

## [0.3.12] - 2026-10-29

- Po pridaní naskenovanej karty sa appka vráti rovno do skenera na ďalšiu kartu.
- Po pridaní karty sa vyhľadávacie pole vyčistí, aby tam starý text nezostával.
- Opravené zobrazovanie detailu karty: názov poľa a hodnota už nie sú zlepené (napr. Rarita / Rare).
- V Nastaveniach pribudla História verzií s prehľadom zmien jednotlivých vydaní.

## [0.3.11] - 2026-10-29

- Detaily mojich kariet sú v rovnakých obdĺžnikových kartách ako zdieľané karty.
- Zdieľaný detail karty obsahuje rovnaké údaje ako môj detail: jazyk, edíciu, raritu, prevedenie, číslo, autora, cenu a zdroj ceny.
- Like srdce je v pravom dolnom rohu, väčšie a bez čierneho rámčeka.
- Zdieľané karty majú holo efekt – nakláňanie podľa telefónu, odlesky a reakciu na potiahnutie prstom.

## [0.3.10] - 2026-10-29

- Opravené prevedenie kariet: skener už nedáva každú kartu ako Reverse Holo.
- Základné prevedenie (Normal / Holo) má prednosť pred reverse variantom.
- Reverse sa zobrazí len vtedy, keď je jediné dostupné prevedenie karty.
- Zlaté, rainbow a iné špeciálne prevedenia zostávajú prioritné.

## [0.3.9] - 2026-10-29

- Zdieľané balíky pribudli do výberu balíkov pod moje balíky a tlačidlo Vytvoriť nový balík.
- Zdieľané balíky majú badge od koho sú a otvárajú sa v rovnakom detaile.
- Kliknutie na kartu v zdieľanom balíku otvorí detail karty.
- Like badge je v spodnom rohu karty; owner vidí lajky na svojich kartách.
- Záloha už nezobrazuje zbytočný toast, stav zostáva pod tlačidlom.
- Skenovanie je celoobrazovkové, s väčším rámom, rohmi, bleskom a vyšším rozlíšením.
- OCR sa robí na oreze karty, čo zlepšuje presnosť hľadania.

## [0.3.8] - 2026-10-29

- Pri zdieľaní balíka sa dá vybrať konkrétnych kamošov bez skenovania.
- Kamoši môžu dať like karty v zdieľanom balíku a like môžu aj odobrať.
- Počet like je viditeľný pri karte; owner vidí počty, kamoši môžu lajkovať.
- Likes sa čistia, keď karta zmizne zo zdieľaného balíka.
- Landing page po inštalácii pripomenie návrat a otvorenie kódu bez skenovania.

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
