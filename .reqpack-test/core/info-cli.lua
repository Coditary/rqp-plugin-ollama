return {
  name = "ollama info cli fallback",
  request = {
    action = "info",
    system = "ollama",
    prompt = "qwen3:8b",
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
      match = "ollama show qwen3:8b",
      exitCode = 0,
      stdout = "  Model\n    architecture        qwen3\n    parameters          8B\n    context length      131072\n    quantization        Q4_K_M\n\n  Capabilities\n    completion\n    tools\n\n  License\n    Apache-2.0\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "informed" },
    resultCount = 1,
    resultName = "qwen3:8b",
    resultVersion = "8b",
  }
}
