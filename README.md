# rqp-plugin-ollama

ReqPack Lua plugin for Ollama app and local model management.

Plugin manages both:

- `app:ollama` for Ollama runtime install, update, and removal
- model packages such as `qwen3:8b`, `llava:latest`, or `my-namespace/model:tag`

Model installs use visible native CLI flows like `ollama pull ...` and then adopt local Ollama manifests and blobs into Unified AI Cache at `~/.local/share/aicache`.
Queries prefer AICache first, then fall back to local Ollama metadata and CLI output.

## Package Syntax

- `app:ollama` for runtime itself
- `model:tag` for default Ollama library models
- `model@tag` as alias for `model:tag`
- `namespace/model:tag` for namespaced models
- `namespace/model@tag` as alias for `namespace/model:tag`
- `host/namespace/model:tag` for fully qualified remote identities
- `host/namespace/model@tag` as alias for `host/namespace/model:tag`
- tag is optional and defaults to `latest`
- plugin shows model names as `@tag` in output while still using Ollama's `:tag` syntax internally

Examples:

```bash
rqp install ollama app:ollama
rqp install ollama qwen3:8b
rqp install ollama qwen3@4b
rqp install ollama llava
rqp remove ollama qwen3:8b
rqp info ollama app:ollama
```

## Supported ReqPack Paths

- `install`
- `installLocal`
- `remove`
- `update`
- `list`
- `search`
- `info`
- `outdated`
- `resolvePackage`

## Cache Behavior

- `install` and `update` run native `ollama pull ...` commands for model packages
- plugin reads local Ollama manifest and blob metadata from Ollama storage after pull
- adopted cache layout includes:
  - `blobs/sha256/<prefix>/<digest>`
  - `artifacts/<artifact-id>/{manifest.json,files.json,source.json}`
  - `views/by-kind/...`, `views/by-format/...`, `views/by-source/...`
- `list` and `info` prefer AICache entries first when canonical metadata exists
- `remove` deletes AICache artifact metadata and derived views for removed model aliases, then prunes unreferenced adopted blobs
- original Ollama model cache stays source-side storage and is not canonical truth

## Notes

- app install/update uses official `https://ollama.com/install.sh` surface
- app removal is best-effort and intentionally conservative about user model storage
- `installLocal()` is unsupported in v1
- `search()` returns only static app result for `app:ollama`/`ollama` in v1
- `outdated()` returns an empty list in v1

## Testing

Run hermetic plugin tests from plugin root:

```bash
rqp test-plugin --plugin ./run.lua --preset core
```
