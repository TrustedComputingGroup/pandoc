# TCG Pandoc Containers

These Docker containers contain the dependencies needed to build TCG
Markdown-based documents. The main anticipated consumer of these
containers is
[the Markdown action](https://github.com/trustedcomputinggroup/markdown),
but anyone can download and use the containers with Docker.

The interesting dependencies are:

* [Pandoc](https://pandoc.org)
* [LaTeX](https://www.latex-project.org) /
  [TexLive](https://www.tug.org/texlive/)
  (a dependency of Pandoc for PDF generation)
* [Eisvogel](https://github.com/Wandmalfarbe/pandoc-latex-template)
  (Pandoc/LaTeX template, with some TCG-specific modifications)
* [Mermaid](https://mermaid-js.github.io/mermaid/#/) /
  [mermaid-filter](https://github.com/raghur/mermaid-filter) (for rendering diagrams)
