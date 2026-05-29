return {
  name = "ollama list cli fallback",
  request = {
    action = "list",
    system = "ollama",
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
      match = "ollama -v",
      exitCode = 0,
      stdout = "ollama version 0.7.1\n",
      stderr = "",
      success = true,
    },
    {
      match = "ollama ls",
      exitCode = 0,
      stdout = "NAME             ID              SIZE    MODIFIED\nqwen3:8b         abcdef123456    5.2 GB  2 hours ago\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "listed" },
    resultCount = 2,
    resultName = "app:ollama",
    resultVersion = "0.7.1",
  }
}
