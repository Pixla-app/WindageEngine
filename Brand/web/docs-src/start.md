---
title: Get started
format: html
description: Add Windage Engine to a Swift package, run the sample game, play it by script and check it.
---
<p>Windage Engine is a Swift package. Add it, run the sample game that ships with it, then play that game by script and check it the way the engine checks itself.</p>
    <div class="pills"><span>macOS 26+</span><span>Swift 6.2</span><span>Metal 4 GPU</span></div>

    <ol class="steps">
      <li>
        <h2 id="add">Add the package</h2>
        <p>In your game's <code>Package.swift</code>:</p>
<pre>dependencies: [
    .package(url: <span class="p">"https://…/WindageEngine.git"</span>, from: <span class="p">"{{version}}"</span>)
]</pre>
      </li>
      <li>
        <h2 id="run">Run the sample</h2>
        <p>A complete small game — two levels, an editor, sound, a save — written against the public API only. It opens with the engine's splash; any key skips it and still does what it was pressed for.</p>
<pre>swift run WindageSample</pre>
        <figure><img src="../images/ruins-lintel.jpg" alt="The sample's ruins at eye height: a stone lintel on posts, stairs and warm lamps."><figcaption>The ruins at eye height, drawn by the sample.</figcaption></figure>
      </li>
      <li>
        <h2 id="script">Play it by script</h2>
        <p>Keys and seconds, pressed through the same path a keyboard uses. The log says where the feet ended each segment.</p>
<pre>WINDAGE_SAMPLE_LEVEL=1 \
WINDAGE_SAMPLE_WALK=<span class="p">"d:0.7 w:1.0 w:0.4 wait:1"</span> swift run WindageSample
<span class="c">WindageSample: walk 'w:1.0' → feet (4.20, 1.20, -0.00), highest 1.20, on the ground, eye 1.69 m up</span></pre>
      </li>
      <li>
        <h2 id="check">Check it</h2>
        <p>Tests, every recorded walk, and every recorded frame — the three checks the engine runs on itself before a change is called done.</p>
<pre>swift test
python3 Tools/walks.py
python3 Tools/frames.py</pre>
      </li>
    </ol>
