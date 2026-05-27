--!nonstrict
--!nolint BuiltinGlobalWrite
local test = require("@std/test")
local dotenv = require("../src")

test.suite("parse", function(suite)
	-- basic cases

	suite:case("simple unquoted value", function(asserts)
		local result = dotenv.parse("SIMPLE=hello")
		asserts.eq("hello", result["SIMPLE"])
	end)

	suite:case("empty value", function(asserts)
		local result = dotenv.parse("EMPTY=")
		asserts.eq("", result["EMPTY"])
	end)

	suite:case("equals sign inside value", function(asserts)
		local result = dotenv.parse("EQUALS_IN_VALUE=key=value=extra")
		asserts.eq("key=value=extra", result["EQUALS_IN_VALUE"])
	end)

	-- whitespace

	suite:case("trailing spaces are stripped from unquoted value", function(asserts)
		local result = dotenv.parse("TRAILING=hello   ")
		asserts.eq("hello", result["TRAILING"])
	end)

	suite:case("leading spaces are stripped from unquoted value", function(asserts)
		local result = dotenv.parse("LEADING=   hello")
		asserts.eq("hello", result["LEADING"])
	end)

	-- comments

	suite:case("skips comment lines", function(asserts)
		local result = dotenv.parse("# comment\nFOO=bar")
		asserts.eq(nil, result["# comment"])
		asserts.eq("bar", result["FOO"])
	end)

	suite:case("inline comment stripped", function(asserts)
		local result = dotenv.parse("INLINE=hello # comment")
		asserts.eq("hello", result["INLINE"])
	end)

	suite:case("url with hash not treated as comment", function(asserts)
		local result = dotenv.parse("URL=http://example.com/#fragment")
		-- no space before #, so it's eaten into the value but NOT a comment
		asserts.eq("http://example.com/#fragment", result["URL"])
	end)

	-- export keyword

	suite:case("export prefix is stripped", function(asserts)
		local result = dotenv.parse("export FOO=bar")
		asserts.eq("bar", result["FOO"])
	end)

	-- double-quoted values

	suite:case("double-quoted preserves spaces", function(asserts)
		local result = dotenv.parse('DOUBLE="hello world"')
		asserts.eq("hello world", result["DOUBLE"])
	end)

	suite:case("double-quoted empty string", function(asserts)
		local result = dotenv.parse('DOUBLE_EMPTY=""')
		asserts.eq("", result["DOUBLE_EMPTY"])
	end)

	suite:case("double-quoted preserves trailing spaces", function(asserts)
		local result = dotenv.parse('TRAILING="hello   "')
		asserts.eq("hello   ", result["TRAILING"])
	end)

	suite:case("double-quoted hash is not a comment", function(asserts)
		local result = dotenv.parse('HASH="hello#notacomment"')
		asserts.eq("hello#notacomment", result["HASH"])
	end)

	suite:case("double-quoted escape sequences", function(asserts)
		local result = dotenv.parse('ESC="tab:\\there\\nnewline"')
		asserts.eq("tab:\there\nnewline", result["ESC"])
	end)

	suite:case("double-quoted escaped quote", function(asserts)
		local result = dotenv.parse('Q="say \\"hi\\""')
		asserts.eq('say "hi"', result["Q"])
	end)

	suite:case("double-quoted multiline value", function(asserts)
		local result = dotenv.parse('MULTI="line one\nline two"')
		asserts.eq("line one\nline two", result["MULTI"])
	end)

	-- single-quoted values

	suite:case("single-quoted preserves spaces", function(asserts)
		local result = dotenv.parse("SINGLE='hello world'")
		asserts.eq("hello world", result["SINGLE"])
	end)

	suite:case("single-quoted does not interpolate variables", function(asserts)
		local result = dotenv.parse("BASE=world\nSINGLE='${BASE}'")
		asserts.eq("${BASE}", result["SINGLE"])
	end)

	suite:case("single-quoted hash is not a comment", function(asserts)
		local result = dotenv.parse("HASH='hello#notacomment'")
		asserts.eq("hello#notacomment", result["HASH"])
	end)

	-- variable interpolation

	suite:case("double-quoted interpolates earlier variable", function(asserts)
		local result = dotenv.parse('BASE=world\nGREET="hello ${BASE}"')
		asserts.eq("hello world", result["GREET"])
	end)

	suite:case("chained interpolation", function(asserts)
		local result = dotenv.parse('A=foo\nB="got ${A}"\nC="chained ${B}"')
		asserts.eq("chained got foo", result["C"])
	end)

	suite:case("forward reference is left as-is", function(asserts)
		-- iNTERP_DEFINED_LATER hasn't been parsed yet when FORWARD is parsed
		local result = dotenv.parse('FORWARD="uses ${LATER}"\nLATER=yep')
		asserts.eq("uses ${LATER}", result["FORWARD"])
	end)

	suite:case("unknown variable kept as literal", function(asserts)
		local result = dotenv.parse('VAR="hello ${DOES_NOT_EXIST} world"')
		asserts.eq("hello ${DOES_NOT_EXIST} world", result["VAR"])
	end)

	-- skipped lines

	suite:case("empty lines are skipped", function(asserts)
		local result = dotenv.parse("\n\nFOO=bar\n\n")
		asserts.eq("bar", result["FOO"])
	end)

	suite:case("windows CRLF line endings handled", function(asserts)
		local result = dotenv.parse("FOO=bar\r\nBAZ=qux")
		asserts.eq("bar", result["FOO"])
		asserts.eq("qux", result["BAZ"])
	end)

	-- error cases

	suite:case("errors on line without equals sign", function(asserts)
		local ok = pcall(function()
			dotenv.parse("NOEQUALSSIGN")
		end)
		asserts.eq(false, ok)
	end)

	suite:case("errors on empty variable name", function(asserts)
		local ok = pcall(function()
			dotenv.parse("=value")
		end)
		asserts.eq(false, ok)
	end)

	suite:case("errors on space in variable name", function(asserts)
		local ok = pcall(function()
			dotenv.parse("SPACE IN NAME=value")
		end)
		asserts.eq(false, ok)
	end)

	suite:case("errors on space in unquoted value", function(asserts)
		local ok = pcall(function()
			dotenv.parse("FOO=unquoted space")
		end)
		asserts.eq(false, ok)
	end)

	suite:case("errors on unclosed double quote", function(asserts)
		local ok = pcall(function()
			dotenv.parse('UNCLOSED="never closes')
		end)
		asserts.eq(false, ok)
	end)

	suite:case("errors on unclosed single quote", function(asserts)
		local ok = pcall(function()
			dotenv.parse("UNCLOSED='never closes")
		end)
		asserts.eq(false, ok)
	end)

	suite:case("warns when unquoted value contains variable syntax", function(asserts)
		local warnings = {}
		dotenv.parse("BASE=world\nUNQUOTED=${BASE}", false, function(msg)
			table.insert(warnings, msg)
		end)
		asserts.eq(1, #warnings)
		asserts.eq(true, string.find(warnings[1], "%[DOTENV WARN%]") ~= nil)
	end)

	suite:case("quiet=true suppresses warning for unquoted variable syntax", function(asserts)
		local warnings = {}
		dotenv.parse("BASE=world\nUNQUOTED=${BASE}", true, function(msg)
			table.insert(warnings, msg)
		end)
		asserts.eq(0, #warnings)
	end)

	suite:case("warns when single-quoted value contains variable syntax", function(asserts)
		local warnings = {}
		dotenv.parse("BASE=world\nSINGLE='${BASE}'", false, function(msg)
			table.insert(warnings, msg)
		end)
		asserts.eq(1, #warnings)
		asserts.eq(true, string.find(warnings[1], "%[DOTENV WARN%]") ~= nil)
	end)

	suite:case("quiet=true suppresses warning for single-quoted variable syntax", function(asserts)
		local warnings = {}
		dotenv.parse("BASE=world\nSINGLE='${BASE}'", true, function(msg)
			table.insert(warnings, msg)
		end)
		asserts.eq(0, #warnings)
	end)

	suite:case("multiple warnings emitted without quiet", function(asserts)
		local warnings = {}
		dotenv.parse("A=1\nB=${A}\nC='${A}'", false, function(msg)
			table.insert(warnings, msg)
		end)
		asserts.eq(2, #warnings)
	end)

	suite:case("quiet=true suppresses all warnings across multiple lines", function(asserts)
		local warnings = {}
		dotenv.parse("A=1\nB=${A}\nC='${A}'", true, function(msg)
			table.insert(warnings, msg)
		end)
		asserts.eq(0, #warnings)
	end)
end)

test.suite("config", function(suite)
	local process = require("@std/process")
	local fs = require("@std/fs")

	local tmpFile = "/tmp/dotenv_test_override.env"

	suite:beforeEach(function()
		fs.writeStringToFile(tmpFile, "TEST_KEY=from_file")
		process.env["TEST_KEY"] = nil
	end)

	suite:afterEach(function()
		if fs.exists(tmpFile) then
			fs.remove(tmpFile)
		end
		process.env["TEST_KEY"] = nil
	end)

	suite:case("override=true sets key in process.env", function(asserts)
		dotenv.config(tmpFile, true)
		asserts.eq("from_file", process.env["TEST_KEY"])
	end)

	suite:case("override=true overwrites existing key", function(asserts)
		process.env["TEST_KEY"] = "original"
		dotenv.config(tmpFile, true)
		asserts.eq("from_file", process.env["TEST_KEY"])
	end)

	suite:case("override=false sets key when not already in env", function(asserts)
		dotenv.config(tmpFile, false)
		asserts.eq("from_file", process.env["TEST_KEY"])
	end)

	suite:case("override=false preserves existing key", function(asserts)
		process.env["TEST_KEY"] = "original"
		dotenv.config(tmpFile, false)
		asserts.eq("original", process.env["TEST_KEY"])
	end)

	suite:case("config passes warnFn through to parse", function(asserts)
		fs.writeStringToFile(tmpFile, "BASE=world\nUNQUOTED=${BASE}")
		local warnings = {}
		dotenv.config(tmpFile, false, false, function(msg)
			table.insert(warnings, msg)
		end)
		asserts.eq(1, #warnings)
		asserts.eq(true, string.find(warnings[1], "%[DOTENV WARN%]") ~= nil)
	end)

	suite:case("config passes quiet=true through to parse, suppressing warnings", function(asserts)
		fs.writeStringToFile(tmpFile, "BASE=world\nUNQUOTED=${BASE}")
		local warnings = {}
		dotenv.config(tmpFile, false, true, function(msg)
			table.insert(warnings, msg)
		end)
		asserts.eq(0, #warnings)
	end)

	suite:case("config warnFn receives warnings for single-quoted variable syntax", function(asserts)
		fs.writeStringToFile(tmpFile, "BASE=world\nSINGLE='${BASE}'")
		local warnings = {}
		dotenv.config(tmpFile, false, false, function(msg)
			table.insert(warnings, msg)
		end)
		asserts.eq(1, #warnings)
	end)

	suite:case("config warnFn receives all warnings across multiple triggering lines", function(asserts)
		fs.writeStringToFile(tmpFile, "A=1\nB=${A}\nC='${A}'")
		local warnings = {}
		dotenv.config(tmpFile, false, false, function(msg)
			table.insert(warnings, msg)
		end)
		asserts.eq(2, #warnings)
	end)
end)
