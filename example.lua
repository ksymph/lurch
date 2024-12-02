local socket = require("socket")
local lurch = require("lurch")
local route = lurch.routing
--[[
TODO
logging
routes
templates
move send from response to server
url parameters



lurch
	methods:
		.new(options) // returns a lurch server object. options is optional table of options
		:listen() // returns request object, response object, error string. response object must be sent with response:send()
		:route(path) // returns path string with routing rules applied (.routes, .default properties)
	properties:
		.routes // table of routes to be used with :route()
		.port
response
	methods:
		:load(path) // loads file at specified path, setting body to file contents and header "Content-Type" appropriately
		:send() // send response back to the requester. required after lurch:listen()
		:error(code, error_details) // immediately sends error page to requester. :send() not required after an error
	properties:
		.body // response body text
		.headers // table of headers. key is header name, value is header value, e.g. .headers["Content-Type"] = "text/html"
		.code // response code integer, defaults to 200 (OK)
		.disabled // bool, set to true after :send() and :error(). prevents either from being called again
		.request // the request object that prompted the response
request
	methods:

	properties:
		.path // the requested path, e.g. "/index.html"
		.method // request method string, e.g. "GET" or "POST"
		.headers // table of headers. key is header name, value is header value, e.g. .headers["Content-Type"] = "text/html"
		.raw // unmodified full request string
		.body // request body, used in POST

--]]


local srv = lurch.new({port = 9090})
route:new{"^/api/", function(response, request_path)
	response:load(request_path .. ".lua")
	response.headers["Content-Type"] = "text/html"
	return "end"
end}
route:new{"^/index", 1, function(response, request_path)
	response:load("/example/index.html")
	print("hello world")
	return "end"
end}
-- srv.routes[".lua$"] = {0, 10, function(response) return end}
-- srv.routes["^/data/"] = function(response)
-- 	response:error(404)
-- 	return
-- end

while true do
	local response, request = srv:listen()
	if response then
		route(response)
		-- print(request.path)
		-- response:load("example/index.html")
		-- response.body = "hello world"
		-- response:load(path)
		-- response.body = "<h1>Hello world!</h1>"
		-- response.headers["Last-Modified"] = "Mon, 18 Jul 2016 02:36:04 GMT"


		response:send()

	end
end
