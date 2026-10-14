#!/usr/bin/env python3
"""build-docs.py — the docs pages of windageengine.com (`web/`), from `Tools/docs-src/*.md`.

Every page wears the same chrome as the first one did by hand: the docs bar, the sidebar with the current
page marked, the crumb, "On this page" from the page's own sections, and the version — read from the
engine's `Engine.semanticVersion`, never typed. Also writes the changelog page from `CHANGELOG.md`, the
reference page from the public types in `Sources/WindageEngine`, and the search index.

The output is committed HTML, so the site still has no build step to *view*: open `web/index.html`. Run this
after changing a page's source, the changelog, the engine's public types or its mark. It also copies the mark
files from `Brand/` into `web/`, so the folder uploads as it is and nobody pastes the mark by hand.

Usage:  python3 Tools/build-docs.py
"""

import html
import json
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True

ENGINE = Path(__file__).resolve().parent.parent
WEB = ENGINE / "web"
SRC = ENGINE / "Tools" / "docs-src"
OUT = WEB / "docs"
MARKS = ["favicon.svg", "windage-engine.svg", "windage-engine-display.svg"]

# The sidebar: (section, [(slug, title)]). Order is reading order. Every slug has docs-src/<slug>.md.
NAV = [
    ("Start", [("start", "Get started"), ("sample", "The sample game"), ("first-game", "Your first game")]),
    ("The frame loop", [("game-loop", "GameLoop"), ("fixed-timestep", "Fixed timestep"),
                        ("running-hidden", "Running hidden"), ("camera", "Camera")]),
    ("Rendering", [("meshes", "Loading meshes"), ("materials", "Materials and textures"), ("shadows", "Shadows"),
                   ("lights", "Clustered lights"), ("sky", "Sky and environment"), ("tone-mapping", "Tone mapping"),
                   ("particles", "Particles"), ("instancing", "Many copies"), ("level-of-detail", "Level of detail"),
                   ("culling", "Culling"), ("hud", "The HUD")]),
    ("Characters", [("skeletons", "Skeletons and clips"), ("character-controller", "CharacterController"),
                    ("attachments", "Hanging things off joints")]),
    ("World", [("levels", "Levels and the editor"), ("audio", "Audio"), ("input", "Input and settings"),
               ("saving", "Saving")]),
    ("Your game's name", [("splash", "The splash"), ("mark", "The mark")]),
    ("Checking your game", [("walks", "Scripted walks"), ("frames", "Recorded frames")]),
]

def news():
    """The box under "On this page": the newest release's headline, from `CHANGELOG.md` — never typed, so it
    cannot fall behind the version beside it. None before the first release, and the box is left out."""
    text = (ENGINE / "CHANGELOG.md").read_text()
    m = re.search(r"^## \[(\d+\.\d+\.\d+)\][^\n]*\n+\*\*(.+?)\*\*", text, flags=re.M)
    if m is None:
        return None
    return (f"New in {m.group(1)}", m.group(2).rstrip("."), f"changelog.html#v{slugify(m.group(1))}")


def version():
    text = (ENGINE / "Sources/WindageEngine/Engine.swift").read_text()
    m = re.search(r"SemanticVersion\(major: (\d+), minor: (\d+), patch: (\d+)\)", text)
    return ".".join(m.groups())


# ---------- Markdown, just enough for these pages ----------

def slugify(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def inline(text):
    """`code`, **bold**, *em*, [text](href) — everything else escaped. Code spans are set aside first and put
    back last, so emphasis can wrap them (`**the `color` key**`)."""
    codes = []

    def hold(m):
        codes.append(f"<code>{html.escape(m.group(1))}</code>")
        return f"\x00{len(codes) - 1}\x00"
    t = _emphasis(re.sub(r"`([^`]+)`", hold, text))
    return re.sub(r"\x00(\d+)\x00", lambda m: codes[int(m.group(1))], t)


def _emphasis(text):
    t = html.escape(text, quote=False)
    t = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", lambda m: f'<a href="{m.group(2)}">{m.group(1)}</a>', t)
    t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)
    t = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", t)
    return t


SWIFT_KEYWORDS = r"\b(import|final|class|struct|enum|protocol|extension|func|var|let|init|return|if|else|guard|for|in|while|switch|case|default|static|private|public|nonisolated|self|Self|try|throws|await|async|some|any|nil|true|false|override|mutating|inout|where|defer|do|catch)\b"


def highlight(code, lang):
    """Comments and strings dimmed, keywords lighter — the homepage's code, in the docs' colors."""
    lines = []
    for line in code.split("\n"):
        esc = html.escape(line, quote=False)
        if lang in ("sh", "shell", "bash", "text", "log"):
            if line.lstrip().startswith("#") or lang == "log":
                esc = f'<span class="c">{esc}</span>'
            else:
                esc = re.sub(r"(&quot;|\")(.*?)(\1)", lambda m: f'<span class="p">{m.group(0)}</span>', esc)
            lines.append(esc)
            continue
        code_part, comment = esc, ""
        idx = _comment_start(esc)
        if idx is not None:
            code_part, comment = esc[:idx], f'<span class="c">{esc[idx:]}</span>'
        code_part = re.sub(r'"(?:[^"\\]|\\.)*"', lambda m: f'<span class="p">{m.group(0)}</span>', code_part)
        code_part = re.sub(SWIFT_KEYWORDS, r'<span class="k">\1</span>', code_part)
        lines.append(code_part + comment)
    return "\n".join(lines)


def _comment_start(line):
    in_str = False
    for i in range(len(line) - 1):
        if line[i] == '"' and (i == 0 or line[i - 1] != "\\"):
            in_str = not in_str
        if not in_str and line[i:i + 2] == "//":
            return i
    return None


def render(md):
    """Markdown body → (html, [(id, heading)] for "On this page")."""
    out, toc = [], []
    lines = md.split("\n")
    i = 0
    para = []

    def flush():
        if para:
            out.append(f"<p>{inline(' '.join(para))}</p>")
            para.clear()

    while i < len(lines):
        line = lines[i]
        s = line.strip()
        if s.startswith("```"):
            flush()
            lang = s[3:].strip() or "swift"
            body = []
            i += 1
            while i < len(lines) and not lines[i].strip().startswith("```"):
                body.append(lines[i])
                i += 1
            out.append(f'<pre class="code-{lang}">{highlight(chr(10).join(body), lang)}</pre>')
        elif s.startswith("<"):                       # raw HTML, as written
            flush()
            block = [line]
            while i + 1 < len(lines) and lines[i + 1].strip():
                i += 1
                block.append(lines[i])
            out.append("\n".join(block))
        elif s.startswith("## ") or s.startswith("### "):
            flush()
            level = 2 if s.startswith("## ") else 3
            text = s[level + 1:]
            m = re.search(r"\s*\{#([\w-]+)\}$", text)
            hid = m.group(1) if m else slugify(text)
            text = text[:m.start()] if m else text
            if level == 2:
                toc.append((hid, re.sub(r"`", "", text)))
            out.append(f'<h{level} id="{hid}">{inline(text)}</h{level}>')
        elif s.startswith("> "):
            flush()
            block = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                block.append(lines[i].strip()[1:].strip())
                i += 1
            i -= 1
            out.append(f'<div class="note"><p>{inline(" ".join(block))}</p></div>')
        elif s.startswith("![") :
            flush()
            m = re.match(r'!\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)', s)
            cap = f"<figcaption>{inline(m.group(3))}</figcaption>" if m.group(3) else ""
            out.append(f'<figure><img src="{m.group(2)}" alt="{html.escape(m.group(1))}">{cap}</figure>')
        elif re.match(r"^(- |\d+\. )", s):
            flush()
            ordered = bool(re.match(r"^\d+\. ", s))
            items = []
            while i < len(lines) and lines[i].strip():
                t = lines[i].strip()
                if re.match(r"^(- |\d+\. )", t):
                    items.append(re.sub(r"^(- |\d+\. )", "", t))
                else:
                    items[-1] += " " + t
                i += 1
            i -= 1
            tag = "ol" if ordered else "ul"
            out.append(f"<{tag}>" + "".join(f"<li>{inline(x)}</li>" for x in items) + f"</{tag}>")
        elif s.startswith("|"):
            flush()
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
                i += 1
            i -= 1
            head, body = rows[0], [r for r in rows[2:]]
            t = '<div class="table"><table><thead><tr>' + "".join(f"<th>{inline(c)}</th>" for c in head) + "</tr></thead><tbody>"
            t += "".join("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>" for r in body)
            out.append(t + "</tbody></table></div>")
        elif not s:
            flush()
        else:
            para.append(s)
        i += 1
    flush()
    return "\n".join(out), toc


def front_matter(text):
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    meta = dict(line.split(": ", 1) for line in m.group(1).split("\n") if ": " in line)
    return meta, text[m.end():]


# ---------- The page ----------

def nav_html(current):
    parts = []
    for section, pages in NAV:
        parts.append(f"<h2>{html.escape(section)}</h2>")
        for slug, title in pages:
            cur = ' aria-current="page"' if slug == current else ""
            parts.append(f'<a href="{slug}.html"{cur}>{html.escape(title)}</a>')
    return "".join(parts)


def section_of(slug):
    for section, pages in NAV:
        if any(s == slug for s, _ in pages):
            return section
    return None


def page(slug, title, description, body, toc, crumb, ver):
    toc_links = "".join(f'<a href="#{hid}">{html.escape(t)}</a>' for hid, t in toc)
    toc_html = f'<h2>On this page</h2>{toc_links}' if toc else ""
    if (latest := news()) is not None:
        news_title, news_text, news_href = latest
        toc_html += f'<a class="news" href="{news_href}"><b>{news_title}</b>{inline(news_text)}</a>'
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)} · Windage Engine</title>
  <meta name="description" content="{html.escape(description)}">
  <link rel="icon" href="../favicon.svg" type="image/svg+xml">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo:wdth,wght@62..125,400..800&family=Hanken+Grotesk:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap">
  <link rel="stylesheet" href="../site.css">
  <script src="search-index.js" defer></script>
  <script src="search.js" defer></script>
</head>
<body>

<header class="docs-bar">
  <a class="brand" href="../index.html"><img src="../windage-engine.svg" alt="">WINDAGE <small>ENGINE</small></a>
  <button class="search" type="button" id="docs-search"><span>Search the docs</span><kbd>⌘K</kbd></button>
  <ul><li><a href="start.html">Guides</a></li><li><a href="reference.html">Reference</a></li><li><a href="changelog.html">Changelog</a></li></ul>
  <span class="ver">v{ver}</span>
</header>

<div class="docs">
  <nav class="docs-nav" aria-label="Documentation">
    {nav_html(slug)}
  </nav>

  <main>
    <details class="docs-menu"><summary>Contents</summary><nav aria-label="Documentation">{nav_html(slug)}</nav></details>
    <p class="crumb">{html.escape(crumb)}</p>
    <h1>{html.escape(title)}</h1>
{body}
  </main>

  <aside class="docs-toc" aria-label="On this page">
    {toc_html}
  </aside>
</div>

</body>
</html>
"""


# ---------- Generated pages ----------

def changelog_md():
    text = (ENGINE / "CHANGELOG.md").read_text()
    text = text[text.index("## ["):]
    # Releases only. Unreleased is a working section of the file, not something a reader can install.
    text = re.sub(r"^## \[Unreleased\].*?(?=^## \[|\Z)", "", text, flags=re.M | re.S)
    if not text.strip():
        return "Nothing has been released yet. The first release will be 1.0.0.\n"
    # Each release a section: "## [1.0.0] — <date>" → "## 1.0.0 — <date> {#v1-0-0}"
    text = re.sub(r"^## \[(.+?)\](.*)$", lambda m: f"## {m.group(1)}{m.group(2)} {{#v{slugify(m.group(1))}}}",
                  text, flags=re.M)
    # Its own `### Added` style sub-headings stay; links to versions on GitHub would point nowhere yet.
    text = re.sub(r"^\[[^\]]+\]: .*$", "", text, flags=re.M)
    return text


# Which guide explains each public type. A type missing here is listed without a guide.
GUIDE = {
    "GameLoop": "game-loop", "FrameRenderer": "game-loop", "Engine": "first-game", "SemanticVersion": "saving",
    "FixedTimestep": "fixed-timestep", "FrameClock": "running-hidden", "Camera": "camera",
    "MeshLoader": "meshes", "MeshLoaderError": "meshes", "LoadedMesh": "meshes", "AssetOrientation": "meshes",
    "BoundingBox": "culling", "Frustum": "culling", "Volume": "attachments",
    "Material": "materials", "TextureSlot": "materials", "TextureSource": "materials", "TextureStore": "materials",
    "TextureStoreError": "materials", "ShaderLibrary": "first-game",
    "ShadowMap": "shadows", "ShadowCascades": "shadows", "ShadowAtlas": "shadows", "ShadowCubes": "shadows",
    "PunctualLight": "lights", "LightSet": "lights", "ClusteredLights": "lights", "ClusterGrid": "lights",
    "ProceduralSky": "sky", "EnvironmentMap": "sky", "ToneMapping": "tone-mapping",
    "ParticleRecipe": "particles", "ParticleSystem": "particles", "ParticleEmitter": "particles",
    "ParticleRenderer": "particles", "InstanceBatches": "instancing", "InstanceBuffer": "instancing",
    "MeshDetail": "level-of-detail", "HUDRenderer": "hud", "HUDRendererError": "hud", "FontAtlas": "hud",
    "FontAtlasError": "hud", "InterfaceColor": "hud", "FrameRendererError": "game-loop",
    "ShaderLibraryError": "first-game", "TextureOrigin": "materials",
    "Rig": "skeletons", "RigLoader": "skeletons", "RigLoaderError": "skeletons", "Skeleton": "skeletons",
    "SkeletonError": "skeletons", "SkeletonPose": "skeletons", "AnimationClip": "skeletons",
    "AnimationBinding": "skeletons", "AnimationPlayhead": "skeletons", "JointTrack": "skeletons",
    "JointTransform": "skeletons", "CharacterController": "character-controller",
    "MovementInput": "character-controller", "TransformHierarchy": "attachments", "SceneObject": "attachments",
    "Level": "levels", "LevelEditor": "levels", "AudioEngine": "audio", "InputState": "input",
    "InputBindings": "input", "KeyCode": "input", "PadBindings": "input", "PadButton": "input",
    "PlayerSettings": "input", "StickResponse": "input", "SaveStore": "saving",
    "SplashScreen": "splash", "EngineMark": "mark",
}


def reference_md():
    """Every public type, grouped by file, each with the first sentence of its doc comment."""
    entries = []
    for path in sorted((ENGINE / "Sources/WindageEngine").glob("*.swift")):
        src = path.read_text().split("\n")
        for n, line in enumerate(src):
            m = re.match(r"^public (?:nonisolated |final )*(struct|class|enum|protocol|actor) (\w+)", line)
            if not m:
                continue
            doc = []
            k = n - 1
            while k >= 0 and (src[k].strip().startswith("///") or src[k].strip().startswith("@")):
                if src[k].strip().startswith("///"):
                    doc.insert(0, src[k].strip()[3:].strip())
                k -= 1
            first = " ".join(doc)
            first = re.split(r"(?<=[.!?])\s", first, 1)[0] if first else ""
            first = re.sub(r"``([^`]+)``", r"`\1`", first)
            entries.append((m.group(2), m.group(1), path.stem, first))
    entries.sort(key=lambda e: e[0].lower())
    def guide(name):
        slug = GUIDE.get(name)
        title = next((t for _, pages in NAV for sl, t in pages if sl == slug), None)
        return f"[{title}]({slug}.html)" if slug and title else "—"
    rows = "\n".join(f"| `{name}` | {kind} | {desc or '—'} | {guide(name)} |" for name, kind, _, desc in entries)
    return ("Every public type in the `WindageEngine` module, with the first line of its documentation and the "
            "guide that explains it.\n\n"
            "## Types {#types}\n\n| Type | Kind | What it is | Guide |\n| --- | --- | --- | --- |\n" + rows + "\n")


def search_entries(slug, title, md):
    text = re.sub(r"```.*?```", " ", md, flags=re.S)
    text = re.sub(r"<[^>]+>|[#*`>|\[\]]", " ", text)
    text = re.sub(r"\(([^)]*\.html[^)]*)\)", " ", text)
    heads = re.findall(r"^##+ (.+?)(?:\s*\{#[\w-]+\})?$", md, flags=re.M)
    return {"slug": slug, "title": title, "section": section_of(slug) or "",
            "headings": heads, "text": re.sub(r"\s+", " ", text)[:4000]}


def main():
    for mark in MARKS:
        (WEB / mark).write_bytes((ENGINE / "Brand" / mark).read_bytes())
    ver = version()
    missing = [s for _, pages in NAV for s, _ in pages if not (SRC / f"{s}.md").exists()]
    if missing:
        print("missing sources:", ", ".join(missing))
    index = []
    for section, pages in NAV:
        for slug, nav_title in pages:
            src = SRC / f"{slug}.md"
            if not src.exists():
                continue
            meta, md = front_matter(src.read_text())
            md = md.replace("{{version}}", ver)
            if meta.get("format") == "html":        # written as HTML, as Get started was
                body = md
                toc = [(i, re.sub(r"<[^>]+>", "", t)) for i, t in re.findall(r'<h2 id="([^"]+)">(.*?)</h2>', md)]
            else:
                body, toc = render(md)
            title = meta.get("title", nav_title)
            (OUT / f"{slug}.html").write_text(page(slug, title, meta.get("description", ""), body, toc,
                                                   f"Docs / {section}", ver))
            index.append(search_entries(slug, title, md))
    for slug, title, description, md in [
        ("changelog", "Changelog", "Every release of Windage Engine, newest first.", changelog_md()),
        ("reference", "Reference", "Every public type in Windage Engine.", reference_md()),
    ]:
        body, toc = render(md)
        if slug == "changelog":
            toc = toc[:12]
        (OUT / f"{slug}.html").write_text(page(slug, title, description, body, toc, f"Docs / {title}", ver))
        index.append(search_entries(slug, title, md))
    (OUT / "search-index.js").write_text(
        "// Written by build-docs.py. A script rather than JSON so search works from a file:// page too.\n"
        "window.DOCS_INDEX = " + json.dumps(index, ensure_ascii=False) + ";\n")
    print(f"built {len(index)} pages at v{ver}")


if __name__ == "__main__":
    main()
