// @name To-dos (React, simple)
// @type react
// @icon ✅

// Globals: React, db

const { useEffect, useState } = React;

function App() {
  const [items, setItems] = useState([]);
  const [text, setText] = useState("");

  async function loadItems() {
    setItems(await db.list());
  }

  useEffect(() => {
    loadItems();
  }, []);

  async function addItem(e) {
    e.preventDefault();
    const name = text.trim();
    if (!name) return;

    await db.create({ name, done: false });
    setText("");
    loadItems();
  }

  async function toggleItem(item) {
    await db.update(item.id, { done: !item.done });
    loadItems();
  }

  async function deleteItem(item) {
    await db.remove(item.id);
    loadItems();
  }

  return (
    <>
      <style>{`
        .container { padding: 16px; }
        form, li { display: flex; gap: 8px; }
        form { margin-bottom: 16px; }
        input[type=text] { flex: 1; padding: 8px; font-size: 1rem; }
        button { padding: 8px 12px; font-size: 1rem; }
        ul { list-style: none; padding: 0; }
        li { align-items: center; padding: 8px 0; }
        li span { flex: 1; }
        li.done span { opacity: 0.5; text-decoration: line-through; }
      `}</style>

      <div className="container">
        <h1>To-dos</h1>
        <form onSubmit={addItem}>
          <input
            type="text"
            value={text}
            placeholder="New item"
            onChange={(e) => setText(e.target.value)}
          />
          <button type="submit">Add</button>
        </form>

        <ul>
          {items.map((item) => (
            <li key={item.id} className={item.done ? "done" : ""}>
              <input
                type="checkbox"
                checked={item.done}
                onChange={() => toggleItem(item)}
              />
              <span>{item.name}</span>
              <button onClick={() => deleteItem(item)}>Delete</button>
            </li>
          ))}
        </ul>
      </div>
    </>
  );
}
