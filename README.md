# SessionBar

Touch Bar-widget die je Claude Code-sessies laat zien (desktop-app Code-tab én CLI).

- ● groen: idle / klaar en gezien
- ● groen ademend: Claude is bezig
- ● oranje knipperend: wacht op jou (toestemming, vraag, plan)
- ● oranje: beurt klaar, nog niet bekeken

Tik op een sessie om de Claude-app (of de terminal van een CLI-sessie) naar voren te halen.
Het icoon in de Control Strip toont dezelfde bolletjes en klapt de balk in en uit.

## Installeren

Vereist een MacBook Pro met Touch Bar, macOS 13+ en de Xcode Command Line Tools
(`xcode-select --install`).

```sh
git clone https://github.com/RespawnDespair/SessionBar.git
cd SessionBar
./scripts/install-app.sh
```

Bouwt de app, zet hem in `/Applications`, voegt hooks toe aan `~/.claude/settings.json`
(backup: `settings.json.bak-sessionbar`), zet "Starten bij inloggen" aan en start hem.
Sessies die al open waren verschijnen zodra ze iets doen.

Instellingen en hooks verwijderen gaan via het menubalk-icoon, of:

```sh
/Applications/SessionBar.app/Contents/MacOS/SessionBar --uninstall-hooks
/Applications/SessionBar.app/Contents/MacOS/SessionBar --launch-at-login off
```

## Hoe het werkt

De app-binary is ook de hook: Claude Code roept `SessionBar --sessionbar-hook` aan, die per
sessie `~/.claude/sessionbar/state.d/<id>.json` schrijft. De app leest die map elke 0,5 s en
ruimt sessies op waarvan het `claude`-proces weg is. Status-logica gebaseerd op
[claude-status-bar](https://github.com/m1ckc3s/claude-status-bar) (MIT, © Mick Cesanek).

Beperking: de desktop-app heeft geen link naar een specifieke Code-sessie, dus een tik brengt
de Claude-app naar voren maar opent niet die ene sessie.
