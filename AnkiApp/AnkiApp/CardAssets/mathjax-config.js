// Based on Anki 26.05 ts/mathjax/index.ts (AGPL-3.0-or-later).
// Copyright: Ankitects Pty Ltd and contributors
window.MathJax = {
    tex: {
        inlineMath: [["\\(", "\\)"]],
        displayMath: [["\\[", "\\]"]],
        processEscapes: false,
        processEnvironments: false,
        processRefs: false,
        packages: { "[+]": ["noerrors", "mathtools"], "[-]": ["textmacros"] }
    },
    loader: {
        load: ["[tex]/noerrors", "[tex]/mathtools"],
        paths: { mathjax: "anki-assets:///mathjax" }
    },
    // Keep fonts and autoloaded TeX extensions local, including offline.
    chtml: { fontURL: "anki-assets:///mathjax/output/chtml/fonts/woff-v2" },
    options: { enableMenu: false },
    startup: { typeset: false }
};
