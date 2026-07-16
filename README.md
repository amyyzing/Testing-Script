# Testing Script

Minimal modular Demonology assistant currently focused on Aswang tracking.

## Loadstring

```luau
loadstring(game:HttpGet("https://raw.githubusercontent.com/amyyzing/Testing-Script/refs/heads/main/logic.luau"))()
```

The root bootstrap loads `loader.luau`, the flat GUI modules, the internal traffic/verdict modules, and the active Aswang trackers. The tracker starts when `Workspace.Ghost`, its `Humanoid`, and `Workspace.SaltPiles` are available.

The current GUI layer is intentionally limited to presentation plus open, close, drag, and resize behavior. Feature controls will be implemented separately under `/logic`.

The remaining ghost, filter, and logic files are intentional placeholders for the one-at-a-time rewrite.
