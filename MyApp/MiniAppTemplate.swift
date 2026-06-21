import Foundation

/// Starter source handed to brand-new mini-apps.
///
/// These are *fragments*, not full HTML documents: the host (`MiniAppDocument`)
/// wraps them in the standard scaffold — doctype, `<head>`, viewport meta, and
/// base CSS — so authors only write the interesting part. State persists via
/// the host's `HostStorage` bridge so it survives relaunch.
enum MiniAppTemplate {
    /// Plain HTML/CSS/JS Todo List. Just body markup, a `<style>` block, and a
    /// `<script>` — the document shell is added by the host.
    static let todoList = """
    <h1>My Todos</h1>
    <div class="row">
      <input id="field" type="text" placeholder="Add a task...">
      <button onclick="addTodo()">Add</button>
    </div>
    <ul id="list"></ul>

    <style>
      .row { display: flex; gap: 8px; margin-bottom: 12px; }
      input[type=text] { flex: 1; padding: 10px; font-size: 1rem; border: 1px solid #8884; border-radius: 10px; }
      button { padding: 10px 14px; font-size: 1rem; border: 0; border-radius: 10px; background: #007aff; color: #fff; }
      ul { list-style: none; padding: 0; margin: 0; }
      li { display: flex; align-items: center; gap: 10px; padding: 12px 4px; border-bottom: 1px solid #8883; }
      li.done span { text-decoration: line-through; opacity: 0.5; }
      li span { flex: 1; }
      .del { background: transparent; color: #ff3b30; padding: 4px 8px; }
    </style>

    <script>
      var KEY = "todos";
      var todos = JSON.parse(HostStorage.getItem(KEY) || "[]");

      function save() { HostStorage.setItem(KEY, JSON.stringify(todos)); }

      function render() {
        var list = document.getElementById("list");
        list.innerHTML = "";
        todos.forEach(function (t, i) {
          var li = document.createElement("li");
          if (t.done) li.className = "done";
          var box = document.createElement("input");
          box.type = "checkbox";
          box.checked = t.done;
          box.onchange = function () { todos[i].done = box.checked; save(); render(); };
          var label = document.createElement("span");
          label.textContent = t.text;
          var del = document.createElement("button");
          del.className = "del";
          del.textContent = "Delete";
          del.onclick = function () { todos.splice(i, 1); save(); render(); };
          li.appendChild(box);
          li.appendChild(label);
          li.appendChild(del);
          list.appendChild(li);
        });
      }

      function addTodo() {
        var field = document.getElementById("field");
        var text = field.value.trim();
        if (!text) return;
        todos.push({ text: text, done: false });
        field.value = "";
        save();
        render();
      }

      document.getElementById("field").addEventListener("keydown", function (e) {
        if (e.key === "Enter") addTodo();
      });

      render();
    </script>
    """

    /// React + JSX counter. Just an `App` component and a `<style>` block — the
    /// host hoists the styles into `<head>`, wraps the JSX in a Babel script,
    /// and auto-mounts `<App/>` (no `createRoot` boilerplate needed).
    static let reactCounter = """
    const { useState } = React;
    const KEY = "count";

    function App() {
      const [count, setCount] = useState(Number(HostStorage.getItem(KEY) || "0"));

      function update(next) {
        setCount(next);
        HostStorage.setItem(KEY, String(next));
      }

      return (
        <div style={{ textAlign: "center" }}>
          <h1>Count: {count}</h1>
          <button onClick={() => update(count + 1)}>+1</button>
          <button onClick={() => update(count - 1)}>-1</button>
          <button className="reset" onClick={() => update(0)}>Reset</button>
        </div>
      );
    }

    <style>
      h1 { font-size: 2.2rem; }
      button { padding: 12px 18px; margin: 4px; font-size: 1.1rem; border: 0; border-radius: 12px; background: #007aff; color: #fff; }
      .reset { background: #8884; color: inherit; }
    </style>
    """
}
