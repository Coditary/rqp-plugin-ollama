return {
  name = "ollama search models fallback",
  request = {
    action = "search",
    system = "ollama",
    prompt = "medgemma",
  },
  fakeExec = {
    {
      match = "curl -fsSL 'https://ollama.com/search?q=medgemma'",
      exitCode = 0,
      stdout = [[<li x-test-model class="flex items-baseline border-b border-neutral-200 py-6"><a href="/library/medgemma" class="group w-full"><div class="flex flex-col mb-1" title="medgemma"><h2 class="truncate text-xl font-medium underline-offset-2 group-hover:underline md:text-2xl"><span x-test-search-response-title>medgemma</span></h2><p class="max-w-lg break-words text-neutral-800 text-md">Medical Gemma family.</p></div><div class="flex flex-col"><div class="flex flex-wrap space-x-2"><span x-test-capability class="inline-flex my-1 items-center rounded-md bg-indigo-50 px-2 py-[2px] text-xs font-medium text-indigo-600 sm:text-[13px]">vision</span><span x-test-size class="inline-flex my-1 items-center rounded-md bg-[#ddf4ff] px-2 py-[2px] text-xs font-medium text-blue-600 sm:text-[13px]">4b</span><span x-test-size class="inline-flex my-1 items-center rounded-md bg-[#ddf4ff] px-2 py-[2px] text-xs font-medium text-blue-600 sm:text-[13px]">27b</span></div><p class="my-1 flex space-x-5 text-[13px] font-medium text-neutral-500"><span class="flex items-center"><span x-test-pull-count>35.7K</span></span><span class="flex items-center"><span x-test-tag-count>9</span></span><span class="flex items-center"><span x-test-updated>1 month ago</span></span></p></div></a></li>]],
      stderr = "",
      success = true,
    },
    {
      match = "curl -fsSL 'https://ollama.com/library/medgemma'",
      exitCode = 22,
      stdout = "",
      stderr = "404",
      success = false,
    },
  },
  expect = {
    success = true,
    events = { "searched" },
    resultCount = 1,
    resultName = "medgemma@latest",
  }
}
