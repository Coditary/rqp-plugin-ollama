plugin = {}

local PLUGIN_NAME = "Ollama"
local PLUGIN_VERSION = "0.1.0"
local INSTALL_SCRIPT_URL = "https://ollama.com/install.sh"
local APP_PACKAGE_NAME = "app:ollama"
local DEFAULT_HOST = "registry.ollama.ai"
local DEFAULT_NAMESPACE = "library"
local DEFAULT_TAG = "latest"
local JSON_NULL = {}
local cached_json_decoder = nil

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function starts_with(value, prefix)
    local text = tostring(value or "")
    local expected = tostring(prefix or "")
    return text:sub(1, #expected) == expected
end

local function ends_with(value, suffix)
    local text = tostring(value or "")
    local expected = tostring(suffix or "")
    return expected == "" or text:sub(-#expected) == expected
end

local function shell_quote(value)
    return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
end

local function is_safe_token(value)
    return tostring(value or ""):match("^[A-Za-z0-9_./:@%%+=,-]+$") ~= nil
end

local function shell_arg(value)
    local text = tostring(value or "")
    if is_safe_token(text) then
        return text
    end
    return shell_quote(text)
end

local function first_nonempty(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if value ~= nil and value ~= JSON_NULL then
            if type(value) == "string" then
                local text = trim(value)
                if text ~= "" then
                    return text
                end
            else
                return value
            end
        end
    end
    return nil
end

local function shallow_copy(value)
    local copy = {}
    for key, item in pairs(value or {}) do
        copy[key] = item
    end
    return copy
end

local function merge_extra_fields(left, right)
    local merged = shallow_copy(type(left) == "table" and left or {})
    for key, value in pairs(type(right) == "table" and right or {}) do
        merged[key] = value
    end
    return merged
end

local function read_field(value, key)
    if value == nil then
        return nil
    end

    local ok, result = pcall(function()
        return value[key]
    end)
    if ok then
        return result
    end

    return nil
end

local function read_nested_field(value, ...)
    local current = value
    for _, key in ipairs({ ... }) do
        current = read_field(current, key)
        if current == nil then
            return nil
        end
    end
    return current
end

local function strip_trailing_slashes(value)
    return tostring(value or ""):gsub("/+$", "")
end

local function path_basename(path)
    local text = tostring(path or "")
    return text:match("([^/]+)$") or text
end

local function path_dirname(path)
    local text = tostring(path or "")
    local dir = text:match("^(.*)/[^/]+$")
    if dir ~= nil and dir ~= "" then
        return dir
    end
    if starts_with(text, "/") then
        return "/"
    end
    return "."
end

local function join_path(...)
    local parts = {}
    for index = 1, select("#", ...) do
        local raw = tostring(select(index, ...) or "")
        if raw ~= "" then
            if #parts == 0 then
                parts[#parts + 1] = strip_trailing_slashes(raw)
            else
                parts[#parts + 1] = strip_trailing_slashes(raw:gsub("^/+", ""))
            end
        end
    end
    return table.concat(parts, "/")
end

local function emit_event(context, name, payload)
    if context == nil or context.events == nil then
        return
    end

    local fn = context.events[name]
    if type(fn) == "function" then
        fn(payload)
    end
end

local function begin_step(context, label)
    if context == nil or context.tx == nil then
        return
    end

    local fn = context.tx.begin_step
    if type(fn) == "function" then
        fn(label)
    end
end

local function tx_success(context)
    if context == nil or context.tx == nil then
        return
    end

    local fn = context.tx.success
    if type(fn) == "function" then
        fn()
    end
end

local function tx_failed(context, message)
    if context == nil or context.tx == nil then
        return
    end

    local fn = context.tx.failed
    if type(fn) == "function" then
        fn(message)
    end
end

local function log_message(context, level, message)
    if context == nil or context.log == nil then
        return
    end

    local fn = context.log[level]
    if type(fn) == "function" then
        fn(message)
    end
end

local function normalize_run_result(first, second, third, fourth, fifth)
    if type(first) == "table" and first.success ~= nil then
        return first
    end

    local result = {}

    local function merge_exec_like(value)
        local probes = {
            "success",
            "ok",
            "stdout",
            "stderr",
            "exitCode",
            "exit_code",
            "code",
            "status",
        }

        for _, key in ipairs(probes) do
            local ok, item = pcall(function()
                return value[key]
            end)
            if ok and item ~= nil and result[key] == nil then
                result[key] = item
            end
        end
    end

    local function merge_table(value)
        for key, item in pairs(value or {}) do
            result[key] = item
        end
    end

    local function apply_scalar(value)
        local value_type = type(value)
        if value_type == "table" then
            merge_table(value)
        elseif value_type == "userdata" then
            merge_exec_like(value)
        elseif value_type == "boolean" then
            if result.success == nil then
                result.success = value
            end
        elseif value_type == "number" then
            if result.exitCode == nil then
                result.exitCode = value
            end
        elseif value_type == "string" then
            if result.stdout == nil then
                result.stdout = value
            elseif result.stderr == nil then
                result.stderr = value
            end
        end
    end

    apply_scalar(first)
    apply_scalar(second)
    apply_scalar(third)
    apply_scalar(fourth)
    apply_scalar(fifth)

    if result.exitCode == nil then
        result.exitCode = result.exit_code or result.code or result.status
    end
    if result.success == nil and result.ok ~= nil then
        result.success = result.ok
    end
    if result.success == nil and result.exitCode ~= nil then
        result.success = result.exitCode == 0
    end

    return result
end

local function run_command(context, command)
    local first, second, third, fourth, fifth
    if context ~= nil and context.exec ~= nil and type(context.exec.run) == "function" then
        first, second, third, fourth, fifth = context.exec.run(command)
    else
        first, second, third, fourth, fifth = reqpack.exec.run(command)
    end
    return normalize_run_result(first, second, third, fourth, fifth)
end

local function is_command_success(result)
    if type(result) ~= "table" then
        return false
    end
    if result.success or result.ok then
        return true
    end
    local exit_code = result.exitCode or result.exit_code or result.code or result.status
    return exit_code == 0
end

local function command_exists(context, binary)
    local result = run_command(context, "command -v " .. shell_quote(binary) .. " >/dev/null 2>&1")
    return is_command_success(result)
end

local function split_raw_lines(value)
    local lines = {}
    for line in tostring(value or ""):gmatch("([^\n]*)\n?") do
        if line == "" and #lines > 0 and lines[#lines] == "" then
            break
        end
        lines[#lines + 1] = line:gsub("\r$", "")
    end
    return lines
end

local function split_lines(value)
    local lines = {}
    for _, line in ipairs(split_raw_lines(value)) do
        local text = trim(line)
        if text ~= "" then
            lines[#lines + 1] = text
        end
    end
    return lines
end

local function split_whitespace(line)
    local fields = {}
    for field in tostring(line or ""):gmatch("%S+") do
        fields[#fields + 1] = field
    end
    return fields
end

local function sorted_string_keys(value)
    local keys = {}
    for key in pairs(value or {}) do
        keys[#keys + 1] = tostring(key)
    end
    table.sort(keys)
    return keys
end

local function is_array_table(value)
    local max_index = 0
    local count = 0
    for key in pairs(value or {}) do
        if type(key) ~= "number" or key < 1 or math.floor(key) ~= key then
            return false
        end
        if key > max_index then
            max_index = key
        end
        count = count + 1
    end
    return max_index == count
end

local function normalize_json_tree(value, null_sentinel, seen)
    if null_sentinel ~= nil and value == null_sentinel then
        return JSON_NULL
    end

    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] ~= nil then
        return seen[value]
    end

    local normalized = {}
    seen[value] = normalized
    for key, item in pairs(value) do
        normalized[key] = normalize_json_tree(item, null_sentinel, seen)
    end
    return normalized
end

local function codepoint_to_utf8(codepoint)
    if codepoint <= 0x7F then
        return string.char(codepoint)
    end

    if codepoint <= 0x7FF then
        return string.char(
            0xC0 + math.floor(codepoint / 0x40),
            0x80 + (codepoint % 0x40)
        )
    end

    if codepoint <= 0xFFFF then
        return string.char(
            0xE0 + math.floor(codepoint / 0x1000),
            0x80 + (math.floor(codepoint / 0x40) % 0x40),
            0x80 + (codepoint % 0x40)
        )
    end

    return string.char(
        0xF0 + math.floor(codepoint / 0x40000),
        0x80 + (math.floor(codepoint / 0x1000) % 0x40),
        0x80 + (math.floor(codepoint / 0x40) % 0x40),
        0x80 + (codepoint % 0x40)
    )
end

local function decode_json_internal(raw)
    local text = tostring(raw or "")
    local length = #text
    local index = 1

    local function decode_error(message)
        error(message .. " at byte " .. tostring(index), 0)
    end

    local function peek()
        return text:sub(index, index)
    end

    local function skip_whitespace()
        while index <= length do
            local byte = text:byte(index)
            if byte == 32 or byte == 9 or byte == 10 or byte == 13 then
                index = index + 1
            else
                break
            end
        end
    end

    local parse_value

    local function parse_string()
        index = index + 1
        local parts = {}
        local segment_start = index

        while index <= length do
            local current = text:sub(index, index)

            if current == '"' then
                parts[#parts + 1] = text:sub(segment_start, index - 1)
                index = index + 1
                return table.concat(parts)
            end

            if current == "\\" then
                parts[#parts + 1] = text:sub(segment_start, index - 1)
                index = index + 1
                if index > length then
                    decode_error("unterminated escape sequence")
                end

                local escape = text:sub(index, index)
                if escape == '"' or escape == "\\" or escape == "/" then
                    parts[#parts + 1] = escape
                    index = index + 1
                elseif escape == "b" then
                    parts[#parts + 1] = "\b"
                    index = index + 1
                elseif escape == "f" then
                    parts[#parts + 1] = "\f"
                    index = index + 1
                elseif escape == "n" then
                    parts[#parts + 1] = "\n"
                    index = index + 1
                elseif escape == "r" then
                    parts[#parts + 1] = "\r"
                    index = index + 1
                elseif escape == "t" then
                    parts[#parts + 1] = "\t"
                    index = index + 1
                elseif escape == "u" then
                    local hex = text:sub(index + 1, index + 4)
                    if #hex ~= 4 or hex:match("^[0-9a-fA-F]+$") == nil then
                        decode_error("invalid unicode escape")
                    end
                    parts[#parts + 1] = codepoint_to_utf8(tonumber(hex, 16))
                    index = index + 5
                else
                    decode_error("unsupported escape sequence")
                end

                segment_start = index
            else
                local byte = text:byte(index)
                if byte ~= nil and byte < 32 then
                    decode_error("control character in string")
                end
                index = index + 1
            end
        end

        decode_error("unterminated string")
    end

    local function parse_number()
        local start_index = index
        local current = peek()
        if current == "-" then
            index = index + 1
        end

        if peek() == "0" then
            index = index + 1
        else
            if peek():match("%d") == nil then
                decode_error("invalid number")
            end
            repeat
                index = index + 1
            until index > length or text:sub(index, index):match("%d") == nil
        end

        if peek() == "." then
            index = index + 1
            if peek():match("%d") == nil then
                decode_error("invalid number")
            end
            repeat
                index = index + 1
            until index > length or text:sub(index, index):match("%d") == nil
        end

        local exponent = peek()
        if exponent == "e" or exponent == "E" then
            index = index + 1
            local sign = peek()
            if sign == "+" or sign == "-" then
                index = index + 1
            end
            if peek():match("%d") == nil then
                decode_error("invalid number")
            end
            repeat
                index = index + 1
            until index > length or text:sub(index, index):match("%d") == nil
        end

        local number = tonumber(text:sub(start_index, index - 1))
        if number == nil then
            decode_error("invalid number")
        end
        return number
    end

    local function parse_array()
        index = index + 1
        skip_whitespace()
        local array = {}
        if peek() == "]" then
            index = index + 1
            return array
        end

        while true do
            array[#array + 1] = parse_value()
            skip_whitespace()
            local current = peek()
            if current == "]" then
                index = index + 1
                return array
            end
            if current ~= "," then
                decode_error("expected ',' or ']' in array")
            end
            index = index + 1
            skip_whitespace()
        end
    end

    local function parse_object()
        index = index + 1
        skip_whitespace()
        local object = {}
        if peek() == "}" then
            index = index + 1
            return object
        end

        while true do
            if peek() ~= '"' then
                decode_error("expected string key")
            end
            local key = parse_string()
            skip_whitespace()
            if peek() ~= ":" then
                decode_error("expected ':' after object key")
            end
            index = index + 1
            skip_whitespace()
            object[key] = parse_value()
            skip_whitespace()
            local current = peek()
            if current == "}" then
                index = index + 1
                return object
            end
            if current ~= "," then
                decode_error("expected ',' or '}' in object")
            end
            index = index + 1
            skip_whitespace()
        end
    end

    parse_value = function()
        skip_whitespace()
        local current = peek()
        if current == '"' then
            return parse_string()
        end
        if current == "{" then
            return parse_object()
        end
        if current == "[" then
            return parse_array()
        end
        if current == "-" or (current ~= "" and current:match("%d") ~= nil) then
            return parse_number()
        end
        if text:sub(index, index + 3) == "true" then
            index = index + 4
            return true
        end
        if text:sub(index, index + 4) == "false" then
            index = index + 5
            return false
        end
        if text:sub(index, index + 3) == "null" then
            index = index + 4
            return JSON_NULL
        end
        decode_error("unexpected token")
    end

    local value = parse_value()
    skip_whitespace()
    if index <= length then
        decode_error("trailing content")
    end

    return value
end

local function load_json_decoder()
    if cached_json_decoder ~= nil then
        return cached_json_decoder
    end

    local candidates = {
        function()
            local ok, module = pcall(require, "cjson.safe")
            if ok and module ~= nil and type(module.decode) == "function" then
                return function(raw)
                    local value, err = module.decode(raw)
                    if err ~= nil then
                        error(err, 0)
                    end
                    return normalize_json_tree(value, module.null)
                end
            end
        end,
        function()
            local ok, module = pcall(require, "cjson")
            if ok and module ~= nil and type(module.decode) == "function" then
                return function(raw)
                    return normalize_json_tree(module.decode(raw), module.null)
                end
            end
        end,
        function()
            local ok, module = pcall(require, "dkjson")
            if ok and module ~= nil and type(module.decode) == "function" then
                return function(raw)
                    local value, _, err = module.decode(raw, 1, nil)
                    if err ~= nil then
                        error(err, 0)
                    end
                    return normalize_json_tree(value, module.null)
                end
            end
        end,
        function()
            local ok, module = pcall(require, "lunajson")
            if ok and module ~= nil and type(module.decode) == "function" then
                return function(raw)
                    return normalize_json_tree(module.decode(raw), module.null)
                end
            end
        end,
        function()
            local ok, module = pcall(require, "json")
            if ok and module ~= nil then
                local decode = module.decode or module.Decode
                if type(decode) == "function" then
                    return function(raw)
                        return normalize_json_tree(decode(raw), module.null)
                    end
                end
            end
        end,
    }

    for _, candidate in ipairs(candidates) do
        local ok, decoder = pcall(candidate)
        if ok and type(decoder) == "function" then
            cached_json_decoder = decoder
            return cached_json_decoder
        end
    end

    cached_json_decoder = decode_json_internal
    return cached_json_decoder
end

local function decode_json(raw)
    local decoder = load_json_decoder()
    local ok, value, err = pcall(decoder, raw)
    if not ok then
        return nil, trim(value)
    end
    if value == nil then
        return nil, first_nonempty(err, "json decode returned nil")
    end
    return value, nil
end

local function encode_json_string(value)
    local text = tostring(value or "")
    local replacements = {
        ["\\"] = "\\\\",
        ['"'] = '\\"',
        ["\b"] = "\\b",
        ["\f"] = "\\f",
        ["\n"] = "\\n",
        ["\r"] = "\\r",
        ["\t"] = "\\t",
    }
    return '"' .. text:gsub('[%z\1-\31\\"]', function(char)
        return replacements[char] or string.format("\\u%04x", string.byte(char))
    end) .. '"'
end

local function encode_json(value)
    local value_type = type(value)
    if value == nil or value == JSON_NULL then
        return "null"
    end
    if value_type == "string" then
        return encode_json_string(value)
    end
    if value_type == "number" or value_type == "boolean" then
        return tostring(value)
    end
    if value_type ~= "table" then
        return encode_json_string(tostring(value))
    end

    if is_array_table(value) then
        local items = {}
        for index = 1, #value do
            items[#items + 1] = encode_json(value[index])
        end
        return "[" .. table.concat(items, ",") .. "]"
    end

    local items = {}
    for _, key in ipairs(sorted_string_keys(value)) do
        items[#items + 1] = encode_json_string(key) .. ":" .. encode_json(value[key])
    end
    return "{" .. table.concat(items, ",") .. "}"
end

local function get_reqpack_path(name)
    local paths = type(reqpack) == "table" and read_field(reqpack, "paths") or nil
    if type(paths) ~= "table" then
        return nil
    end
    return first_nonempty(read_field(paths, name))
end

local function read_proc_environ_value(name)
    if os ~= nil and type(os.getenv) == "function" then
        local current = os.getenv(tostring(name or ""))
        if current ~= nil and current ~= "" then
            return trim(current)
        end
    end

    local handle = io.open("/proc/self/environ", "rb")
    if handle == nil then
        return nil
    end

    local payload = handle:read("*a")
    handle:close()
    if payload == nil or payload == "" then
        return nil
    end

    local prefix = tostring(name or "") .. "="
    for entry in tostring(payload):gmatch("[^%z]+") do
        if starts_with(entry, prefix) then
            return trim(entry:sub(#prefix + 1))
        end
    end
    return nil
end

local function path_exists(context, path)
    local text = tostring(path or "")
    if text == "" then
        return false
    end

    local handle = io.open(text, "rb")
    if handle ~= nil then
        handle:close()
        return true
    end

    local dir_handle = io.open(join_path(text, "."), "rb")
    if dir_handle ~= nil then
        dir_handle:close()
        return true
    end
    return false
end

local function path_is_dir(context, path)
    local text = tostring(path or "")
    if text == "" then
        return false
    end

    local dir_handle = io.open(join_path(text, "."), "rb")
    if dir_handle ~= nil then
        dir_handle:close()
        return true
    end
    return false
end

local function read_text_file(path)
    local handle = io.open(path, "rb")
    if handle == nil then
        return nil
    end
    local content = handle:read("*a")
    handle:close()
    return content
end

local function write_text_file(path, content)
    local handle, open_error = io.open(path, "wb")
    if handle == nil then
        return nil, open_error
    end

    local ok, write_error = handle:write(content)
    handle:close()
    if not ok then
        return nil, write_error
    end
    return true, nil
end

local function ensure_directory(context, path)
    local result = run_command(context, "mkdir -p " .. shell_quote(path))
    if is_command_success(result) then
        return true, nil
    end
    return nil, first_nonempty(result and result.stderr, result and result.stdout, "failed to create directory: " .. tostring(path))
end

local function decode_json_file(path)
    local content = read_text_file(path)
    if content == nil then
        return nil, "failed to read file: " .. path
    end
    return decode_json(content)
end

local function capture_command_output(context, command, output_path)
    local result = run_command(context, command .. " > " .. shell_quote(output_path))
    if result == nil or not is_command_success(result) then
        return nil, first_nonempty(result and result.stderr, result and result.stdout, "command failed")
    end

    local content = read_text_file(output_path)
    if content == nil then
        content = result.stdout
    end
    if content == nil then
        return nil, "failed to read command output from " .. output_path
    end
    return trim(content), nil
end

local function current_timestamp_utc(context, temp_dir)
    return capture_command_output(context, "date -u +%Y-%m-%dT%H:%M:%SZ", join_path(temp_dir, "timestamp.txt"))
end

local function sha256_digest_for_file(context, file_path, temp_dir)
    local output_path = join_path(temp_dir, path_basename(file_path) .. ".sha256")
    local content, capture_error = capture_command_output(context, "sha256sum " .. shell_quote(file_path), output_path)
    if content == nil then
        content, capture_error = capture_command_output(context, "shasum -a 256 " .. shell_quote(file_path), output_path)
        if content == nil then
            return nil, capture_error
        end
    end

    local digest = trim(content):match("^([0-9a-fA-F]+)")
    if digest == nil or #digest ~= 64 then
        return nil, "failed to parse sha256 for " .. file_path
    end
    return lower(digest), nil
end

local function file_link_count(context, path, temp_dir)
    if not path_exists(context, path) then
        return 0, nil
    end

    local output_path = join_path(temp_dir, path_basename(path) .. ".links")
    local content, capture_error = capture_command_output(context, "stat -c %h " .. shell_quote(path), output_path)
    if content == nil then
        content, capture_error = capture_command_output(context, "stat -f %l " .. shell_quote(path), output_path)
        if content == nil then
            return nil, capture_error
        end
    end

    local count = tonumber(trim(content))
    if count == nil then
        return nil, "failed to parse link count for " .. path
    end
    return count, nil
end

local function remove_path_if_exists(context, path)
    if not path_exists(context, path) then
        return true, nil
    end

    local result = run_command(context, "rm -rf " .. shell_quote(path))
    if is_command_success(result) then
        return true, nil
    end
    return nil, first_nonempty(result and result.stderr, result and result.stdout, "failed to remove path: " .. path)
end

local function build_command(binary, args)
    local parts = { shell_arg(binary) }
    for _, arg in ipairs(args or {}) do
        parts[#parts + 1] = shell_arg(arg)
    end
    return table.concat(parts, " ")
end

local function host_os_family(context)
    local value = first_nonempty(
        read_nested_field(context, "host", "platform", "osFamily"),
        read_nested_field(reqpack, "host", "platform", "osFamily")
    )
    return lower(value or "unknown")
end

local function unsupported_os_error(context)
    return "ollama app management supports Linux and macOS only"
end

local function is_app_package_name(name)
    return lower(trim(name)) == APP_PACKAGE_NAME
end

local function package_name(package)
    return trim(read_field(package, "name") or package)
end

local function package_version(package)
    return trim(read_field(package, "version"))
end

local function normalize_token(value)
    return tostring(value or ""):gsub("/", "__"):gsub("[^%w%._%-]+", "_")
end

local function make_model_spec(host, namespace, model, tag)
    local spec = {
        host = trim(host),
        namespace = trim(namespace),
        model = trim(model),
        tag = trim(tag),
    }

    if spec.host == "" then
        spec.host = DEFAULT_HOST
    end
    if spec.namespace == "" then
        spec.namespace = DEFAULT_NAMESPACE
    end
    if spec.tag == "" then
        spec.tag = DEFAULT_TAG
    end
    if spec.model == "" then
        return nil, "ollama model name missing"
    end

    if lower(spec.host) == DEFAULT_HOST and lower(spec.namespace) == DEFAULT_NAMESPACE then
        spec.cliName = spec.model .. ":" .. spec.tag
        spec.displayName = spec.model .. "@" .. spec.tag
    elseif lower(spec.host) == DEFAULT_HOST then
        spec.cliName = spec.namespace .. "/" .. spec.model .. ":" .. spec.tag
        spec.displayName = spec.namespace .. "/" .. spec.model .. "@" .. spec.tag
    else
        spec.cliName = spec.host .. "/" .. spec.namespace .. "/" .. spec.model .. ":" .. spec.tag
        spec.displayName = spec.host .. "/" .. spec.namespace .. "/" .. spec.model .. "@" .. spec.tag
    end
    spec.packageId = spec.cliName
    return spec, nil
end

local function parse_model_name(raw)
    local text = trim(raw)
    if text == "" then
        return nil, "ollama model name missing"
    end
    if is_app_package_name(text) then
        return nil, "app:ollama is not a model package"
    end

    local path_part = text
    local tag = DEFAULT_TAG
    if text:find("@", 1, true) ~= nil and text:find("@[^/@]+$") ~= nil then
        path_part, tag = text:match("^(.*)@([^/@]+)$")
    elseif text:find(":", 1, true) ~= nil and text:find(":[^/]+$") ~= nil then
        path_part, tag = text:match("^(.*):([^/:]+)$")
    end

    local segments = {}
    for segment in tostring(path_part or ""):gmatch("[^/]+") do
        segments[#segments + 1] = segment
    end

    if #segments == 1 then
        return make_model_spec(DEFAULT_HOST, DEFAULT_NAMESPACE, segments[1], tag)
    end
    if #segments == 2 then
        return make_model_spec(DEFAULT_HOST, segments[1], segments[2], tag)
    end
    if #segments == 3 then
        return make_model_spec(segments[1], segments[2], segments[3], tag)
    end
    return nil, "invalid ollama model name"
end

local function model_homepage_url(spec)
    if type(spec) ~= "table" then
        return nil
    end
    if lower(spec.host or "") ~= DEFAULT_HOST then
        return nil
    end
    local base = spec.namespace ~= DEFAULT_NAMESPACE and (spec.namespace .. "/" .. spec.model) or spec.model
    return "https://ollama.com/library/" .. base .. ":" .. spec.tag
end

local function unique_append(list, seen, value)
    local text = trim(value)
    if text == "" or seen[text] then
        return
    end
    seen[text] = true
    list[#list + 1] = text
end

local function candidate_models_roots(context)
    local candidates = {}
    local seen = {}

    unique_append(candidates, seen, read_proc_environ_value("OLLAMA_MODELS"))

    local home = trim(read_proc_environ_value("HOME") or "")
    local os_family = host_os_family(context)
    if os_family == "macos" then
        if home ~= "" then
            unique_append(candidates, seen, join_path(home, ".ollama", "models"))
        end
    elseif os_family == "linux" then
        unique_append(candidates, seen, "/usr/share/ollama/.ollama/models")
        if home ~= "" then
            unique_append(candidates, seen, join_path(home, ".ollama", "models"))
        end
    else
        if home ~= "" then
            unique_append(candidates, seen, join_path(home, ".ollama", "models"))
        end
    end

    return candidates
end

local function manifest_root_for_models_root(models_root)
    return join_path(models_root, "manifests")
end

local function model_manifest_path(models_root, spec)
    return join_path(manifest_root_for_models_root(models_root), spec.host, spec.namespace, spec.model, spec.tag)
end

local function blob_path_for_digest(models_root, digest)
    local normalized = tostring(digest or ""):gsub(":", "-")
    return join_path(models_root, "blobs", normalized)
end

local function digest_hex(digest)
    local hex = tostring(digest or ""):match("^sha256[:-]([0-9a-fA-F]+)$")
    if hex == nil or #hex ~= 64 then
        return nil
    end
    return lower(hex)
end

local function normalize_digest(digest)
    local hex = digest_hex(digest)
    if hex == nil then
        return nil
    end
    return "sha256:" .. hex
end

local function media_type_base(media_type)
    return trim((tostring(media_type or ""):match("^([^;]+)")))
end

local function media_type_param(media_type, key)
    local wanted = lower(trim(key or ""))
    for part in tostring(media_type or ""):gmatch(";([^;]+)") do
        local name, value = part:match("^%s*([^=]+)=?(.*)$")
        if lower(trim(name or "")) == wanted then
            return trim((value or ""):gsub('^"', ""):gsub('"$', ""))
        end
    end
    return nil
end

local function normalize_string_array(value)
    local items = {}
    for _, item in ipairs(type(value) == "table" and value or {}) do
        local text = trim(item)
        if text ~= "" then
            items[#items + 1] = text
        end
    end
    return items
end

local function contains_value(list, wanted)
    local needle = lower(trim(wanted))
    for _, item in ipairs(list or {}) do
        if lower(trim(item)) == needle then
            return true
        end
    end
    return false
end

local function record_layers(record)
    return type(read_field(record.manifest, "layers")) == "table" and read_field(record.manifest, "layers") or {}
end

local function read_model_config(record)
    local config_layer = read_field(record.manifest, "config")
    local digest = trim(type(config_layer) == "table" and read_field(config_layer, "digest") or "")
    if digest == "" then
        return {}, nil
    end

    local blob_path = blob_path_for_digest(record.modelsRoot, digest)
    local config, config_error = decode_json_file(blob_path)
    if config == nil then
        return {}, config_error
    end
    return config, nil
end

local function parse_manifest_relative_path(manifest_root, manifest_path)
    local prefix = strip_trailing_slashes(manifest_root) .. "/"
    if not starts_with(manifest_path, prefix) then
        return nil, "invalid ollama manifest path"
    end

    local relative = manifest_path:sub(#prefix + 1)
    local parts = {}
    for part in relative:gmatch("[^/]+") do
        parts[#parts + 1] = part
    end
    if #parts ~= 4 then
        return nil, "invalid ollama manifest layout"
    end
    return make_model_spec(parts[1], parts[2], parts[3], parts[4])
end

local function load_manifest_record(context, models_root, manifest_path)
    local manifest, manifest_error = decode_json_file(manifest_path)
    if manifest == nil then
        return nil, manifest_error
    end

    local spec, spec_error = parse_manifest_relative_path(manifest_root_for_models_root(models_root), manifest_path)
    if spec == nil then
        return nil, spec_error
    end

    local record = {
        modelsRoot = models_root,
        manifestPath = manifest_path,
        manifest = manifest,
        spec = spec,
    }
    local config, config_error = read_model_config(record)
    if config_error ~= nil then
        log_message(context, "warn", config_error)
    end
    record.config = config or {}
    return record, nil
end

local function find_local_record(context, spec)
    for _, models_root in ipairs(candidate_models_roots(context)) do
        local manifest_path = model_manifest_path(models_root, spec)
        if path_exists(context, manifest_path) then
            return load_manifest_record(context, models_root, manifest_path)
        end
    end
    return nil, nil
end

local function record_capabilities(record)
    local capabilities = normalize_string_array(read_field(record.config, "capabilities"))
    local layers = record_layers(record)
    local has_projector = false
    for _, layer in ipairs(layers) do
        local base = media_type_base(read_field(layer, "mediaType"))
        if base == "application/vnd.ollama.image.projector" then
            has_projector = true
        end
    end

    if has_projector and not contains_value(capabilities, "vision") then
        capabilities[#capabilities + 1] = "vision"
    end
    if tonumber(read_field(record.config, "embedding_length") or 0) > 0 and not contains_value(capabilities, "embedding") then
        capabilities[#capabilities + 1] = "embedding"
    end
    return capabilities
end

local function classify_record_kind(record)
    local capabilities = record_capabilities(record)
    if contains_value(capabilities, "vision") then
        return "model-vlm", { "vision-language" }
    end
    if contains_value(capabilities, "embedding") then
        return "model-embedding", { "embedding" }
    end
    return "model-llm", { "completion" }
end

local function summarize_record(record)
    local family = trim(read_field(record.config, "model_family") or "")
    local parameter_size = trim(read_field(record.config, "model_type") or "")
    local quantization = trim(read_field(record.config, "file_type") or "")
    local parts = {}
    if family ~= "" then
        parts[#parts + 1] = family
    end
    if parameter_size ~= "" then
        parts[#parts + 1] = parameter_size
    end
    if quantization ~= "" then
        parts[#parts + 1] = quantization
    end
    if #parts == 0 then
        return "Ollama model"
    end
    return "Ollama model " .. table.concat(parts, " ")
end

local function base_model_item(record, version_override)
    local spec = record.spec
    local capabilities = record_capabilities(record)
    local artifact_kind = classify_record_kind(record)
    local version = trim(first_nonempty(version_override, spec.tag))
    local homepage = model_homepage_url(spec)

    return {
        name = spec.displayName,
        packageId = spec.displayName,
        version = version ~= "" and version or nil,
        latestVersion = version ~= "" and version or nil,
        summary = summarize_record(record),
        description = summarize_record(record),
        homepage = homepage,
        sourceUrl = homepage,
        packageType = "model",
        type = "package",
        extraFields = {
            host = spec.host,
            namespace = spec.namespace,
            model = spec.model,
            tag = spec.tag,
            format = first_nonempty(read_field(record.config, "model_format")),
            family = first_nonempty(read_field(record.config, "model_family")),
            families = read_field(record.config, "model_families"),
            parameterSize = first_nonempty(read_field(record.config, "model_type")),
            quantization = first_nonempty(read_field(record.config, "file_type")),
            capabilities = capabilities,
            artifactKind = artifact_kind,
            contextLength = read_field(record.config, "context_length"),
            embeddingLength = read_field(record.config, "embedding_length"),
            localManifestPath = record.manifestPath,
            localModelsRoot = record.modelsRoot,
        },
    }
end

local function build_model_info_from_record(record, version_override)
    local item = base_model_item(record, version_override)
    local licenses = {}
    local system_prompt = nil
    local template_text = nil
    local messages_count = nil

    for _, layer in ipairs(record_layers(record)) do
        local digest = trim(read_field(layer, "digest") or "")
        local base = media_type_base(read_field(layer, "mediaType"))
        if digest ~= "" then
            local blob_path = blob_path_for_digest(record.modelsRoot, digest)
            if base == "application/vnd.ollama.image.license" then
                local text = read_text_file(blob_path)
                if text ~= nil and trim(text) ~= "" then
                    licenses[#licenses + 1] = trim(text)
                end
            elseif base == "application/vnd.ollama.image.system" then
                local text = read_text_file(blob_path)
                if text ~= nil and trim(text) ~= "" then
                    system_prompt = trim(text)
                end
            elseif base == "application/vnd.ollama.image.template" or base == "application/vnd.ollama.image.prompt" then
                local text = read_text_file(blob_path)
                if text ~= nil and trim(text) ~= "" then
                    template_text = trim(text)
                end
            elseif base == "application/vnd.ollama.image.messages" then
                local payload, payload_error = decode_json_file(blob_path)
                if payload_error == nil and type(payload) == "table" then
                    messages_count = #payload
                end
            end
        end
    end

    if #licenses > 0 then
        item.license = licenses[1]
        item.extraFields.licenses = licenses
    end
    if system_prompt ~= nil then
        item.extraFields.systemPrompt = system_prompt
    end
    if template_text ~= nil then
        item.extraFields.template = template_text
    end
    if messages_count ~= nil then
        item.extraFields.messageCount = messages_count
    end
    return item
end

local function detect_app_version(context)
    if not command_exists(context, "ollama") then
        return nil, "ollama not installed"
    end
    local result = run_command(context, "ollama -v")
    if result == nil or not is_command_success(result) then
        return nil, first_nonempty(result and result.stderr, result and result.stdout, "ollama version check failed")
    end

    local version = first_nonempty(
        tostring(result.stdout or ""):match("([0-9]+%.[0-9]+%.[0-9]+[%w%._%-]*)"),
        tostring(result.stderr or ""):match("([0-9]+%.[0-9]+%.[0-9]+[%w%._%-]*)")
    )
    if version == nil then
        return nil, "failed to parse ollama version"
    end
    return version, nil
end

local function build_app_item(version)
    return {
        name = APP_PACKAGE_NAME,
        packageId = APP_PACKAGE_NAME,
        version = version,
        latestVersion = version,
        summary = "Ollama runtime",
        description = "Ollama runtime and local model server",
        homepage = "https://ollama.com",
        sourceUrl = "https://ollama.com",
        packageType = "application",
        type = "package",
    }
end

local function static_app_search_item()
    return {
        name = APP_PACKAGE_NAME,
        packageId = APP_PACKAGE_NAME,
        summary = "Ollama runtime",
        description = "Ollama runtime and local model server",
        homepage = "https://ollama.com",
        sourceUrl = "https://ollama.com",
        packageType = "application",
        type = "package",
    }
end

local function install_script_command(version)
    if trim(version) ~= "" then
        return "curl -fsSL " .. INSTALL_SCRIPT_URL .. " | OLLAMA_VERSION=" .. shell_quote(version) .. " sh"
    end
    return "curl -fsSL " .. INSTALL_SCRIPT_URL .. " | sh"
end

local function uninstall_app_linux(context)
    local commands = {
        "command -v systemctl >/dev/null 2>&1 && systemctl stop ollama >/dev/null 2>&1 || true",
        "command -v systemctl >/dev/null 2>&1 && systemctl disable ollama >/dev/null 2>&1 || true",
        "command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload >/dev/null 2>&1 || true",
        "rm -f '/etc/systemd/system/ollama.service'",
        "rm -f '/usr/local/bin/ollama' '/usr/bin/ollama' '/bin/ollama'",
        "rm -rf '/usr/local/lib/ollama' '/usr/lib/ollama' '/lib/ollama'",
    }
    for _, command in ipairs(commands) do
        local result = run_command(context, command)
        if result == nil or not is_command_success(result) then
            return nil, first_nonempty(result and result.stderr, result and result.stdout, "ollama app removal failed")
        end
    end
    return true, nil
end

local function uninstall_app_macos(context)
    local commands = {
        "pkill -x 'Ollama' >/dev/null 2>&1 || true",
        "rm -f '/usr/local/bin/ollama'",
        "rm -rf '/Applications/Ollama.app'",
    }
    for _, command in ipairs(commands) do
        local result = run_command(context, command)
        if result == nil or not is_command_success(result) then
            return nil, first_nonempty(result and result.stderr, result and result.stdout, "ollama app removal failed")
        end
    end
    return true, nil
end

local function install_app(context, package)
    local os_family = host_os_family(context)
    if os_family ~= "linux" and os_family ~= "macos" then
        return nil, unsupported_os_error(context)
    end

    begin_step(context, "install ollama app")
    local command = install_script_command(package_version(package))
    local result = run_command(context, command)
    if result == nil or not is_command_success(result) then
        return nil, first_nonempty(result and result.stderr, result and result.stdout, "ollama install failed")
    end

    local version, version_error = detect_app_version(context)
    if version == nil then
        log_message(context, "warn", version_error)
        version = first_nonempty(package_version(package), "installed")
    end

    return build_app_item(version), nil
end

local function remove_app(context)
    local os_family = host_os_family(context)
    if os_family == "linux" then
        return uninstall_app_linux(context)
    end
    if os_family == "macos" then
        return uninstall_app_macos(context)
    end
    return nil, unsupported_os_error(context)
end

local function ensure_cli_available(context)
    if command_exists(context, "ollama") then
        return "ollama", nil
    end
    return nil, "ollama not installed; install app:ollama first or ensure ollama is on PATH"
end

local function list_manifest_paths(context)
    local paths = {}
    local seen = {}

    for _, models_root in ipairs(candidate_models_roots(context)) do
        local manifest_root = manifest_root_for_models_root(models_root)
        if path_exists(context, manifest_root) then
            local command = "find " .. shell_quote(manifest_root) .. " -type f | LC_ALL=C sort"
            local result = run_command(context, command)
            if result ~= nil and is_command_success(result) then
                for _, path in ipairs(split_lines(result.stdout)) do
                    unique_append(paths, seen, path)
                end
            end
        end
    end

    return paths
end

local function list_local_manifest_items(context)
    local items = {}
    for _, manifest_path in ipairs(list_manifest_paths(context)) do
        local models_root = manifest_path:match("^(.*)/manifests/")
        if models_root ~= nil and models_root ~= "" then
            local record = select(1, load_manifest_record(context, models_root, manifest_path))
            if record ~= nil then
                items[#items + 1] = build_model_info_from_record(record, record.spec.tag)
            end
        end
    end

    table.sort(items, function(left, right)
        return lower(left.packageId or left.name or "") < lower(right.packageId or right.name or "")
    end)
    return items
end

local function parse_ls_output(output)
    local items = {}
    for index, raw_line in ipairs(split_raw_lines(output)) do
        local line = trim(raw_line)
        if line ~= "" and index > 1 and not starts_with(line, "NAME") then
            local fields = split_whitespace(line)
            local name = trim(fields[1] or "")
            if name ~= "" then
                local spec = parse_model_name(name)
                if spec ~= nil then
                    items[#items + 1] = {
                        name = spec.displayName,
                        packageId = spec.displayName,
                        version = spec.tag,
                        latestVersion = spec.tag,
                        summary = "Ollama model",
                        description = "Ollama model",
                        homepage = model_homepage_url(spec),
                        sourceUrl = model_homepage_url(spec),
                        packageType = "model",
                        type = "package",
                        extraFields = {
                            host = spec.host,
                            namespace = spec.namespace,
                            model = spec.model,
                            tag = spec.tag,
                            localId = trim(fields[2] or ""),
                        },
                    }
                end
            end
        end
    end
    return items
end

local function list_cli_items(context, cli_binary)
    local result = run_command(context, build_command(cli_binary, { "ls" }))
    if result == nil or not is_command_success(result) then
        return {}, first_nonempty(result and result.stderr, result and result.stdout, "ollama ls failed")
    end
    return parse_ls_output(result.stdout), nil
end

local function parse_show_output(spec, output)
    local section = nil
    local model_fields = {}
    local capabilities = {}
    local licenses = {}

    for _, raw_line in ipairs(split_raw_lines(output)) do
        local line = raw_line:gsub("\r$", "")
        local text = trim(line)
        if text == "" then
        elseif raw_line:match("^  %S") and not raw_line:match("^    ") then
            section = text
        else
            if section == "Model" then
                local key, value = text:match("^([%a ][%a ]-)%s%s+(.+)$")
                if key ~= nil and value ~= nil then
                    model_fields[lower(trim(key))] = trim(value)
                end
            elseif section == "Capabilities" then
                capabilities[#capabilities + 1] = text
            elseif section == "License" then
                licenses[#licenses + 1] = text
            end
        end
    end

    local item = {
        name = spec.displayName,
        packageId = spec.displayName,
        version = spec.tag,
        latestVersion = spec.tag,
        summary = "Ollama model",
        description = "Ollama model",
        homepage = model_homepage_url(spec),
        sourceUrl = model_homepage_url(spec),
        packageType = "model",
        type = "package",
        extraFields = {
            host = spec.host,
            namespace = spec.namespace,
            model = spec.model,
            tag = spec.tag,
            family = model_fields["architecture"],
            parameterSize = model_fields["parameters"],
            quantization = model_fields["quantization"],
            contextLength = model_fields["context length"],
            embeddingLength = model_fields["embedding length"],
            capabilities = capabilities,
        },
    }

    if #licenses > 0 then
        item.license = table.concat(licenses, "\n")
    end
    return item
end

local function info_from_show_cli(context, cli_binary, spec)
    local result = run_command(context, build_command(cli_binary, { "show", spec.cliName }))
    if result == nil or not is_command_success(result) then
        return nil, first_nonempty(result and result.stderr, result and result.stdout, "ollama show failed")
    end
    return parse_show_output(spec, result.stdout), nil
end

local function build_artifact_id(spec, artifact_kind, revision)
    return join_path("ollama", artifact_kind, spec.packageId) .. "@" .. revision
end

local function aicache_root()
    local data_root = get_reqpack_path("dataRoot")
    if data_root ~= nil then
        return join_path(data_root, "aicache")
    end

    local xdg_data_home = read_proc_environ_value("XDG_DATA_HOME")
    if xdg_data_home ~= nil and xdg_data_home ~= "" then
        return join_path(xdg_data_home, "aicache")
    end

    local home = read_proc_environ_value("HOME")
    if home ~= nil and home ~= "" then
        return join_path(home, ".local", "share", "aicache")
    end

    return nil
end

local function artifact_view_paths(root, spec, artifact_kind, artifact_id, revision, logical_path, format)
    return {
        join_path(root, "views", "by-kind", artifact_kind, artifact_id, logical_path),
        join_path(root, "views", "by-format", format, artifact_id, logical_path),
        join_path(root, "views", "by-source", "ollama", "model", normalize_token(spec.packageId), revision, logical_path),
    }
end

local function aicache_current_path(root, spec)
    return join_path(root, "views", "by-source", "ollama", "model", normalize_token(spec.packageId), "current.json")
end

local function detect_weight_format(record, layer)
    return lower(first_nonempty(
        read_field(record.config, "model_format"),
        media_type_param(read_field(read_field(record, "manifest") or {}, "config") and read_field(read_field(record.manifest, "config"), "mediaType") or "", "type"),
        media_type_param(read_field(layer, "mediaType"), "type"),
        "bin"
    ))
end

local function build_file_entries(record)
    local entries = {}
    local counters = {
        model = 0,
        projector = 0,
        adapter = 0,
        license = 0,
        unknown = 0,
    }

    local function append_entry(logical_path, role, format, layer)
        local digest = normalize_digest(read_field(layer, "digest"))
        if digest == nil then
            return nil, "invalid ollama layer digest"
        end
        local source_path = blob_path_for_digest(record.modelsRoot, digest)
        if not path_exists(nil, source_path) then
            return nil, "ollama blob missing: " .. source_path
        end
        entries[#entries + 1] = {
            logical_path = logical_path,
            role = role,
            format = format,
            blob_id = digest,
            size = tonumber(read_field(layer, "size") or 0) or 0,
            source_path = source_path,
            media_type = read_field(layer, "mediaType"),
        }
        return true, nil
    end

    local config_layer = read_field(record.manifest, "config")
    if type(config_layer) == "table" and trim(read_field(config_layer, "digest") or "") ~= "" then
        local ok, err = append_entry("config.json", "config", "json", config_layer)
        if not ok then
            return nil, err
        end
    end

    for _, layer in ipairs(record_layers(record)) do
        local base = media_type_base(read_field(layer, "mediaType"))
        local ok, err
        if base == "application/vnd.ollama.image.template" or base == "application/vnd.ollama.image.prompt" then
            ok, err = append_entry("template.txt", "template", "txt", layer)
        elseif base == "application/vnd.ollama.image.system" then
            ok, err = append_entry("system.txt", "system", "txt", layer)
        elseif base == "application/vnd.ollama.image.params" then
            ok, err = append_entry("parameters.json", "parameters", "json", layer)
        elseif base == "application/vnd.ollama.image.messages" then
            ok, err = append_entry("messages.json", "messages", "json", layer)
        elseif base == "application/vnd.ollama.image.license" then
            counters.license = counters.license + 1
            local logical = counters.license == 1 and "license.txt" or join_path("licenses", "license-" .. tostring(counters.license) .. ".txt")
            ok, err = append_entry(logical, "license", "txt", layer)
        elseif base == "application/vnd.ollama.image.projector" then
            counters.projector = counters.projector + 1
            local format = detect_weight_format(record, layer)
            local logical = counters.projector == 1 and ("projector." .. format) or join_path("projectors", "projector-" .. tostring(counters.projector) .. "." .. format)
            ok, err = append_entry(logical, "projector", format, layer)
        elseif base == "application/vnd.ollama.image.adapter" then
            counters.adapter = counters.adapter + 1
            local format = detect_weight_format(record, layer)
            local logical = counters.adapter == 1 and ("adapter." .. format) or join_path("adapters", "adapter-" .. tostring(counters.adapter) .. "." .. format)
            ok, err = append_entry(logical, "adapter", format, layer)
        elseif base == "application/vnd.ollama.image.model" or base == "application/vnd.ollama.image.tensor" then
            counters.model = counters.model + 1
            local format = detect_weight_format(record, layer)
            local logical = counters.model == 1 and ("model." .. format) or join_path("weights", "model-" .. tostring(counters.model) .. "." .. format)
            ok, err = append_entry(logical, "weights", format, layer)
        else
            counters.unknown = counters.unknown + 1
            ok, err = append_entry(join_path("layers", "layer-" .. tostring(counters.unknown) .. ".bin"), "unknown", "bin", layer)
        end
        if not ok then
            return nil, err
        end
    end

    return entries, nil
end

local function adopt_blob(context, source_path, blob_path)
    if path_exists(context, blob_path) then
        return true, nil
    end

    local ok, err = ensure_directory(context, path_dirname(blob_path))
    if not ok then
        return nil, err
    end

    local link_result = run_command(context, "ln " .. shell_quote(source_path) .. " " .. shell_quote(blob_path))
    if link_result ~= nil and is_command_success(link_result) then
        return true, nil
    end

    local copy_result = run_command(context, "cp " .. shell_quote(source_path) .. " " .. shell_quote(blob_path))
    if copy_result ~= nil and is_command_success(copy_result) then
        return true, nil
    end

    return nil, first_nonempty(
        copy_result and copy_result.stderr,
        copy_result and copy_result.stdout,
        link_result and link_result.stderr,
        link_result and link_result.stdout,
        "failed to adopt blob"
    )
end

local function materialize_view_file(context, blob_path, target_path)
    local ok, err = ensure_directory(context, path_dirname(target_path))
    if not ok then
        return nil, err
    end

    if path_exists(context, target_path) then
        local remove_result = run_command(context, "rm -f " .. shell_quote(target_path))
        if remove_result == nil or not is_command_success(remove_result) then
            return nil, first_nonempty(remove_result and remove_result.stderr, remove_result and remove_result.stdout, "failed to replace existing view file")
        end
    end

    local link_result = run_command(context, "ln " .. shell_quote(blob_path) .. " " .. shell_quote(target_path))
    if link_result ~= nil and is_command_success(link_result) then
        return true, nil
    end

    local copy_result = run_command(context, "cp " .. shell_quote(blob_path) .. " " .. shell_quote(target_path))
    if copy_result ~= nil and is_command_success(copy_result) then
        return true, nil
    end

    return nil, first_nonempty(
        copy_result and copy_result.stderr,
        copy_result and copy_result.stdout,
        link_result and link_result.stderr,
        link_result and link_result.stdout,
        "failed to materialize view file"
    )
end

local function sync_aicache_for_record(context, record)
    local root = aicache_root()
    if root == nil or root == "" then
        return nil, "aicache root unavailable"
    end

    local temp_dir = context ~= nil and context.fs ~= nil and type(context.fs.get_tmp_dir) == "function" and context.fs.get_tmp_dir() or ""
    if trim(temp_dir) == "" then
        return nil, "temporary directory unavailable"
    end

    local scaffold_paths = {
        join_path(root, "blobs", "sha256"),
        join_path(root, "artifacts"),
        join_path(root, "views", "by-kind"),
        join_path(root, "views", "by-format"),
        join_path(root, "views", "by-source"),
        join_path(root, "index"),
        join_path(root, "pins"),
        join_path(root, "staging"),
        join_path(root, "gc"),
    }
    for _, path in ipairs(scaffold_paths) do
        local ok, err = ensure_directory(context, path)
        if not ok then
            return nil, err
        end
    end

    local revision, revision_error = sha256_digest_for_file(context, record.manifestPath, temp_dir)
    if revision == nil then
        return nil, revision_error
    end

    local created_at, timestamp_error = current_timestamp_utc(context, temp_dir)
    if created_at == nil then
        return nil, timestamp_error
    end

    local file_entries, files_error = build_file_entries(record)
    if file_entries == nil then
        return nil, files_error
    end
    if #file_entries == 0 then
        return nil, "ollama manifest produced no files"
    end

    local artifact_kind, tasks = classify_record_kind(record)
    local artifact_id = build_artifact_id(record.spec, artifact_kind, revision)
    local artifact_path = join_path(root, "artifacts", artifact_id)
    local ok, err = ensure_directory(context, artifact_path)
    if not ok then
        return nil, err
    end

    for _, entry in ipairs(file_entries) do
        local digest = digest_hex(entry.blob_id)
        local blob_path = join_path(root, "blobs", "sha256", digest:sub(1, 2), digest)
        ok, err = adopt_blob(context, entry.source_path, blob_path)
        if not ok then
            return nil, err
        end

        for _, view_path in ipairs(artifact_view_paths(root, record.spec, artifact_kind, artifact_id, revision, entry.logical_path, entry.format)) do
            ok, err = materialize_view_file(context, blob_path, view_path)
            if not ok then
                return nil, err
            end
        end
    end

    local aliases = {
        {
            system = "ollama",
            package_id = record.spec.displayName,
        }
    }

    local manifest_payload = {
        artifact_id = artifact_id,
        kind = artifact_kind,
        tasks = tasks,
        aliases = aliases,
        source = {
            registry = "ollama",
            repo_type = "model",
            package_id = record.spec.displayName,
            host = record.spec.host,
            namespace = record.spec.namespace,
            model = record.spec.model,
            tag = record.spec.tag,
            revision = revision,
            refs = { record.spec.tag },
        },
        created_at = created_at,
    }

    local source_metadata = {
        ingest_mode = "adopted-from-ollama",
        source_cache_paths = { record.modelsRoot },
        managed_source_cache = false,
        fetched_at = created_at,
        upstream_metadata = {
            model_name = record.spec.displayName,
            homepage = model_homepage_url(record.spec),
            source_url = model_homepage_url(record.spec),
            format = read_field(record.config, "model_format"),
            family = read_field(record.config, "model_family"),
            families = read_field(record.config, "model_families"),
            parameter_size = read_field(record.config, "model_type"),
            quantization = read_field(record.config, "file_type"),
            capabilities = record_capabilities(record),
            context_length = read_field(record.config, "context_length"),
            embedding_length = read_field(record.config, "embedding_length"),
            base_name = read_field(record.config, "base_name"),
            architecture = read_field(record.config, "architecture"),
            os = read_field(record.config, "os"),
        },
    }

    local manifest_ok, manifest_error = write_text_file(join_path(artifact_path, "manifest.json"), encode_json(manifest_payload))
    if not manifest_ok then
        return nil, manifest_error
    end

    local files_ok, files_write_error = write_text_file(join_path(artifact_path, "files.json"), encode_json({ files = file_entries }))
    if not files_ok then
        return nil, files_write_error
    end

    local source_ok, source_error = write_text_file(join_path(artifact_path, "source.json"), encode_json(source_metadata))
    if not source_ok then
        return nil, source_error
    end

    local current_path = aicache_current_path(root, record.spec)
    ok, err = ensure_directory(context, path_dirname(current_path))
    if not ok then
        return nil, err
    end
    local current_ok, current_error = write_text_file(current_path, encode_json({
        artifact_id = artifact_id,
        artifact_path = artifact_path,
        revision = revision,
    }))
    if not current_ok then
        return nil, current_error
    end

    return {
        artifactId = artifact_id,
        artifactPath = artifact_path,
        sourcePath = record.manifestPath,
        revision = revision,
    }, nil
end

local function parse_artifact_layout(root, artifact_path)
    local manifest, manifest_error = decode_json_file(join_path(artifact_path, "manifest.json"))
    if manifest == nil then
        return nil, manifest_error
    end

    local files_payload, files_error = decode_json_file(join_path(artifact_path, "files.json"))
    if files_payload == nil then
        return nil, files_error
    end

    local source_payload, source_error = decode_json_file(join_path(artifact_path, "source.json"))
    if source_payload == nil then
        return nil, source_error
    end

    local files = read_field(files_payload, "files")
    if type(files) ~= "table" then
        return nil, "invalid artifact files manifest"
    end

    local source = read_field(manifest, "source")
    local artifact_id = trim(read_field(manifest, "artifact_id") or path_basename(artifact_path))
    local artifact_kind = trim(read_field(manifest, "kind") or "unknown-ai-artifact")
    local package_id = trim(type(source) == "table" and read_field(source, "package_id") or "")
    local revision = trim(type(source) == "table" and read_field(source, "revision") or "")
    local spec = parse_model_name(package_id)
    if spec == nil then
        spec = { packageId = package_id, displayName = package_id }
    end
    if revision == "" then
        revision = artifact_id:match("@([^@]+)$") or "unknown"
    end

    local blob_paths = {}
    local view_paths = {}
    for _, entry in ipairs(files) do
        if type(entry) == "table" then
            local blob_id = trim(read_field(entry, "blob_id") or "")
            local digest = digest_hex(blob_id)
            local logical_path = trim(read_field(entry, "logical_path") or "")
            local format = trim(read_field(entry, "format") or "unknown")
            if digest ~= nil and logical_path ~= "" then
                blob_paths[#blob_paths + 1] = join_path(root, "blobs", "sha256", digest:sub(1, 2), digest)
                for _, path in ipairs(artifact_view_paths(root, spec, artifact_kind, artifact_id, revision, logical_path, format)) do
                    view_paths[#view_paths + 1] = path
                end
            end
        end
    end

    return {
        artifactId = artifact_id,
        artifactKind = artifact_kind,
        artifactPath = artifact_path,
        manifest = manifest,
        sourceMetadata = source_payload,
        spec = spec,
        revision = revision,
        fileCount = #files,
        blobPaths = blob_paths,
        viewPaths = view_paths,
    }, nil
end

local function build_info_from_aicache_layout(layout)
    if type(layout) ~= "table" then
        return nil
    end

    local manifest = type(layout.manifest) == "table" and layout.manifest or {}
    local source = type(read_field(manifest, "source")) == "table" and read_field(manifest, "source") or {}
    local source_metadata = type(layout.sourceMetadata) == "table" and layout.sourceMetadata or {}
    local upstream = type(read_field(source_metadata, "upstream_metadata")) == "table" and read_field(source_metadata, "upstream_metadata") or {}
    local package_id = trim(read_field(source, "package_id") or layout.spec.packageId or "")
    local spec = parse_model_name(package_id)
    local description = first_nonempty(
        read_field(upstream, "family") and ("Ollama model " .. tostring(read_field(upstream, "family"))),
        "Ollama model stored in AICache"
    )
    local version = trim(first_nonempty(read_field(source, "revision"), layout.revision, "unknown"))

    return {
        name = package_id,
        packageId = package_id,
        version = version,
        latestVersion = version,
        summary = description,
        description = description,
        homepage = first_nonempty(read_field(upstream, "homepage"), model_homepage_url(spec)),
        sourceUrl = first_nonempty(read_field(upstream, "source_url"), model_homepage_url(spec)),
        packageType = "model",
        type = "package",
        license = first_nonempty(read_field(upstream, "license")),
        updatedAt = first_nonempty(read_field(source_metadata, "fetched_at")),
        extraFields = {
            host = spec and spec.host or nil,
            namespace = spec and spec.namespace or nil,
            model = spec and spec.model or nil,
            tag = spec and spec.tag or nil,
            artifactKind = layout.artifactKind,
            aicacheArtifactId = layout.artifactId,
            aicacheArtifactPath = layout.artifactPath,
            aicacheFileCount = tostring(layout.fileCount or 0),
            format = read_field(upstream, "format"),
            family = read_field(upstream, "family"),
            families = read_field(upstream, "families"),
            parameterSize = read_field(upstream, "parameter_size"),
            quantization = read_field(upstream, "quantization"),
            capabilities = read_field(upstream, "capabilities"),
            contextLength = read_field(upstream, "context_length"),
            embeddingLength = read_field(upstream, "embedding_length"),
        },
    }
end

local function list_aicache_current_paths(context)
    local root = aicache_root()
    if root == nil or root == "" then
        return {}, nil
    end

    local source_root = join_path(root, "views", "by-source", "ollama")
    if not path_exists(context, source_root) then
        return {}, nil
    end

    local command = "find " .. shell_quote(source_root) .. " -type f -name 'current.json' | LC_ALL=C sort"
    local result = run_command(context, command)
    if result == nil or not is_command_success(result) then
        return {}, first_nonempty(result and result.stderr, result and result.stdout, "failed to list ollama aicache current pointers")
    end
    return split_lines(result.stdout), nil
end

local function read_aicache_layout_from_current_path(context, current_path)
    local current, current_error = decode_json_file(current_path)
    if current == nil then
        return nil, current_error
    end

    local artifact_path = trim(read_field(current, "artifact_path") or "")
    local root = current_path:match("^(.*)/views/")
    if root == nil or root == "" then
        return nil, "failed to derive aicache root from current pointer"
    end

    if artifact_path == "" then
        local artifact_id = trim(read_field(current, "artifact_id") or "")
        if artifact_id == "" then
            return nil, "invalid aicache current pointer"
        end
        artifact_path = join_path(root, "artifacts", artifact_id)
    end
    if not path_exists(context, artifact_path) then
        return nil, nil
    end

    return parse_artifact_layout(root, artifact_path)
end

local function list_aicache(context)
    local current_paths, current_error = list_aicache_current_paths(context)
    if current_paths == nil then
        return {}, current_error
    end

    local items = {}
    for _, current_path in ipairs(current_paths) do
        local layout = select(1, read_aicache_layout_from_current_path(context, current_path))
        local item = build_info_from_aicache_layout(layout)
        if item ~= nil then
            items[#items + 1] = item
        end
    end

    table.sort(items, function(left, right)
        return lower(left.packageId or left.name or "") < lower(right.packageId or right.name or "")
    end)
    return items, current_error
end

local function lookup_aicache_layout(context, spec)
    local root = aicache_root()
    if root == nil or root == "" then
        return nil, nil
    end

    local current_path = aicache_current_path(root, spec)
    if not path_exists(context, current_path) then
        return nil, nil
    end

    return read_aicache_layout_from_current_path(context, current_path)
end

local function lookup_aicache_info(context, spec)
    local layout, layout_error = lookup_aicache_layout(context, spec)
    if layout == nil then
        return nil, layout_error
    end
    return build_info_from_aicache_layout(layout), nil
end

local function locate_aicache_artifact(context, spec)
    local root = aicache_root()
    if root == nil or root == "" then
        return nil, nil
    end

    local current_path = aicache_current_path(root, spec)
    if not path_exists(context, current_path) then
        return nil, nil
    end

    local current, current_error = decode_json_file(current_path)
    if current == nil then
        return nil, current_error
    end

    local artifact_path = trim(read_field(current, "artifact_path") or "")
    if artifact_path ~= "" and path_exists(context, artifact_path) then
        return artifact_path, nil
    end

    local artifact_id = trim(read_field(current, "artifact_id") or "")
    if artifact_id ~= "" then
        local candidate = join_path(root, "artifacts", artifact_id)
        if path_exists(context, candidate) then
            return candidate, nil
        end
    end

    return nil, nil
end

local function cleanup_aicache_artifact(context, spec)
    local artifact_path, locate_error = locate_aicache_artifact(context, spec)
    if locate_error ~= nil then
        return nil, locate_error
    end
    if artifact_path == nil or not path_exists(context, artifact_path) then
        return false, nil
    end

    local root = artifact_path:match("^(.*)/artifacts/")
    if root == nil or root == "" then
        return nil, "failed to derive aicache root from artifact path"
    end

    local temp_dir = context ~= nil and context.fs ~= nil and type(context.fs.get_tmp_dir) == "function" and context.fs.get_tmp_dir() or ""
    if trim(temp_dir) == "" then
        return nil, "temporary directory unavailable"
    end

    local layout, layout_error = parse_artifact_layout(root, artifact_path)
    if layout == nil then
        return nil, layout_error
    end

    for _, path in ipairs(layout.viewPaths) do
        local ok, remove_error = remove_path_if_exists(context, path)
        if not ok then
            return nil, remove_error
        end
    end

    local ok, remove_error = remove_path_if_exists(context, layout.artifactPath)
    if not ok then
        return nil, remove_error
    end

    ok, remove_error = remove_path_if_exists(context, aicache_current_path(root, spec))
    if not ok then
        return nil, remove_error
    end

    for _, blob_path in ipairs(layout.blobPaths) do
        local link_count, link_error = file_link_count(context, blob_path, temp_dir)
        if link_count == nil then
            return nil, link_error
        end
        if link_count <= 1 then
            local removed, blob_error = remove_path_if_exists(context, blob_path)
            if not removed then
                return nil, blob_error
            end
        end
    end

    return true, nil
end

local function annotate_aicache_fields(item, aicache)
    if type(item) ~= "table" or type(aicache) ~= "table" then
        return item
    end
    item.extraFields = merge_extra_fields(item.extraFields, {
        aicacheArtifactId = aicache.artifactId,
        aicacheArtifactPath = aicache.artifactPath,
        aicacheSourcePath = aicache.sourcePath,
        revision = aicache.revision,
    })
    return item
end

local function split_requested_packages(packages)
    local app_packages = {}
    local model_packages = {}
    for _, package in ipairs(packages or {}) do
        if is_app_package_name(package_name(package)) then
            app_packages[#app_packages + 1] = package
        else
            model_packages[#model_packages + 1] = package
        end
    end
    return app_packages, model_packages
end

local function build_removed_model_item(spec)
    return {
        name = spec.displayName,
        packageId = spec.displayName,
        version = spec.tag,
        packageType = "model",
        type = "package",
        extraFields = {
            host = spec.host,
            namespace = spec.namespace,
            model = spec.model,
            tag = spec.tag,
        },
    }
end

function plugin.getName()
    return PLUGIN_NAME
end

function plugin.getVersion()
    return PLUGIN_VERSION
end

function plugin.getRequirements()
    return {}
end

function plugin.getCategories()
    return { "AI", "Package Manager", "Ollama" }
end

function plugin.getMissingPackages(packages)
    local installed = plugin.list(nil)
    local lookup = {}
    for _, item in ipairs(installed or {}) do
        lookup[item.name] = true
        if item.packageId ~= nil then
            lookup[item.packageId] = true
        end
    end

    local missing = {}
    for _, package in ipairs(packages or {}) do
        local name = package_name(package)
        local action = lower(read_field(package, "action") or "")
        local exists = lookup[name] == true
        if action == "remove" or action == "update" then
            if exists then
                missing[#missing + 1] = package
            end
        elseif not exists then
            missing[#missing + 1] = package
        end
    end
    return missing
end

function plugin.install(context, packages)
    local requested = packages or {}
    if #requested == 0 then
        return true
    end

    local app_packages, model_packages = split_requested_packages(requested)
    local installed = {}

    if #app_packages > 0 then
        local item, err = install_app(context, app_packages[1])
        if item == nil then
            tx_failed(context, err)
            return false
        end
        installed[#installed + 1] = item
    end

    if #model_packages > 0 then
        local cli_binary, cli_error = ensure_cli_available(context)
        if cli_binary == nil then
            tx_failed(context, cli_error)
            return false
        end

        for _, package in ipairs(model_packages) do
            local spec, spec_error = parse_model_name(package_name(package))
            if spec == nil then
                tx_failed(context, spec_error)
                return false
            end

            begin_step(context, "pull ollama model " .. spec.displayName)
            local result = run_command(context, build_command(cli_binary, { "pull", spec.cliName }))
            if result == nil or not is_command_success(result) then
                tx_failed(context, first_nonempty(result and result.stderr, result and result.stdout, "ollama pull failed"))
                return false
            end

            local record, record_error = find_local_record(context, spec)
            if record == nil then
                tx_failed(context, first_nonempty(record_error, "ollama model manifest unavailable after pull"))
                return false
            end

            local item = build_model_info_from_record(record, spec.tag)
            local aicache, aicache_error = sync_aicache_for_record(context, record)
            if aicache == nil then
                tx_failed(context, first_nonempty(aicache_error, "ollama aicache adoption failed"))
                return false
            end
            annotate_aicache_fields(item, aicache)
            installed[#installed + 1] = item
        end
    end

    emit_event(context, "installed", installed)
    tx_success(context)
    return true
end

function plugin.installLocal(context, path)
    begin_step(context, "install local ollama artifact")
    tx_failed(context, "ollama plugin does not support installLocal()")
    emit_event(context, "unavailable", {
        path = path,
        reason = "local-install-unsupported",
    })
    return false
end

function plugin.remove(context, packages)
    local requested = packages or {}
    if #requested == 0 then
        return true
    end

    local app_packages, model_packages = split_requested_packages(requested)
    local removed = {}

    if #model_packages > 0 then
        local cli_binary, cli_error = ensure_cli_available(context)
        if cli_binary == nil then
            tx_failed(context, cli_error)
            return false
        end

        for _, package in ipairs(model_packages) do
            local spec, spec_error = parse_model_name(package_name(package))
            if spec == nil then
                tx_failed(context, spec_error)
                return false
            end

            begin_step(context, "remove ollama model " .. spec.displayName)
            local result = run_command(context, build_command(cli_binary, { "rm", spec.cliName }))
            if result == nil or not is_command_success(result) then
                tx_failed(context, first_nonempty(result and result.stderr, result and result.stdout, "ollama rm failed"))
                return false
            end

            local cleaned, cleanup_error = cleanup_aicache_artifact(context, spec)
            if cleanup_error ~= nil then
                tx_failed(context, cleanup_error)
                return false
            end
            if cleaned then
                log_message(context, "info", "removed aicache artifact for " .. spec.displayName)
            end

            removed[#removed + 1] = build_removed_model_item(spec)
        end
    end

    if #app_packages > 0 then
        begin_step(context, "remove ollama app")
        local ok, err = remove_app(context)
        if not ok then
            tx_failed(context, err)
            return false
        end
        removed[#removed + 1] = build_app_item(nil)
    end

    emit_event(context, "deleted", removed)
    tx_success(context)
    return true
end

function plugin.update(context, packages)
    local requested = packages or {}
    if #requested == 0 then
        return true
    end

    local app_packages, model_packages = split_requested_packages(requested)
    local updated = {}

    if #app_packages > 0 then
        local item, err = install_app(context, app_packages[1])
        if item == nil then
            tx_failed(context, err)
            return false
        end
        updated[#updated + 1] = item
    end

    if #model_packages > 0 then
        local cli_binary, cli_error = ensure_cli_available(context)
        if cli_binary == nil then
            tx_failed(context, cli_error)
            return false
        end

        for _, package in ipairs(model_packages) do
            local spec, spec_error = parse_model_name(package_name(package))
            if spec == nil then
                tx_failed(context, spec_error)
                return false
            end

            begin_step(context, "update ollama model " .. spec.displayName)
            local result = run_command(context, build_command(cli_binary, { "pull", spec.cliName }))
            if result == nil or not is_command_success(result) then
                tx_failed(context, first_nonempty(result and result.stderr, result and result.stdout, "ollama pull failed"))
                return false
            end

            local record, record_error = find_local_record(context, spec)
            if record == nil then
                tx_failed(context, first_nonempty(record_error, "ollama model manifest unavailable after update"))
                return false
            end

            local item = build_model_info_from_record(record, spec.tag)
            local aicache, aicache_error = sync_aicache_for_record(context, record)
            if aicache == nil then
                tx_failed(context, first_nonempty(aicache_error, "ollama aicache adoption failed"))
                return false
            end
            annotate_aicache_fields(item, aicache)
            updated[#updated + 1] = item
        end
    end

    emit_event(context, "updated", updated)
    tx_success(context)
    return true
end

function plugin.list(context)
    local items = {}

    local version = select(1, detect_app_version(context))
    if version ~= nil then
        items[#items + 1] = build_app_item(version)
    end

    local model_items, aicache_error = list_aicache(context)
    if model_items ~= nil and #model_items > 0 then
        for _, item in ipairs(model_items) do
            items[#items + 1] = item
        end
        emit_event(context, "listed", items)
        return items
    end

    if aicache_error ~= nil then
        log_message(context, "warn", aicache_error)
    end

    local local_items = list_local_manifest_items(context)
    if #local_items > 0 then
        for _, item in ipairs(local_items) do
            items[#items + 1] = item
        end
        emit_event(context, "listed", items)
        return items
    end

    local cli_binary = select(1, ensure_cli_available(context))
    if cli_binary ~= nil then
        local cli_items, cli_error = list_cli_items(context, cli_binary)
        if cli_error ~= nil then
            log_message(context, "warn", cli_error)
        end
        for _, item in ipairs(cli_items or {}) do
            items[#items + 1] = item
        end
    end

    emit_event(context, "listed", items)
    return items
end

function plugin.outdated(context)
    local empty = {}
    emit_event(context, "outdated", empty)
    return empty
end

function plugin.search(context, prompt)
    local query = lower(trim(prompt))
    local items = {}
    if query ~= "" and (query == "ollama" or query == APP_PACKAGE_NAME or starts_with(APP_PACKAGE_NAME, query) or starts_with(query, "app:ollama")) then
        items[#items + 1] = static_app_search_item()
    end
    emit_event(context, "searched", items)
    return items
end

function plugin.info(context, name)
    local query = trim(name)
    if query == "" then
        emit_event(context, "informed", {})
        return {}
    end

    if is_app_package_name(query) then
        local version, version_error = detect_app_version(context)
        if version == nil then
            if version_error ~= nil then
                log_message(context, "warn", version_error)
            end
            emit_event(context, "informed", {})
            return {}
        end
        local item = build_app_item(version)
        emit_event(context, "informed", item)
        return item
    end

    local spec, spec_error = parse_model_name(query)
    if spec == nil then
        log_message(context, "warn", spec_error)
        emit_event(context, "informed", {})
        return {}
    end

    local cached_item, cached_error = lookup_aicache_info(context, spec)
    if cached_item ~= nil then
        emit_event(context, "informed", cached_item)
        return cached_item
    end

    local record, record_error = find_local_record(context, spec)
    if record ~= nil then
        local item = build_model_info_from_record(record, spec.tag)
        emit_event(context, "informed", item)
        return item
    end
    if cached_error ~= nil then
        log_message(context, "warn", cached_error)
    end
    if record_error ~= nil then
        log_message(context, "warn", record_error)
    end

    local cli_binary, cli_error = ensure_cli_available(context)
    if cli_binary == nil then
        if cli_error ~= nil then
            log_message(context, "warn", cli_error)
        end
        emit_event(context, "informed", {})
        return {}
    end

    local item, show_error = info_from_show_cli(context, cli_binary, spec)
    if item == nil then
        if show_error ~= nil then
            log_message(context, "warn", show_error)
        end
        emit_event(context, "informed", {})
        return {}
    end

    emit_event(context, "informed", item)
    return item
end

function plugin.resolvePackage(context, package)
    local name = package_name(package)
    if name == "" then
        return nil
    end
    if is_app_package_name(name) then
        return static_app_search_item()
    end

    local spec = parse_model_name(name)
    if spec == nil then
        return nil
    end

    local item = plugin.info(context, spec.displayName)
    if type(item) == "table" and first_nonempty(item.packageId, item.name) ~= nil then
        return item
    end

    return {
        name = spec.displayName,
        packageId = spec.displayName,
        version = spec.tag,
        packageType = "model",
        type = "package",
        extraFields = {
            host = spec.host,
            namespace = spec.namespace,
            model = spec.model,
            tag = spec.tag,
            cliName = spec.cliName,
        },
    }
end

function plugin.getSecurityMetadata()
    return {
        role = "package-manager",
        capabilities = { "exec", "network" },
        ecosystemScopes = { "ollama" },
        writeScopes = {
            { kind = "temp" },
            { kind = "user-home-subpath", value = ".local/share/aicache" },
            { kind = "user-home-subpath", value = ".ollama" },
            { kind = "system-path", value = "/usr/share/ollama" },
            { kind = "system-path", value = "/Applications/Ollama.app" },
        },
        networkScopes = {
            { host = "ollama.com", scheme = "https" },
        },
        privilegeLevel = "sudo",
        purlType = "generic",
    }
end

function plugin.init()
    return true
end

function plugin.shutdown()
    return true
end

return plugin
