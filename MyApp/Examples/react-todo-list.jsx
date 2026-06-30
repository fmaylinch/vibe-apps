// @name To-dos (React)
// @type react
// @icon ⚛️

const { useState } = React;
const KEY = "todos";

function App() {
  const [todos, setTodos] = useState(HostStorage.getItem(KEY) || []);
  const [text, setText] = useState("");

  function save(next) {
    setTodos(next);
    HostStorage.setItem(KEY, next);
  }

  function addTodo() {
    const trimmed = text.trim();
    if (!trimmed) return;
    save([...todos, { text: trimmed, done: false }]);
    setText("");
  }

  function toggle(i) {
    save(todos.map((t, j) => (j === i ? { ...t, done: !t.done } : t)));
  }

  function remove(i) {
    save(todos.filter((_, j) => j !== i));
  }

  return (
    <>
      <style>{`
        .row { display: flex; gap: 8px; margin-bottom: 12px; }
        input[type=text] { flex: 1; padding: 10px; font-size: 1rem; border: 1px solid #8884; border-radius: 10px; }
        button { padding: 10px 14px; font-size: 1rem; border: 0; border-radius: 10px; background: #007aff; color: #fff; }
        ul { list-style: none; padding: 0; margin: 0; }
        li { display: flex; align-items: center; gap: 10px; padding: 12px 4px; border-bottom: 1px solid #8883; }
        li.done span { text-decoration: line-through; opacity: 0.5; }
        li span { flex: 1; }
        .del { background: transparent; color: #ff3b30; padding: 4px 8px; }
      `}</style>
      <div>
        <h1>My Todos</h1>
        <div className="row">
          <input
            type="text"
            placeholder="Add a task..."
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter") addTodo(); }}
          />
          <button onClick={addTodo}>Add</button>
        </div>
        <ul>
          {todos.map((t, i) => (
            <li key={i} className={t.done ? "done" : ""}>
              <input type="checkbox" checked={t.done} onChange={() => toggle(i)} />
              <span>{t.text}</span>
              <button className="del" onClick={() => remove(i)}>Delete</button>
            </li>
          ))}
        </ul>
      </div>
    </>
  );
}

// @miniapp-storage
const STORAGE = {};
