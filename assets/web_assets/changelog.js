// Generated from CHANGELOG.md by tool/generate_changelog_js.py.
window.RARITIO_CHANGELOG = [
  {
    "version": "0.3.12",
    "date": "2026-10-29",
    "changes": [
      "Po pridaní naskenovanej karty sa appka vráti rovno do skenera na ďalšiu kartu.",
      "Po pridaní karty sa vyhľadávacie pole vyčistí, aby tam starý text nezostával.",
      "Opravené zobrazovanie detailu karty: názov poľa a hodnota už nie sú zlepené (napr. Rarita / Rare).",
      "V Nastaveniach pribudla História verzií s prehľadom zmien jednotlivých vydaní."
    ]
  },
  {
    "version": "0.3.11",
    "date": "2026-10-29",
    "changes": [
      "Detaily mojich kariet sú v rovnakých obdĺžnikových kartách ako zdieľané karty.",
      "Zdieľaný detail karty obsahuje rovnaké údaje ako môj detail: jazyk, edíciu, raritu, prevedenie, číslo, autora, cenu a zdroj ceny.",
      "Like srdce je v pravom dolnom rohu, väčšie a bez čierneho rámčeka.",
      "Zdieľané karty majú holo efekt – nakláňanie podľa telefónu, odlesky a reakciu na potiahnutie prstom."
    ]
  },
  {
    "version": "0.3.10",
    "date": "2026-10-29",
    "changes": [
      "Opravené prevedenie kariet: skener už nedáva každú kartu ako Reverse Holo.",
      "Základné prevedenie (Normal / Holo) má prednosť pred reverse variantom.",
      "Reverse sa zobrazí len vtedy, keď je jediné dostupné prevedenie karty.",
      "Zlaté, rainbow a iné špeciálne prevedenia zostávajú prioritné."
    ]
  },
  {
    "version": "0.3.9",
    "date": "2026-10-29",
    "changes": [
      "Zdieľané balíky pribudli do výberu balíkov pod moje balíky a tlačidlo Vytvoriť nový balík.",
      "Zdieľané balíky majú badge od koho sú a otvárajú sa v rovnakom detaile.",
      "Kliknutie na kartu v zdieľanom balíku otvorí detail karty.",
      "Like badge je v spodnom rohu karty; owner vidí lajky na svojich kartách.",
      "Záloha už nezobrazuje zbytočný toast, stav zostáva pod tlačidlom.",
      "Skenovanie je celoobrazovkové, s väčším rámom, rohmi, bleskom a vyšším rozlíšením.",
      "OCR sa robí na oreze karty, čo zlepšuje presnosť hľadania."
    ]
  },
  {
    "version": "0.3.8",
    "date": "2026-10-29",
    "changes": [
      "Pri zdieľaní balíka sa dá vybrať konkrétnych kamošov bez skenovania.",
      "Kamoši môžu dať like karty v zdieľanom balíku a like môžu aj odobrať.",
      "Počet like je viditeľný pri karte; owner vidí počty, kamoši môžu lajkovať.",
      "Likes sa čistia, keď karta zmizne zo zdieľaného balíka.",
      "Landing page po inštalácii pripomenie návrat a otvorenie kódu bez skenovania."
    ]
  },
  {
    "version": "0.3.7",
    "date": "2026-10-29",
    "changes": [
      "QR kódy pre zdieľanie a pozvánky fungujú cez HTTPS stránku.",
      "Pri mojom profile pribudla ikonka Môj QR kód.",
      "Ak kamoš Raritio nemá, stránka mu ponúkne aktuálne APK na stiahnutie.",
      "Pridaná jednoduchá Raritio landing page na GitHub Pages.",
      "Opravené načítanie QR z webového odkazu v appke."
    ]
  },
  {
    "version": "0.3.6",
    "date": "2026-10-29",
    "changes": [
      "Moderné výberové okno radenia kariet namiesto natívneho selectu.",
      "Zálohy sa ukladajú do Downloads/Raritio.",
      "Automatické aj manuálne zálohy sa v Downloads držia maximálne 5.",
      "Opravené a doplnené Supabase RLS migrácie."
    ]
  },
  {
    "version": "0.3.5",
    "date": "2026-10-29",
    "changes": [
      "Opravené RLS pravidlá pre zdieľané balíky (infinite recursion).",
      "Opravené pridávanie a odoberanie kamošov.",
      "Manuálna kontrola aktualizácií v Nastaveniach.",
      "Zdieľaný zoznam sa automaticky obnovuje každých 30 sekúnd.",
      "Doplnené bezpečnejšie Supabase migrácie."
    ]
  },
  {
    "version": "0.3.4",
    "date": "2026-10-29",
    "changes": [
      "Prvý Raritio beta build.",
      "Rebrand z Holodex TCG na Raritio.",
      "Nový package sk.zdenoiva.raritio.",
      "Nová ikona aplikácie.",
      "Nové číslovanie verzií: 0.3.4 bez zátvoriek.",
      "Vlastné balíky, radenie a presúvanie kariet.",
      "Vlastné fotky kariet s badge Custom.",
      "Zdieľané balíky cez Supabase (read-only pre kamošov).",
      "QR kódy, Android share menu a friend kódy.",
      "Automatická kontrola aktualizácií z GitHub Releases.",
      "Supabase keepalive workflow pre free tier."
    ]
  }
];
