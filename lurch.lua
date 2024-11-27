local socket = require("socket")
local lurch = {}
lurch.__index = lurch

function readFile(filename)
	local file, err = io.open(filename, "r")
	if not file then return err, 404 end
	local content = file:read("*all")
	file:close()
	return content
end

function lurch:log(event)
	print(event)
end

local route_metatable = {
	__newindex = function(routes, key, route_func)
		local priority = 5
		if type(key) == "string" then

			--routes[key] = route_func
		elseif type(key) == "table" then

		end
	end
}

function lurch.new(new_settings)
	local self = setmetatable({}, lurch)

	new_settings = new_settings or {}
	local default_settings = {
		port = 80,
		backlog = 5,
		timeout = 5,
		routes = {}
	}
	for id, val in pairs(default_settings) do
		self[id] = new_settings[id] or val
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

function newResponse()
	local response = {}

	response.headers = {}
	response.headers["Content-Type"] = "text/html"
	response.body = ""
	response.code = 200
	response.disabled = false

	local codes = {
		[200] = "OK",
		[404] = "Not Found",
		[403] = "Forbidden",
		[500] = "Internal Server Error"
	}

	function response:send(error)
		if self.disabled then return end
		local error = error or {}
		local code = error.code or self.code
		local response_firstline = "HTTP/1.1 " .. code .. " " .. codes[code]
		local response_headers = ""
		local response_body = error.body or self.body or ""

		self.headers["Content-Length"] = string.len(response_body)
		for key, val in pairs(self.headers) do
			response_headers = response_headers .. key .. ": " .. val .. "\n"
		end

		local response_raw = response_firstline .. "\n" .. response_headers .. "\n" .. response_body

		self.client:send(response_raw)
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

	function response:load(path)
		content, err_code = readFile(path:gsub("^/", ""))
		if err_code then response:error(err_code, "/" .. content) return else self.body = content end
		local file_extension = path:match("^.+(%..+)$"):sub(2)
		local mimes = {
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
		self.headers["Content-Type"] = mimes[file_extension:lower()] or "application/octet-stream"

	end

	return response
end

function parseRequest(req)
	local request = {raw = req, headers = {}, method, path, body}

	local lines = {}
	for line in req:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end

	request.method, request.path = lines[1]:match("^(%S+)%s+(%S+)")

	local i = 2
	while lines[i] and lines[i] ~= "" do
		local header_line = lines[i]
		local name, value = header_line:match("^(%S+):%s*(.+)")
		if name and value then
			request.headers[name] = value
		end
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
	-- Prepare a list of sockets to monitor for reading (server socket + active client sockets)
	local sockets_to_check = {self.server}
	for _, client in ipairs(self.clients) do
		table.insert(sockets_to_check, client)
	end

	local ready_sockets = socket.select(sockets_to_check, nil, self.timeout)

	-- Check if the server socket is ready (indicating a new client connection)
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



function lurch:route(response)
	local request_path = response.request.path
	local matches = {}

	for pattern, operation in pairs(self.routes) do
		if string.match(request_path, pattern) then
			local match = {pattern = pattern, func = operation}
			table.insert(matches, match)
		end
	end

	local match_outputs = {}
	for i, match in ipairs(matches) do
		local result = match.func(response, request_path)
		if result then match_outputs[match.pattern] = result end
	end

	if match_outputs[1] then return match_outputs else return end
end



return lurch
