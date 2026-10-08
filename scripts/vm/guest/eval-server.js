// Prepended to the guest's init.js by `hs2vm install`: a loopback-only HTTP endpoint that
// evaluates the request body as JavaScript, for `hs2vm hs`.
//
// This stands in for hs.ipc/hs2: launchd refuses to let a normally-launched app register the
// undeclared Mach service net.tenshu.Hammerspoon-2.ipc ("failed activation ... Operation not
// permitted"); only Xcode/debugger launches get it. That applies on any Mac, not just in VMs.
globalThis.__hs2vmEvalServer = hs.httpserver.create()
    .setInterface("localhost")
    .setPort(7999)
    .setCallback(async (method, path, headers, body) => {
        const reply = (status, text) => ({ status, body: text, headers: { "Content-Type": "text/plain" } })
        try {
            let value = (0, eval)(body)
            if (value && typeof value.then === "function") value = await value
            if (typeof value === "string") return reply(200, value)
            if (value === undefined || value === null || typeof value !== "object") return reply(200, String(value))
            // Bridged Swift objects have no enumerable properties, so JSON shows them as "{}".
            const json = JSON.stringify(value)
            return reply(200, json === "{}" ? String(value) : json)
        } catch (e) {
            return reply(500, e && e.stack ? `${e}\n${e.stack}` : String(e))
        }
    })
    .start()
