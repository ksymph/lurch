local socket = require("socket")
local lurch = {}
lurch.__index = lurch

local RESPONSE_CODE = {
	[200] = "OK",
	[404] = "Not Found",
	[403] = "Forbidden",
	[500] = "Internal Server Error"
}

local MIME = {
	html = "text/html",
	htm  = "text/html",
	css  = "text/css",
	js   = "application/javascript",
	json = "application/json",
	xml  = "application/xml",
	jpg  = "image/jpeg",
	jpeg = "image/jpeg",
	png  = "image/png",
	gif  = "image/gif",
	bmp  = "image/bmp",
	svg  = "image/svg+xml",
	txt  = "text/plain",
	pdf  = "application/pdf",
	zip  = "application/zip",
	mp3  = "audio/mpeg",
	mp4  = "video/mp4",
	wav  = "audio/wav",
	ogg  = "audio/ogg",
	ico  = "image/x-icon"
}

function lurch.read(path)
	local file, err = io.open(path, "r")
	if not file then return err, 404 end
	local content = file:read("*all")
	file:close()

	local filetype = MIME[path:match("^.+(%..+)$"):sub(2):lower()] or "application/octet-stream"

	return content, filetype
end

function lurch.parse(str, environment)
	local env = _G
	env.parse, env.read = lurch.parse, lurch.read
	for k,v in pairs(environment or {}) do env[k]=v end
	local code =
		"return function(_)" ..
			"local result = '' " ..
			"local function _(s) " ..
				"result = result .. tostring(s or '') " ..
			"end " ..
			"_[=[" .. str:
				gsub("[][]=[][]", ']=]_"%1"_[=['):
				gsub("<%%=", "]=]_("):
				gsub("<%%", "]=]_("):
				gsub("%%>", ")_[=["):
				gsub("<%?", "]=] "):
				gsub("%?>", " _[=[") ..
			"]=] " ..
		"return result end"

	local func = load(code, "template", "t", env)
	local compiled = func()
	return compiled()
end

function lurch.sanitize(str)
	return tostring(str or ""):gsub("[\">/<'&]", {
		["&"] = "&amp;",
		["<"] = "&lt;",
		[">"] = "&gt;",
		['"'] = "&quot;",
		["'"] = "&#39;",
		["/"] = "&#47;"
	})
end

function lurch:log(event)
	-- todo: logging
	print(event)
end

function lurch.new(settings)
	local self = setmetatable({}, lurch)
	settings = settings or {
		port = 80,
		backlog = 5,
		timeout = 5,
		routes = {}
	}
	self.routes = {}
	for id, val in pairs(settings) do
		self[id] = val
	end

	self.server = assert(socket.tcp())
	assert(self.server:bind("*", self.port))
	self.server:listen(self.backlog)

	self.clients = {}

	local ip, port = self.server:getsockname()
	print("server ready")
	print("listening on port " .. port .. "...")

	return self
end

local function newResponse()
	local response = {
		headers = {["Content-Type"] = "text/html"},
		body = "",
		code = 200,
		disabled = false,
		foo = "bar"
	}


	function response:send()
		if self.disabled then return end
		local response_raw = "HTTP/1.1 " .. self.code .. " " .. RESPONSE_CODE[self.code] .. "\n"

		self.headers["Content-Length"] = string.len(self.body or "")
		for header_name, header_value in pairs(self.headers) do
			response_raw = response_raw .. header_name .. ": " .. header_value .. "\n"
		end

		response_raw = response_raw .. "\n" .. self.body

		self.client:send(response_raw)
		--self.client:send("HTTP/1.1 " .. self.code .. " " .. RESPONSE_CODE[self.code] .. "\n\n" .. "HI")
		self.client:close()
		self.disabled = true
	end

	function response:error(code, details)
		if self.disabled then return end
		local error = {}
		error.code = code or 500
		error.body = "<h1>" .. error.code .. " " .. codes[error.code] .. "</h1>"
		if details then error.body = error.body .. "<p>" .. details .. "</p>" end
		print(error.code)

		self.headers["Connection"] = "close"
		self.headers["Cache-Control"] = "no-store"
		self:send(error)
	end

	function response:load(path, overwrite)
		content, filetype = lurch.read(path:gsub("^/", ""))
		self.body = overwrite and content or self.body .. content
		self.headers["Content-Type"] = filetype
	end

	function response:tmpload(path, overwrite)
		content = lurch.read(path:gsub("^/", ""))
		self.body = overwrite and lurch.parse(content) or self.body .. lurch.parse(content)
		self.headers["Content-Type"] = "text/html"
	end

	return response

end

local function parseRequest(req)
	local request = {raw = req, headers = {}, params = {}, path = ""}

	local lines = {}
	for line in req:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end

	request.method, request.path = lines[1]:match("^(%S+)%s+([^?%s]+)")

	local query_string = lines[1]:match("?(.+)%s") or ""
	for key, value in query_string:gmatch("([^&=?]+)=([^&=?]+)") do
		request.params[key] = value:gsub("%%([0-9a-fA-F][0-9a-fA-F])", function(hex)
			return string.char(tonumber(hex, 16))
		end)
	end

	local i = 2
	while lines[i] and lines[i] ~= "" do
		local header_name, header_value = lines[i]:match("^(%S+):%s*(.+)")
		if header_name and header_value then request.headers[name] = value end
		i = i + 1
	end

	request.body = table.concat(lines, "\n", i + 1)
	return request
end
--[[
function lurch:listen()
	local response = newResponse()
	response.client, err = self.server:accept()
	if err then return nil, nil, err end
	if response.client then
		local req_raw, err = response.client:receive()
		if err then return nil, nil, err end
		local request = parseRequest(req_raw)
		response.request = request
		return response, response.request
	end
end
--]]

function lurch:listen()
	local sockets_to_check = {self.server}
	for _, client in ipairs(self.clients) do
		table.insert(sockets_to_check, client)
	end

	local ready_sockets = socket.select(sockets_to_check, nil, self.timeout)

	for _, sock in ipairs(ready_sockets) do
		if sock == self.server then
			local client, err = self.server:accept()
			if client then
				client:settimeout(0) -- Make client socket non-blocking
				table.insert(self.clients, client) -- Add new client to the list
				print("New client connected!")
			else
				print("Accept error: " .. err)
			end
			return
		end
		-- An existing client is ready for reading
		local req_raw, err = sock:receive()
		if not req_raw then
			-- Client closed connection or there was an error
			if err == "closed" then
				print("Client disconnected")
			else
				print("Receive error: " .. err)
			end
			-- Remove the client from the list
			for i, client in ipairs(self.clients) do
				if client == sock then
					table.remove(self.clients, i)
					break
				end
			end
			sock:close() -- Close the socket connection
		else
			-- Create a response object for this client
			local response = newResponse()
			response.client = sock
			local request = parseRequest(req_raw)
			response.request = request

			-- Return the response and request to the caller for further processing
			return response, request
		end

	end
end

function lurch:addRoute(...)
	local route = {pattern = "", priority = 1, func = function() end}
	for _,val in ipairs({...}) do
		if type(val) == "string" then route.pattern = val
			elseif type(val) == "table" then route.pattern = val
			elseif type(val) == "number" then route.priority = val
			elseif type(val) == "function" then route.func = val
		end
	end
	table.insert(self.routes, route)
	table.sort(self.routes, function(a, b)
		return a.priority < b.priority
	end)
end

function lurch:route(response)
	local request_path = response.request.path
	local matches = {}
	local outputs = {}

	for _,route in ipairs(self.routes) do
		local patterns = type(route.pattern) == "table" and route.pattern or {route.pattern}
		for _,pattern in ipairs(patterns) do
			if string.match(request_path, pattern) then
				local output = route.func(response, request_path)
				if output then table.insert(outputs, output) end
			end
		end
	end

	if outputs[1] then return outputs end
end



return lurch
