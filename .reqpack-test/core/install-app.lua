return {
  name = "ollama install app",
  request = {
    action = "install",
    system = "ollama",
    packages = {
      { name = "app:ollama" }
    },
  },
  fakeExec = {
    {
      match = "curl -fsSL https://ollama.com/install.sh | sh",
      exitCode = 0,
      stdout = "install ok\n",
      stderr = "",
      success = true,
    },
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
  },
  expect = {
    success = true,
    commands = {
      "curl -fsSL https://ollama.com/install.sh | sh",
      "command -v 'ollama' >/dev/null 2>&1",
      "ollama -v",
    },
    events = { "installed", "success" },
    eventPayloads = {
      installed = "{1=<lua-value>}",
      success = "ok",
    },
  }
}
