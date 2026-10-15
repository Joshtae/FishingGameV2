# FishingGameV2

Luau source for the game, extracted from the Studio place and organized for
[Rojo](https://github.com/rojo-rbx/rojo) 7.

## Layout

| Folder | Syncs to | Contents |
|---|---|---|
| `src/server/FishingSystem` | `ServerScriptService.FishingSystem` | Server modules and bootstraps (`.server.luau` = Script, `.luau` = ModuleScript), including `Dependencies/ProfileStore` and `DEV_TEST_ONLY` |
| `src/shared/FishingSystemV2` | `ReplicatedStorage.FishingSystemV2` | Shared config and data modules |
| `src/client/FishingSystemV2` | `StarterPlayer.StarterPlayerScripts.FishingSystemV2` | Client LocalScripts (`.client.luau`) |

Reference only (not synced by `default.project.json`):

- `src/client/Legacy` — the old pre-V2 LocalScripts. They are disabled in the
  place (`*.meta.json` records `Disabled = true`) and are dead code.
- `src/server/WorkspaceRigs`, `src/client/WorkspaceRigs` — scripts that live
  inside character rig models in Workspace (`BreathingAnimationController`, and
  one copy of Roblox's stock `Animate` script, which 148 rigs share unchanged).
  They belong to the models, so Rojo does not place them.

## Notes

- The project file only manages the three script folders above and sets
  `$ignoreUnknownInstances`, so syncing never deletes the place's other
  objects (Remotes, templates, CharacterModels, UI, Workspace).
- UI, models, plots and other non-script instances still live only in the
  Studio place. The raw place file was removed from the repo; it remains in
  git history (commit `10ab23d`).

## Syncing

```bash
rojo serve
```

Then connect from the Rojo plugin in Studio with the game place open.
