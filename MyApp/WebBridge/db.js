// db: a firebase-like document/collection API for mini-apps.
//
// Unlike HostStorage (fire-and-forget), every db call returns a Promise that
// resolves only after native has performed the operation and persisted it
// (and rejects on error). Each call carries a `reqId`; native settles the
// matching pending Promise via `window.__settleDb`.
//
//   const todos = db.collection("todos");   // a named collection
//   await todos.list();                       // -> [{ id, ... }, ...]
//   await todos.get(id);                       // -> { id, ... } | null
//   await todos.create({ text });              // -> created doc (with generated id)
//   await todos.update(id, { done: true });    // -> updated doc (rejects if id missing)
//   await todos.remove(id);                     // -> null (idempotent)
//
// `db` itself is a default collection, so `db.list()` / `db.create(...)` work
// directly without naming a collection.
window.db = (function () {
    var pending = {};
    var nextReq = 1;

    function call(collection, op, payload) {
        return new Promise(function (resolve, reject) {
            var id = "r" + (nextReq++);
            pending[id] = { resolve: resolve, reject: reject };
            window.webkit.messageHandlers.db.postMessage({
                reqId: id, collection: collection, op: op, payload: payload || {}
            });
        });
    }

    // Native calls this to settle a pending request.
    window.__settleDb = function (reqId, ok, result) {
        var p = pending[reqId];
        if (!p) return;
        delete pending[reqId];
        if (ok) p.resolve(result);
        else p.reject(new Error(result || "db error"));
    };

    function makeCollection(name) {
        return {
            list:   function ()         { return call(name, "list"); },
            get:    function (id)        { return call(name, "get",    { id: id }); },
            create: function (doc)       { return call(name, "create", { doc: doc }); },
            update: function (id, patch) { return call(name, "update", { id: id, patch: patch }); },
            remove: function (id)        { return call(name, "remove", { id: id }); }
        };
    }

    var root = makeCollection("default");   // enables flat db.list() / db.create()
    root.collection = function (name) { return makeCollection(name); };
    return root;
})();
