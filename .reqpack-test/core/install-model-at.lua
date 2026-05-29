return {
  name = "ollama install model @tag",
  request = {
    action = "install",
    system = "ollama",
    packages = {
      { name = "qwen3@4b" }
    },
  },
  fixtureRoot = "../fixtures-install-model-at",
  fixtureDirs = {
    "data/aicache/artifacts/ollama/model-llm/qwen3:4b@1111111111111111111111111111111111111111111111111111111111111111",
    "data/aicache/views/by-source/ollama/model/qwen3_4b",
  },
  fixtureFiles = {
    {
      path = "models/manifests/registry.ollama.ai/library/qwen3/4b",
      content = [[{"schemaVersion":2,"mediaType":"application/vnd.docker.distribution.manifest.v2+json","config":{"mediaType":"application/vnd.ollama.image.config; type=gguf","digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size":220},"layers":[{"mediaType":"application/vnd.ollama.image.model","digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","size":4096},{"mediaType":"application/vnd.ollama.image.template","digest":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","size":64},{"mediaType":"application/vnd.ollama.image.license","digest":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","size":32}]}]],
    },
    {
      path = "models/blobs/sha256-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      content = [[{"model_format":"gguf","model_family":"qwen3","model_families":["qwen3"],"model_type":"4B","file_type":"Q4_K_M","architecture":"amd64","os":"linux","rootfs":{"type":"layers","diff_ids":[]},"capabilities":["completion"],"context_length":131072}]],
    },
    {
      path = "models/blobs/sha256-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      content = "weights",
    },
    {
      path = "models/blobs/sha256-cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      content = "{{ .Prompt }}",
    },
    {
      path = "models/blobs/sha256-dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      content = "Apache-2.0",
    },
  },
  environment = {
    OLLAMA_MODELS = "${fixtureRoot}/models",
    XDG_DATA_HOME = "${fixtureRoot}/data",
    HOME = "${fixtureRoot}/home",
  },
  fakeExec = {
    {
      match = "command -v 'ollama' >/dev/null 2>&1",
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
    {
      match = "ollama pull qwen3:4b",
      exitCode = 0,
      stdout = "pulling manifest\n",
      stderr = "",
      success = true,
    },
    {
      match = "mkdir -p '",
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
    {
      match = "sha256sum '",
      exitCode = 0,
      stdout = "1111111111111111111111111111111111111111111111111111111111111111  ${fixtureRoot}/models/manifests/registry.ollama.ai/library/qwen3/4b\n",
      stderr = "",
      success = true,
    },
    {
      match = "shasum -a 256 '",
      exitCode = 0,
      stdout = "1111111111111111111111111111111111111111111111111111111111111111  ${fixtureRoot}/models/manifests/registry.ollama.ai/library/qwen3/4b\n",
      stderr = "",
      success = true,
    },
    {
      match = "date -u +%Y-%m-%dT%H:%M:%SZ > '",
      exitCode = 0,
      stdout = "2026-05-28T12:00:00Z\n",
      stderr = "",
      success = true,
    },
    {
      match = "ln '",
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "installed", "success" },
    eventPayloads = {
      installed = "{1=<lua-value>}",
      success = "ok",
    },
  }
}
