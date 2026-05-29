return {
  name = "ollama list aicache",
  request = {
    action = "list",
    system = "ollama",
  },
  fixtureRoot = "../fixtures-aicache-list",
  fixtureFiles = {
    {
      path = "data/aicache/views/by-source/ollama/model/qwen3_8b/current.json",
      content = [[{"artifact_id":"ollama/model-llm/qwen3:8b@1111111111111111111111111111111111111111111111111111111111111111","artifact_path":"${fixtureRoot}/data/aicache/artifacts/ollama/model-llm/qwen3:8b@1111111111111111111111111111111111111111111111111111111111111111"}]],
    },
    {
      path = "data/aicache/artifacts/ollama/model-llm/qwen3:8b@1111111111111111111111111111111111111111111111111111111111111111/manifest.json",
      content = [[{"artifact_id":"ollama/model-llm/qwen3:8b@1111111111111111111111111111111111111111111111111111111111111111","kind":"model-llm","tasks":["completion"],"source":{"registry":"ollama","repo_type":"model","package_id":"qwen3:8b","revision":"1111111111111111111111111111111111111111111111111111111111111111","refs":["8b"]},"created_at":"2026-05-28T12:00:00Z"}]],
    },
    {
      path = "data/aicache/artifacts/ollama/model-llm/qwen3:8b@1111111111111111111111111111111111111111111111111111111111111111/files.json",
      content = [[{"files":[{"logical_path":"model.gguf","role":"weights","format":"gguf","blob_id":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","size":4096}]}]],
    },
    {
      path = "data/aicache/artifacts/ollama/model-llm/qwen3:8b@1111111111111111111111111111111111111111111111111111111111111111/source.json",
      content = [[{"fetched_at":"2026-05-28T12:00:00Z","upstream_metadata":{"homepage":"https://ollama.com/library/qwen3:8b","source_url":"https://ollama.com/library/qwen3:8b","format":"gguf","family":"qwen3","parameter_size":"8B","quantization":"Q4_K_M","capabilities":["completion"]}}]],
    },
  },
  environment = {
    XDG_DATA_HOME = "${fixtureRoot}/data",
    HOME = "${fixtureRoot}/home",
  },
  fakeExec = {
    {
      match = "command -v 'ollama' >/dev/null 2>&1",
      exitCode = 1,
      stdout = "",
      stderr = "",
      success = false,
    },
    {
      match = "find '",
      exitCode = 0,
      stdout = ".reqpack-test/fixtures-aicache-list/data/aicache/views/by-source/ollama/model/qwen3_8b/current.json\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "listed" },
    resultCount = 1,
    resultName = "qwen3:8b",
    resultVersion = "1111111111111111111111111111111111111111111111111111111111111111",
  }
}
