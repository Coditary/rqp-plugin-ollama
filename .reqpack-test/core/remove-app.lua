return {
  name = "ollama remove app",
  request = {
    action = "remove",
    system = "ollama",
    packages = {
      { name = "app:ollama" }
    },
  },
  environment = {
    HOME = "${fixtureRoot}/home",
  },
  fakeExec = {
    {
      match = "command -v systemctl >/dev/null 2>&1 && systemctl stop ollama >/dev/null 2>&1 || true",
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
    {
      match = "command -v systemctl >/dev/null 2>&1 && systemctl disable ollama >/dev/null 2>&1 || true",
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
    {
      match = "command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload >/dev/null 2>&1 || true",
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
    {
      match = "rm -f '/etc/systemd/system/ollama.service'",
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
    {
      match = "rm -f '/usr/local/bin/ollama' '/usr/bin/ollama' '/bin/ollama'",
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
    {
      match = "rm -rf '/usr/local/lib/ollama' '/usr/lib/ollama' '/lib/ollama'",
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    commands = {
      "command -v systemctl >/dev/null 2>&1 && systemctl stop ollama >/dev/null 2>&1 || true",
      "command -v systemctl >/dev/null 2>&1 && systemctl disable ollama >/dev/null 2>&1 || true",
      "command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload >/dev/null 2>&1 || true",
      "rm -f '/etc/systemd/system/ollama.service'",
      "rm -f '/usr/local/bin/ollama' '/usr/bin/ollama' '/bin/ollama'",
      "rm -rf '/usr/local/lib/ollama' '/usr/lib/ollama' '/lib/ollama'",
    },
    events = { "deleted", "success" },
    eventPayloads = {
      deleted = "{1=<lua-value>}",
      success = "ok",
    },
  }
}
