--!strict
-- Klien Open Cloud: jeda antar request + ulang otomatis (408/429/5xx/jaringan).
local net = require("@lune/net")
local serde = require("@lune/serde")
local task = require("@lune/task")

local Http = {}
Http.__index = Http

export type Http = typeof(setmetatable(
	{} :: {
		base: string,
		key: string,
		interval: number,
		lastAt: number,
		count: number,
		writes: number,
		log: (string) -> (),
	},
	Http
))

function Http.new(base: string, key: string, interval: number, log: ((string) -> ())?): Http
	return setmetatable({
		base = base,
		key = key,
		interval = interval,
		lastAt = 0,
		count = 0,
		writes = 0,
		log = log or print,
	}, Http)
end

function Http.enc(s: string): string
	return net.urlEncode(s)
end

-- Kembalikan (status, body terdekode). status 0 = gagal jaringan setelah semua ulangan.
function Http.request(self: Http, method: string, path: string, query: { [string]: string }?, body: any?): (number, any)
	local attempt = 0
	while true do
		local wait = self.interval - (os.clock() - self.lastAt)
		if wait > 0 then
			task.wait(wait)
		end
		self.lastAt = os.clock()
		self.count += 1
		if method ~= "GET" then
			self.writes += 1
		end
		local headers = { ["x-api-key"] = self.key, ["accept"] = "application/json" }
		local encoded: string? = nil
		if body ~= nil then
			headers["content-type"] = "application/json"
			encoded = serde.encode("json", body)
		end
		local ok, res = pcall(net.request, {
			url = self.base .. path,
			method = method :: any,
			query = query,
			headers = headers,
			body = encoded,
		})
		local status = if ok then res.statusCode else 0
		local retryable = (not ok) or status == 408 or status == 429 or status >= 500
		if retryable and attempt < 6 then
			attempt += 1
			local delay = 2 ^ attempt
			if ok and res.headers then
				local ra = tonumber(res.headers["retry-after"] or "")
				if ra and ra > 0 then
					delay = math.min(ra, 60)
				end
			end
			if self.interval > 0 then
				self.log(
					string.format(
						"   ... %s, ulang %d/6 dalam %ds",
						if ok then "HTTP " .. status else "jaringan gagal",
						attempt,
						delay
					)
				)
				task.wait(delay)
			end
		else
			if not ok then
				return 0, { message = tostring(res) }
			end
			local decoded: any = nil
			if res.body and res.body ~= "" then
				local okJ, v = pcall(serde.decode, "json" :: any, res.body)
				decoded = if okJ then v else { message = string.sub(res.body, 1, 200) }
			end
			return status, decoded
		end
	end
end

function Http.errText(status: number, body: any): string
	local msg = if type(body) == "table" then tostring(body.message or body.error or "") else ""
	return string.format("HTTP %d %s", status, msg)
end

return Http
