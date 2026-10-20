# Vendored MathJax 3.2.2

Unmodified files from the official `mathjax@3.2.2` npm package:
https://registry.npmjs.org/mathjax/-/mathjax-3.2.2.tgz

Archive SHA-256: `1b9c0a1c44df864e915690558e72adb9cc5203360daefd385084ced3b6c64c09`.

Included from `es5/`: `tex-chtml.js`, `input/tex/extensions/`,
`output/chtml/fonts/woff-v2/`, and `a11y/assistive-mml.js`.
See LICENSE (Apache-2.0); upstream: https://github.com/mathjax/MathJax/tree/3.2.2.
No package manager or download is needed to run the app.

Version and configuration reference: Anki 26.05, commit
`e64c6b1aee3e8d668fb8bbe084beada8e070d985`:
- https://github.com/ankitects/anki/blob/26.05/yarn.lock
- https://github.com/ankitects/anki/blob/26.05/ts/mathjax/index.ts
- https://github.com/ankitects/anki/blob/26.05/ts/reviewer/index.ts

The adjacent configuration follows Anki's TeX settings. The MathJax context menu
is disabled; its optional speech/menu dependencies are not included. Assistive
MathML remains available for accessibility. All TeX extensions are included so
MathJax's autoload and `\require` resolve locally.
