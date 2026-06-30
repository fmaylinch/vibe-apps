// Routes console.* output, uncaught errors, and unhandled promise rejections to
// the host (via the "log" message handler) so they can be shown in a debug
// console. Injected at document start, before any page or runtime script, so it
// also captures React/Babel failures.
(function () {
    function post(level, args) {
        try {
            var parts = Array.prototype.map.call(args, function (a) {
                if (a instanceof Error) return (a.stack || (a.name + ": " + a.message));
                if (typeof a === "object" && a !== null) {
                    try { return JSON.stringify(a); } catch (e) { return String(a); }
                }
                return String(a);
            });
            window.webkit.messageHandlers.log.postMessage({ level: level, message: parts.join(" ") });
        } catch (e) { /* never let logging break the app */ }
    }
    ["log", "info", "debug", "warn", "error"].forEach(function (name) {
        var original = console[name] ? console[name].bind(console) : null;
        console[name] = function () {
            post(name === "warn" ? "warning" : name, arguments);
            if (original) original.apply(console, arguments);
        };
    });
    window.addEventListener("error", function (e) {
        // Same-origin loads expose the real Error, including its stack.
        if (e.error && e.error.stack) { post("error", [e.error.stack]); return; }
        var where = e.filename ? (" (" + e.filename + ":" + e.lineno + ":" + e.colno + ")") : "";
        post("error", [(e.message || "Script error") + where]);
    });
    window.addEventListener("unhandledrejection", function (e) {
        var reason = e.reason && e.reason.message ? e.reason.message : e.reason;
        post("error", ["Unhandled promise rejection: " + reason]);
    });
})();
