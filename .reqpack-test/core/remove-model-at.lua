return {
  name = "ollama remove model @tag",
  request = {
    action = "remove",
    system = "ollama",
    packages = {
      { name = "qwen3@4b" }
    },
  },
  fixtureRoot = "../fixtures-remove-model-at",
  fixtureFiles = {
    {
      path = "data/aicache/views/by-source/ollama/model/qwen3_4b/current.json",
      content = [[{"artifact_id":"ollama/model-llm/qwen3:4b@1111111111111111111111111111111111111111111111111111111111111111","artifact_path":"${fixtureRoot}/data/aicache/artifacts/ollama/model-llm/qwen3:4b@1111111111111111111111111111111111111111111111111111111111111111"}]],
    },
    {
      path = "data/aicache/artifacts/ollama/model-llm/qwen3:4b@1111111111111111111111111111111111111111111111111111111111111111/manifest.json",
      content = [[{"artifact_id":"ollama/model-llm/qwen3:4b@1111111111111111111111111111111111111111111111111111111111111111","kind":"model-llm","tasks":["completion"],"source":{"registry":"ollama","repo_type":"model","package_id":"qwen3:4b","revision":"1111111111111111111111111111111111111111111111111111111111111111","refs":["4b"]},"created_at":"2026-05-28T12:00:00Z"}]],
    },
    {
      path = "data/aicache/artifacts/ollama/model-llm/qwen3:4b@1111111111111111111111111111111111111111111111111111111111111111/files.json",
      content = [[{"files":[{"logical_path":"model.gguf","role":"weights","format":"gguf","blob_id":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","size":4096}]}]],
    },
    {
      path = "data/aicache/artifacts/ollama/model-llm/qwen3:4b@1111111111111111111111111111111111111111111111111111111111111111/source.json",
      content = [[{"fetched_at":"2026-05-28T12:00:00Z","upstream_metadata":{"homepage":"https://ollama.com/library/qwen3:4b"}}]],
    },
    {
      path = "data/aicache/views/by-kind/model-llm/ollama/model-llm/qwen3:4b@1111111111111111111111111111111111111111111111111111111111111111/model.gguf",
      content = "weights",
    },
    {
      path = "data/aicache/views/by-format/gguf/ollama/model-llm/qwen3:4b@1111111111111111111111111111111111111111111111111111111111111111/model.gguf",
      content = "weights",
    },
    {
      path = "data/aicache/views/by-source/ollama/model/qwen3_4b/1111111111111111111111111111111111111111111111111111111111111111/model.gguf",
      content = "weights",
    },
  },
  environment = {
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
      match = "ollama rm qwen3:4b",
      exitCode = 0,
      stdout = "deleted\n",
      stderr = "",
      success = true,
    },
    {
      match = "stat -c '%h' '",
      exitCode = 0,
      stdout = "1\n",
      stderr = "",
      success = true,
    },
    {
      match = "stat -f '%l' '",
      exitCode = 0,
      stdout = "1\n",
      stderr = "",
      success = true,
    },
    {
      match = "rm -rf '",
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
    {
      match = "rm -f '",
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "deleted", "success" },
    eventPayloads = {
      deleted = "{1=<lua-value>}",
      success = "ok",
    },
  }
}
