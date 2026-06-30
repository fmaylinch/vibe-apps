// @name To-dos (React + db)
// @type react
// @icon 🗄️

const { useState, useEffect } = React;
const todos = db.collection("todos");

function App() {
  const [items, setItems] = useState([]);
  const [text, setText] = useState("");
  const [loading, setLoading] = useState(true);

  async function refresh() {
    setItems(await todos.list());
  }

  useEffect(() => {
    refresh().finally(() => setLoading(false));
  }, []);

  async function add(e) {
    e.preventDefault();
    const trimmed = text.trim();
    if (!trimmed) return;
    await todos.create({ text: trimmed, done: false, createdAt: Date.now() });
    setText("");
    refresh();
  }

  async function toggle(t) {
    await todos.update(t.id, { done: !t.done });
    refresh();
  }

  async function remove(t) {
    await todos.remove(t.id);
    refresh();
  }

  return (
    <>
      <style>{`
        .row { display: flex; gap: 8px; margin-bottom: 12px; }
        input[type=text] { flex: 1; padding: 10px; font-size: 1rem; border: 1px solid #8884; border-radius: 10px; }
        button { padding: 10px 14px; font-size: 1rem; border: 0; border-radius: 10px; background: #007aff; color: #fff; }
        .muted { opacity: 0.5; }
        ul { list-style: none; padding: 0; margin: 0; }
        li { display: flex; align-items: center; gap: 10px; padding: 12px 4px; border-bottom: 1px solid #8883; }
        li.done span { text-decoration: line-through; opacity: 0.5; }
        li span { flex: 1; }
        .del { background: transparent; color: #ff3b30; padding: 4px 8px; }
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
        {loading ? (
          <p className="muted">Loading…</p>
        ) : (
          <ul>
            {items.map((t) => (
              <li key={t.id} className={t.done ? "done" : ""}>
                <input type="checkbox" checked={t.done} onChange={() => toggle(t)} />
                <span>{t.text}</span>
                <button className="del" onClick={() => remove(t)}>Delete</button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </>
  );
}

// @miniapp-storage
const STORAGE = {};
