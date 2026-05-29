return {
  name = "ollama install local unsupported",
  request = {
    action = "install",
    system = "ollama",
    localPath = "/tmp/model.gguf",
  },
  fakeExec = {},
  expect = {
    success = false,
    events = { "failed", "unavailable" },
    eventPayloads = {
      failed = "ollama plugin does not support installLocal()",
      unavailable = "{path=/tmp/model.gguf, reason=local-install-unsupported}",
    },
  }
}
