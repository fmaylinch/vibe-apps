// @name Habit Tracker
// @type react
// @icon 🎯

// Globals: React, db

const { useState, useEffect, useCallback } = React;

const habits = db.collection("habits");

// ---- date helpers ---------------------------------------------------------

// Local date as "YYYY-MM-DD" (stable key for a given day)
function dayKey(d = new Date()) {
    return [
        d.getFullYear(),
        String(d.getMonth() + 1).padStart(2, "0"),
        String(d.getDate()).padStart(2, "0"),
    ].join("-");
}

// Whole days between a stored day-key and today
function daysBetween(key) {
    const today = new Date(); today.setHours(0, 0, 0, 0);
    const [y, m, d] = key.split("-").map(Number);
    const then = new Date(y, m - 1, d); then.setHours(0, 0, 0, 0);
    return Math.round((today - then) / 86400000);
}

// A history entry is "YYYY-MM-DD" or "YYYY-MM-DD C" (C = a custom mark char)
function entryDay(entry) {
    return entry.slice(0, 10);
}
function entryMark(entry) {
    const c = entry.slice(10).trim();
    return c ? c[0] : "x";
}

function lastDoneLabel(history) {
    if (!history || history.length === 0) return "-";
    const last = history.slice().sort().at(-1); // most recent day
    const diff = daysBetween(entryDay(last));
    if (diff === 0) return "today";
    if (diff === 1) return "1 day ago";
    return diff + " days ago";
}

// "-x---F-" for the last `days` days (oldest first); "-" = missed,
// otherwise the day's mark char ("x" by default, or a custom one)
function recentStrip(history, days = 7) {
    const marks = {};
    for (const e of history || []) marks[entryDay(e)] = entryMark(e);
    const today = new Date(); today.setHours(0, 0, 0, 0);
    let out = "";
    for (let i = days - 1; i >= 0; i--) {
        const d = new Date(today); d.setDate(today.getDate() - i);
        const key = dayKey(d);
        out += key in marks ? marks[key] : "-";
    }
    return out;
}

// ---- app ------------------------------------------------------------------

function App() {
    const [items, setItems] = useState([]);
    const [name, setName] = useState("");
    const [open, setOpen] = useState({});   // which habits have history expanded
    const [draft, setDraft] = useState({}); // editable history text per habit
    const [loading, setLoading] = useState(true);

    // Load every habit (sorted by name).
    // Filtering, sorting and counting happen natively, so only rows we show
    // cross the bridge.
    const load = useCallback(async () => {
        const rows = await habits.list({ orderBy: "name" });
        console.log("Loaded rows: ", rows.length);
        setItems(rows);
    }, []);

    // Reload on first mount.
    useEffect(() => {
        setLoading(true);
        load().finally(() => setLoading(false));
    }, [load]);

    async function add(e) {
        e.preventDefault();
        const trimmed = name.trim();
        if (!trimmed) return;
        await habits.create({ name: trimmed, history: [], color: "#3498db", createdAt: Date.now() });
        setName("");
        load();
    }

    async function toggleToday(h) {
        const today = dayKey();
        const history = h.history || [];
        const next = history.some((e) => entryDay(e) === today)
            ? history.filter((e) => entryDay(e) !== today) // un-check today
            : [...history, today];                          // mark done today
        await habits.update(h.id, { history: next });
        load();
    }

    async function setColor(h, color) {
        await habits.update(h.id, { color });
        load();
    }

    // Opening fills the textarea draft; saving parses + stores the edited days.
    async function toggleHistory(h) {
        if (open[h.id]) {
            const text = draft[h.id] ?? "";
            const days = [...new Set(
                text.split("\n").map((s) => s.trim()).filter(Boolean)
            )].sort();
            await habits.update(h.id, { history: days });
            setOpen((o) => ({ ...o, [h.id]: false }));
            load();
        } else {
            const text = (h.history || []).slice().sort().reverse().join("\n");
            setDraft((d) => ({ ...d, [h.id]: text }));
            setOpen((o) => ({ ...o, [h.id]: true }));
        }
    }

    async function remove(h) {
        await habits.remove(h.id);
        load();
    }

    const today = dayKey();

    return (
        <>
            <style>{`
.wrap { max-width: 480px; }
.row { display: flex; gap: 8px; margin-bottom: 12px; }
input[type=text] { flex: 1; padding: 10px; font-size: 1rem; border: 1px solid #8884; border-radius: 10px; }
button { padding: 7px 10px; font-size: 1rem; border: 0; border-radius: 10px; background: #007aff; color: #fff; }
.muted { opacity: 0.5; }
ul { list-style: none; padding: 0; margin: 0; }
li { padding: 5px 4px; border-bottom: 1px solid #8883; }
.habit { display: flex; align-items: center; gap: 8px; }
.name { flex: 1; font-weight: 500; cursor: pointer; user-select: none; }
.strip { font-family: monospace; font-size: 13px; opacity: 0.6; letter-spacing: 1px; }
.swatch { width: 28px; height: 28px; padding: 0; border: none; background: none; cursor: pointer; }
.ghost { background: #8882; color: inherit; }
.editor { margin: 6px 0 2px 26px; font-size: 13px; }
textarea { width: 100%; box-sizing: border-box; font-family: monospace; font-size: 16px; padding: 6px; border: 1px solid #8884; border-radius: 8px; }
.del { background: transparent; color: #ff3b30; padding: 4px 8px; margin-top: 8px; }
`}</style>
            <div className="wrap">
                <form className="row" onSubmit={add}>
                    <input
                        type="text"
                        placeholder="New habit..."
                        value={name}
                        onChange={(e) => setName(e.target.value)}
                    />
                    <button type="submit">Add</button>
                </form>
                {loading ? (
                    <p className="muted">Loading…</p>
                ) : items.length === 0 ? (
                    <p className="muted">No habits yet.</p>
                ) : (
                    <ul>
                        {items.map((h) => {
                            const history = h.history || [];
                            const doneToday = history.some((e) => entryDay(e) === today);
                            const isOpen = !!open[h.id];
                            return (
                                <li key={h.id}>
                                    <div className="habit">
                                        <input
                                            type="checkbox"
                                            checked={doneToday}
                                            onChange={() => toggleToday(h)}
                                        />
                                        <input
                                            type="color"
                                            className="swatch"
                                            value={h.color || "#3498db"}
                                            onChange={(e) => setColor(h, e.target.value)}
                                        />
                                        <span
                                            className="name"
                                            onClick={() => toggleToday(h)}
                                            style={{ color: h.color || "inherit" }}
                                        >
                      {h.name}
                    </span>
                                        <span className="strip" title={lastDoneLabel(history)}>
                      {recentStrip(history)}
                    </span>
                                        <button className="ghost" onClick={() => toggleHistory(h)}>
                                            {isOpen ? "save" : "edit"}
                                        </button>
                                    </div>
                                    {isOpen && (
                                        <div className="editor">
                      <textarea
                          value={draft[h.id] ?? ""}
                          onChange={(e) => setDraft((d) => ({ ...d, [h.id]: e.target.value }))}
                          placeholder={"One day per line with optional mark e.g. 2026-06-17 F"}
                          rows={Math.max(3, (draft[h.id] ?? "").split("\n").length)}
                      />
                                            <button className="del" onClick={() => remove(h)}>Delete habit</button>
                                        </div>
                                    )}
                                </li>
                            );
                        })}
                    </ul>
                )}
            </div>
        </>
    );
}
