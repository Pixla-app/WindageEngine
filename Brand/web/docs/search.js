// Docs search: ⌘K (or the box) opens a field; titles, headings and text from search-index.js, which
// build-docs.py writes. No server, no library — the docs are a few dozen pages.
(function () {
  const index = window.DOCS_INDEX || [];
  const dialog = document.createElement("dialog");
  dialog.className = "search-dialog";
  dialog.innerHTML = '<input type="search" placeholder="Search the docs" aria-label="Search the docs"><ul></ul>';
  document.body.appendChild(dialog);
  const input = dialog.querySelector("input"), list = dialog.querySelector("ul");

  function score(entry, words) {
    let s = 0;
    for (const w of words) {
      const t = entry.title.toLowerCase(), h = entry.headings.join(" ").toLowerCase(), x = entry.text.toLowerCase();
      if (t.includes(w)) s += 10; else if (h.includes(w)) s += 4; else if (x.includes(w)) s += 1; else return 0;
    }
    return s;
  }
  function show() {
    const words = input.value.toLowerCase().split(/\s+/).filter(Boolean);
    const hits = words.length ? index.map(e => [score(e, words), e]).filter(([s]) => s > 0)
      .sort((a, b) => b[0] - a[0]).slice(0, 12).map(([, e]) => e) : index.slice(0, 12);
    list.innerHTML = hits.map(e => `<li><a href="${e.slug}.html"><b>${e.title}</b><span>${e.section}</span></a></li>`).join("")
      || "<li class=\"none\">Nothing matches.</li>";
  }
  function open() { show(); dialog.showModal(); input.focus(); input.select(); }
  document.getElementById("docs-search")?.addEventListener("click", open);
  document.addEventListener("keydown", e => {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") { e.preventDefault(); open(); }
  });
  input.addEventListener("input", show);
  input.addEventListener("keydown", e => {
    if (e.key === "Enter") { const a = list.querySelector("a"); if (a) location.href = a.href; }
  });
  dialog.addEventListener("click", e => { if (e.target === dialog) dialog.close(); });
})();
