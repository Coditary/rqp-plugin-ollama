return {
  name = "ollama search models",
  request = {
    action = "search",
    system = "ollama",
    prompt = "gemma",
  },
  fakeExec = {
    {
      match = "curl -fsSL 'https://ollama.com/search?q=gemma'",
      exitCode = 0,
      stdout = [[<li x-test-model class="flex items-baseline border-b border-neutral-200 py-6"><a href="/library/gemma3" class="group w-full"><div class="flex flex-col mb-1" title="gemma3"><h2 class="truncate text-xl font-medium underline-offset-2 group-hover:underline md:text-2xl"><span x-test-search-response-title>gemma3</span></h2><p class="max-w-lg break-words text-neutral-800 text-md">The current, most capable model that runs on a single GPU.</p></div><div class="flex flex-col"><div class="flex flex-wrap space-x-2"><span x-test-capability class="inline-flex my-1 items-center rounded-md bg-indigo-50 px-2 py-[2px] text-xs font-medium text-indigo-600 sm:text-[13px]">vision</span><span class="inline-flex my-1 items-center rounded-md bg-cyan-50 px-2 py-[2px] text-xs font-medium text-cyan-500 sm:text-[13px]">cloud</span><span x-test-size class="inline-flex my-1 items-center rounded-md bg-[#ddf4ff] px-2 py-[2px] text-xs font-medium text-blue-600 sm:text-[13px]">1b</span><span x-test-size class="inline-flex my-1 items-center rounded-md bg-[#ddf4ff] px-2 py-[2px] text-xs font-medium text-blue-600 sm:text-[13px]">4b</span></div><p class="my-1 flex space-x-5 text-[13px] font-medium text-neutral-500"><span class="flex items-center"><span x-test-pull-count>37.2M</span></span><span class="flex items-center"><span x-test-tag-count>29</span></span><span class="flex items-center"><span x-test-updated>5 months ago</span></span></p></div></a></li>]],
      stderr = "",
      success = true,
    },
    {
      match = "curl -fsSL 'https://ollama.com/library/gemma3'",
      exitCode = 0,
      stdout = [[<a href="/library/gemma3:1b" class="block group-hover:underline text-sm font-medium text-neutral-800">gemma3:1b</a><input class="command hidden" value="gemma3:1b" /><p x-test-model-tag-size class="col-span-2 text-neutral-500">815MB</p><p class="col-span-2 text-neutral-500">32K</p><p class="col-span-2 text-neutral-500">Text</p><a href="/library/gemma3:4b" class="block group-hover:underline text-sm font-medium text-neutral-800">gemma3:4b</a><span class="ml-2 inline-flex items-center rounded-full px-2 py-px text-xs font-medium border border-blue-500 text-blue-600">latest</span><input class="command hidden" value="gemma3:4b" /><p x-test-model-tag-size class="col-span-2 text-neutral-500">3.3GB</p><p class="col-span-2 text-neutral-500">128K</p><p class="col-span-2 text-neutral-500">Text, Image</p>]],
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "searched" },
    resultCount = 2,
    resultName = "gemma3@1b",
    commands = {
      "curl -fsSL 'https://ollama.com/search?q=gemma'",
      "curl -fsSL 'https://ollama.com/library/gemma3'",
    },
  }
}
