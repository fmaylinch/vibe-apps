// @name To-dos (React + db features)
// @type react
// @icon 🗄️

const { useState, useEffect, useCallback } = React;
const todos = db.collection("todos");
const PAGE_SIZE = 5;

// Each filter maps to a db `where` clause (undefined = no filter, i.e. all).
const WHERE = {
  all:    undefined,
  active: { done: false },
  done:   { done: true },
};

function App() {
  const [items, setItems] = useState([]);
  const [text, setText] = useState("");
  const [filter, setFilter] = useState("all");
  const [counts, setCounts] = useState({ all: 0, active: 0, done: 0 });
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);

  // Tab badges come straight from the db with count() — no need to load rows.
  const refreshCounts = useCallback(async () => {
    const [all, active, done] = await Promise.all([
      todos.count(),
      todos.count({ where: WHERE.active }),
      todos.count({ where: WHERE.done }),
    ]);
    setCounts({ all, active, done });
  }, []);

  // Load one page of the current filter, newest first. offset 0 replaces the
  // list; a larger offset appends it (the "Load more" path). Filtering, sorting
  // and paging all happen natively, so only this page crosses the bridge.
  const loadPage = useCallback(async (offset) => {
    const page = await todos.list({
      where: WHERE[filter],
      orderBy: "createdAt",
      desc: true,
      limit: PAGE_SIZE,
      offset,
    });
    setItems((prev) => (offset === 0 ? page : [...prev, ...page]));
    setHasMore(page.length === PAGE_SIZE);
  }, [filter]);

  // Reload from the top whenever the filter changes (and on first mount).
  useEffect(() => {
    setLoading(true);
    Promise.all([loadPage(0), refreshCounts()]).finally(() => setLoading(false));
  }, [filter, loadPage, refreshCounts]);

  // After any mutation, refresh the first page and the counts.
  const sync = useCallback(
    () => Promise.all([loadPage(0), refreshCounts()]),
    [loadPage, refreshCounts]
  );

  async function add(e) {
    e.preventDefault();
    const trimmed = text.trim();
    if (!trimmed) return;
    await todos.create({ text: trimmed, done: false, createdAt: Date.now() });
    setText("");
    sync();
  }

  async function toggle(t) {
    await todos.update(t.id, { done: !t.done });
    sync();
  }

  async function remove(t) {
    await todos.remove(t.id);
    sync();
  }

  return (
    <>
      <style>{`
        .row { display: flex; gap: 8px; margin-bottom: 12px; }
        input[type=text] { flex: 1; padding: 10px; font-size: 1rem; border: 1px solid #8884; border-radius: 10px; }
        button { padding: 10px 14px; font-size: 1rem; border: 0; border-radius: 10px; background: #007aff; color: #fff; }
        .muted { opacity: 0.5; }
        .tabs { display: flex; gap: 8px; margin-bottom: 12px; }
        .tab { background: #8882; color: inherit; padding: 8px 12px; }
        .tab.active { background: #007aff; color: #fff; }
        ul { list-style: none; padding: 0; margin: 0; }
        li { display: flex; align-items: center; gap: 10px; padding: 12px 4px; border-bottom: 1px solid #8883; }
        li.done span { text-decoration: line-through; opacity: 0.5; }
        li span { flex: 1; }
        .del { background: transparent; color: #ff3b30; padding: 4px 8px; }
        .more { width: 100%; margin-top: 12px; background: #8882; color: inherit; }
      `}</style>
      <div>
        <h1>My Todos</h1>
        <form className="row" onSubmit={add}>
          <input
            type="text"
            placeholder="Add a task..."
            value={text}
            onChange={(e) => setText(e.target.value)}
          />
          <button type="submit">Add</button>
        </form>

        <div className="tabs">
          {["all", "active", "done"].map((key) => (
            <button
              key={key}
              className={"tab" + (filter === key ? " active" : "")}
              onClick={() => setFilter(key)}
            >
              {key[0].toUpperCase() + key.slice(1)} ({counts[key]})
            </button>
          ))}
        </div>

        {loading ? (
          <p className="muted">Loading…</p>
        ) : items.length === 0 ? (
          <p className="muted">Nothing here.</p>
        ) : (
          <>
            <ul>
              {items.map((t) => (
                <li key={t.id} className={t.done ? "done" : ""}>
                  <input type="checkbox" checked={t.done} onChange={() => toggle(t)} />
                  <span>{t.text}</span>
                  <button className="del" onClick={() => remove(t)}>Delete</button>
                </li>
              ))}
            </ul>
            {hasMore && (
              <button className="more" onClick={() => loadPage(items.length)}>
                Load more
              </button>
            )}
          </>
        )}
      </div>
    </>
  );
}

// @miniapp-storage
const STORAGE = {};
