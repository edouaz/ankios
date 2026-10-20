"""Run with python3 tests/test_mathjax.py on macOS (Command Line Tools suffice)."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "AnkiApp/AnkiApp"
# Exercise the actual document template rather than maintaining a second renderer.
template = (SOURCE / "CardWebView.swift").read_text().split('let document = """', 1)[1].split('"""', 1)[0]
with tempfile.TemporaryDirectory(prefix="ankios-mathjax-") as directory:
    directory = Path(directory)
    for dark in (False, True):
        for answer in (False, True):
            expressions = [r"\(x+1\)", r"\[\frac{1}{2}\]", r"\(\sqrt{2}\)",
                           r"\[\sum_{i=1}^{n}i\]", r"\[\begin{pmatrix}a&b\\c&d\end{pmatrix}\]",
                           # Anki's cloze_filter strips HTML inside math delimiters.
                           r"\(x=2\)" if answer else r"\(x=[...]\)",
                           r"\(\ce{H2O}\)", r"\[\coloneqq\]", r"\(\unknowncommand\)"]
            html = "".join(f'<div class="formula">{e}</div>' for e in expressions)
            html += '<span class="cloze">' + ("answer" if answer else "[...]") + '</span>'
            html += '<img id="media" src="test.svg"><img id="latex" src="latex-test.svg">'
            html += f'<script>window.expectedDark = {str(dark).lower()}; window.expectedAnswer = {str(answer).lower()}; window.templateRan = (window.templateRan || 0) + 1;</script>'
            document = template.replace('\\(colorScheme == .dark ? "nightMode" : "")', "nightMode" if dark else "")
            document = document.replace('\\(Int(templateIndex) + 1)', '2')
            document = document.replace('\\(colorScheme == .dark ? "dark" : "light")', 'dark' if dark else 'light')
            css = '.card { background-color: white; color: black; } .card2 { text-align: center; }'
            if answer:
                css += ' body.nightMode { background-color: rgb(24, 32, 40); color: rgb(240, 240, 240); }'
            document = document.replace('\\(css)', css)
            document = document.replace('\\(html)', html)
            assert '\\(css)' not in document and '\\(html)' not in document
            (directory / f'{dark}-{answer}.html').write_text(document)
    svg = '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12"><rect width="12" height="12"/></svg>'
    for name in ('test.svg', 'latex-test.svg'):
        (directory / name).write_text(svg)
    subprocess.run(['swiftc', '-module-cache-path', str(directory / 'cache'),
                    str(SOURCE / 'MediaSchemeHandler.swift'), str(ROOT / 'tests/main.swift'),
                    '-o', str(directory / 'test')], check=True, timeout=240)
    subprocess.run([str(directory / 'test'), str(SOURCE / 'CardAssets'), str(directory)], check=True, timeout=60)
