// HostStorage: a tiny synchronous key-value bridge for mini-apps.
//
// Reads its seed from `window.__INITIAL_DATA__` (set by the host immediately
// before this script). Reads are served from the in-memory copy; writes update
// that copy and post a fire-and-forget message to native, which persists them.
//
//   HostStorage.getItem(key)        -> any JSON value (object/array/number/string/bool) | null
//   HostStorage.setItem(key, value) -> persists any JSON value across launches
//   HostStorage.removeItem(key)
//   HostStorage.clear()
window.HostStorage = (function () {
    var data = window.__INITIAL_DATA__ || {};
    function send(msg) { window.webkit.messageHandlers.storage.postMessage(msg); }
    return {
        getItem: function (k) {
            return Object.prototype.hasOwnProperty.call(data, k) ? data[k] : null;
        },
        setItem: function (k, v) { data[k] = v; send({ op: "set", key: k, value: v }); },
        removeItem: function (k) { delete data[k]; send({ op: "remove", key: k }); },
        clear: function () { data = {}; send({ op: "clear" }); }
    };
})();
