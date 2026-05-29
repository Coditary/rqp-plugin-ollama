return {
  name = "ollama info cli fallback @tag",
  request = {
    action = "info",
    system = "ollama",
    prompt = "qwen3@4b",
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
      match = "ollama show qwen3:4b",
      exitCode = 0,
      stdout = [[Model
  architecture        qwen3
  parameters          4B
  quantization        Q4_K_M
  context length      131072

Capabilities
  completion
]],
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "informed" },
    resultCount = 1,
    resultName = "qwen3@4b",
    resultVersion = "4b",
  }
}
