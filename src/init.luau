local fs = require("@std/fs")
local process = require("@std/process")
local path = require("@std/path")

local dotenv = {}

local function processVariables(variables: { [string]: string }, str: string)
	return string.gsub(str, "%${(.-)}", function(key)
		if variables[key] then
			return variables[key]
		else
			return "${" .. key .. "}" -- avoided template literal cause it looked weird
		end
	end)
end

-- parses the content of a double-quoted value (after the opening quote has been stripped)
-- returns the parsed string, or nil if the closing quote was never found
local function parseDoubleQuotedValue(str: string): string?
	local result = {}
	local pos = 1
	local len = string.len(str)

	while pos <= len do
		local ch = string.sub(str, pos, pos)
		if ch == "\\" then
			local next = string.sub(str, pos + 1, pos + 1)
			if next == '"' then
				table.insert(result, '"')
			elseif next == "\\" then
				table.insert(result, "\\")
			elseif next == "n" then
				table.insert(result, "\n")
			elseif next == "t" then
				table.insert(result, "\t")
			elseif next == "r" then
				table.insert(result, "\r")
			else
				-- unknown escape: keep both characters as-is
				table.insert(result, "\\")
				table.insert(result, next)
			end
			pos += 2
		elseif ch == '"' then
			return table.concat(result)
		else
			table.insert(result, ch)
			pos += 1
		end
	end

	return nil -- closing quote not found
end

function dotenv.parse(envText: string, quiet: boolean?, warnFn: ((string) -> ())?): { [string]: string }
	envText = string.gsub(envText, "\r\n", "\n") -- windows

	local warn: (string) -> () = if quiet then function(_message: string) end else (warnFn or print)

	local variables: { [string]: string } = {}

	local lines = string.split(envText, "\n")
	local i = 1

	while i <= #lines do
		local line = lines[i]
		i += 1

		-- skip empty lines and comments
		if line == "" or string.sub(line, 1, 1) == "#" then
			continue
		end

		-- handle export for shell compatibility
		line = string.gsub(line, "^export%s+", "")

		local varName, varValue = string.match(line, "^(.-)=(.*)$")

		-- error on lines that don't match KEY=VALUE format
		if not varName or not varValue then
			error(`Line doesn't match KEY=VALUE format:\n{line}`)
		end

		-- empty var name (e.g. "=value")
		if varName == "" then
			error(`Empty variable name:\n{line}`)
		end

		-- spaces not allowed in var name
		local nameSpacePos = string.find(varName, "%s")
		if nameSpacePos then
			error(`Unexpected character " " in env:\n{line}\n{string.rep("-", nameSpacePos - 1)}^\n`)
		end

		-- check if var value is quoted (matching quote types only)
		local first = string.sub(varValue, 1, 1)
		local isDoubleQuoted = first == '"'
		local isSingleQuoted = first == "'"

		if isDoubleQuoted then
			-- strip the opening quote and accumulate lines until the closing quote is found
			local accumulated = string.sub(varValue, 2)

			while true do
				local parsed = parseDoubleQuotedValue(accumulated)
				if parsed then
					varValue = processVariables(variables, parsed)
					break
				end
				if i > #lines then
					error(`Unclosed double quote starting at:\n{line}`)
				end
				accumulated = accumulated .. "\n" .. lines[i]
				i += 1
			end
		elseif isSingleQuoted then
			local closePos = string.find(varValue, "'", 2, true)
			if not closePos then
				error(`Unclosed quote in: {line}`)
			end
			varValue = string.sub(varValue, 2, closePos - 1)
			-- variables not processed if single quoted
			if not quiet and string.match(varValue, "%${(.-)}") then
				warn(`[DOTENV WARN] Variables not processed, wrap in double quotes (") to fix:\n              {line}`)
			end
		else
			-- strip inline comments (e.g. KEY=value # comment)
			varValue = string.gsub(varValue, "%s+#.*$", "")

			-- trim leading/trailing whitespace before validation (unquoted only)
			varValue = string.gsub(varValue, "^%s+", "")
			varValue = string.gsub(varValue, "%s+$", "")

			-- spaces not allowed in unquoted var value
			local valueSpacePos = string.find(varValue, "%s")
			if valueSpacePos then
				local charsUntilSpace = string.len(varName) + 1 + valueSpacePos
				error(`Unexpected character " " in env:\n{line}\n{string.rep("-", charsUntilSpace - 1)}^\n`)
			end

			-- variables not processed if not quoted
			if not quiet and string.match(varValue, "%${(.-)}") then
				warn(`[DOTENV WARN] Variables not processed, wrap in double quotes (") to fix:\n              {line}`)
			end
		end

		variables[varName] = varValue
	end

	return variables
end

function dotenv.config(
	targetPath: (string | { string })?,
	override: boolean?,
	quiet: boolean?,
	warnFn: ((string) -> ())?
): { [string]: string }?
	if targetPath == nil then
		targetPath = path.format(path.resolve(process.cwd(), ".env"))
	end

	local warn: (string) -> () = if quiet then function(_message: string) end else (warnFn or print)

	-- normalise to a list so both cases share the same loop
	local candidates: { string } = if type(targetPath) == "table" then targetPath else { targetPath :: string }

	for _, candidate in candidates do
		if fs.exists(candidate) then
			local parsed = dotenv.parse(fs.readFileToString(candidate), quiet, warnFn)
			for key, value in parsed do
				if override or not process.env[key] then
					process.env[key] = value
				end
			end
			return parsed
		end
	end

	warn(`[DOTENV WARN] No .env file found (searched: {table.concat(candidates, ", ")})`)
	return nil
end

return table.freeze(dotenv)
