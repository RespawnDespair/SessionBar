# SessionBar

Touch Bar-widget die je Claude Code-sessies laat zien (desktop-app Code-tab én CLI).

- ● groen: idle / klaar en gezien
- ● groen ademend: Claude is bezig
- ● oranje knipperend: wacht op jou (toestemming, vraag, plan)
- ● oranje: beurt klaar, nog niet bekeken

Tik op een sessie om de Claude-app (of de terminal van een CLI-sessie) naar voren te halen.
Het icoon in de Control Strip toont dezelfde bolletjes en klapt de balk in en uit.

## Installeren

```sh
./scripts/install-app.sh
```

Bouwt de app, zet hem in `/Applications`, voegt hooks toe aan `~/.claude/settings.json`
(backup: `settings.json.bak-sessionbar`) en start hem. Hooks verwijderen kan via het
menubalk-icoon of `SessionBar --uninstall-hooks`.

## Hoe het werkt

De app-binary is ook de hook: Claude Code roept `SessionBar --sessionbar-hook` aan, die per
sessie `~/.claude/sessionbar/state.d/<id>.json` schrijft. De app leest die map elke 0,5 s en
ruimt sessies op waarvan het `claude`-proces weg is. Status-logica gebaseerd op
[claude-status-bar](https://github.com/m1ckc3s/claude-status-bar).

Beperking: de desktop-app heeft geen link naar een specifieke Code-sessie, dus een tik brengt
de Claude-app naar voren maar opent niet die ene sessie.
