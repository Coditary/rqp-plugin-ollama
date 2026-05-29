# ReqPack Lua Plugin API Quick Reference

Short reference for this wrapper.
Source of truth is ReqPack wiki page `Extending-Writing-Lua-Plugins` from this project.

## Files You Usually Edit

- `metadata.json`: plugin id and bundle metadata
- `reqpack.lua`: bundle manifest with `apiVersion` and `depends`
- `run.lua`: main wrapper implementation
- `scripts/install.lua` and `scripts/remove.lua`: required bundle hook stubs
- `.reqpack-test/core/*.lua`: hermetic plugin tests
- `README.md`: quickstart for people opening bundle first

## Ollama Wrapper Behavior

- `app:ollama` uses official Ollama installer script for install/update
- model packages use `ollama pull`, `ollama rm`, `ollama ls`, and `ollama show`
- model package input accepts both `model:tag` and `model@tag`; plugin calls Ollama with `model:tag` but shows/returns names as `model@tag`
- model install/update adopt local Ollama manifest and blob metadata into `~/.local/share/aicache`
- adopted cache layout includes:
  - `blobs/sha256/<prefix>/<digest>`
  - `artifacts/<artifact-id>/{manifest.json,files.json,source.json}`
  - `views/by-kind/...`, `views/by-format/...`, `views/by-source/...`
- `list()` includes installed app when `ollama` binary is on PATH and prefers AICache for model entries first
- `info()` prefers AICache metadata, then falls back to local Ollama manifest plus `ollama show`
- `remove()` deletes model aliases from Ollama via `ollama rm`, cleans AICache metadata/views, and prunes unreferenced adopted blobs
- `installLocal()` is intentionally unsupported in v1
- `search()` only returns static runtime package result for `app:ollama` in v1
- `outdated()` returns empty list in v1

## Required Methods

ReqPack expects these methods on `plugin`:

```lua
function plugin.getName() end
function plugin.getVersion() end
function plugin.getRequirements() end
function plugin.getCategories() end
function plugin.getMissingPackages(packages) end
function plugin.install(context, packages) end
function plugin.installLocal(context, path) end
function plugin.remove(context, packages) end
function plugin.update(context, packages) end
function plugin.list(context) end
function plugin.search(context, prompt) end
function plugin.info(context, packageName) end
```

## Testing

```bash
rqp test-plugin --plugin . --preset core
```

Current core preset covers app lifecycle, model lifecycle, CLI fallback paths, and fixture-backed AICache query behavior.
