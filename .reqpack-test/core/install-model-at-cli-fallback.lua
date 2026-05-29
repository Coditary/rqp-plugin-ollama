return {
  name = "ollama install model @tag cli fallback",
  request = {
    action = "install",
    system = "ollama",
    packages = {
      { name = "gemma3@4b" }
    },
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
      match = "ollama pull gemma3:4b",
      exitCode = 0,
      stdout = "pulling manifest\n",
      stderr = "",
      success = true,
    },
    {
      match = "ollama show gemma3:4b",
      exitCode = 0,
      stdout = "  Model\n    architecture        gemma3\n    parameters          4B\n    context length      131072\n    quantization        Q4_K_M\n\n  Capabilities\n    completion\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "installed", "success" },
    resultCount = 1,
    resultName = "gemma3@4b",
    resultVersion = "4b",
  }
}
