# Math on cards

AnkiOS renders MathJax on both question and answer, including offline. The
engine, TeX extensions and fonts are bundled in the application. No card or
collection content is rewritten.

Use Anki's delimiters:

- Inline: `\(x^2 + \sqrt{2}\)`
- Display: `\[\frac{1}{2} + \sum_{i=1}^{n} i\]`
- Matrix: `\[\begin{pmatrix}a & b \\ c & d\end{pmatrix}\]`

The configuration matches Anki 26.05 (MathJax 3.2.2): standard TeX/AMS,
`noerrors`, `mathtools`, and locally autoloaded extensions such as `mhchem`.
Dollar delimiters (`$...$`, `$$...$$`) are not enabled. Environments must be
inside math delimiters. Cloze cards use the normal upstream Anki backend;
put the cloze inside the delimiters, e.g. `\(x={{c1::2}}\)`.

`[latex]...[/latex]`, `[$]...[/$]` and `[$$]...[/$$]` are different: Anki desktop
compiles these into image files. Generate the images on desktop and sync the
media before studying on iOS. AnkiOS displays those images through its normal
media handler; it does not compile LaTeX. Missing images require desktop
regeneration/media sync, not a MathJax change.

Template HTML, CSS and scripts remain in the page. The body has Anki's `card`
class plus the template-specific `card1`, `card2`, etc., and the content is inside `#qa`; dark mode adds `nightMode` to the body
and root. Each face gets a fresh document: startup/macros and pending rendering
from an earlier face cannot modify the next document. Configuration loads
before template scripts; typesetting waits for DOMContentLoaded and
`MathJax.startup.promise`.

## Developer smoke test

On macOS with Swift Command Line Tools:

```sh
python3 tests/test_mathjax.py
```

This compiles the production media/resource handler into a macOS WKWebView
harness and uses the actual HTML template extracted from CardWebView.swift.
It blocks HTTP(S) requests and checks inline/display math, fractions, roots,
sums, matrices, backend-shaped cloze output, `mhchem` autoload, `mathtools`,
`noerrors`, local fonts, template scripts, relative images and desktop LaTeX
images. It repeats for question/answer and light/dark, replacing a stale
navigation each time. It is not an iOS application or backend integration test.

The full iOS build also needs Xcode, generated protobuf files and
`Anki.xcframework` as described in the main README.
