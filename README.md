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
* [aasvg](https://github.com/martinthomson/aasvg) (for rendering ASCII art diagrams)

# How to Use

## How to Use with GitHub Specs

See the [Guide](guide.md) (In PDF form on the [Releases](https://github.com/TrustedComputingGroup/pandoc/releases) page).
A template repository is available at https://github.com/trustedcomputinggroup/specification-example.

## How to Run Locally

Your workflow may prefer local development and rendering. Due to the complexity of the various Pandoc
and LaTeX dependencies at work, it's easiest to use the Docker containers published at
https://github.com/trustedcomputinggroup/pandoc/pkgs/container/pandoc from this repository.

```sh
docker pull ghcr.io/trustedcomputinggroup/pandoc:latest

./docker_run --pdf=guide.pdf guide.tcg
```

Note that the `.tcg` extension is a convention and is not required.

## How to Build Locally

You may wish to send a PR to this repository, to add a feature or fix an issue with the tools.
To do so, it can be helpful to build and test the Docker container.

Another reason to build locally is if you are running on an architecture that is not built
and published to https://github.com/trustedcomputinggroup/pandoc/pkgs/container/pandoc
(e.g., arm64).

This project uses Docker [buildx](https://docs.docker.com/build/architecture#buildx)
to support cross-platform builds. Install it, then enable it using:

```sh
docker buildx install
```

To build the container:

```sh
docker build --tag working .

DOCKER_IMAGE=working:latest ./docker_run --pdf=guide.pdf guide.tcg
```

## How to customize the template

You may wish to provide your own LaTeX template, as well as other resources like images or style documents.
Suppose you have a directory `my_resource_dir` with the following contents:

- `img/cover_page_background.png`
- `reference_doc.docx`
- `reference_style.csl`
- `template.tex`

`template.tex` and any input files can refer to files in `resource_dir`, for example
by using `\includegraphics{extra/my_resource_dir/img/cover_page_background.png}`.

You can then run the following:

```sh
./docker_run \
  --extra_resource_dir path/to/my_resource_dir \
  --template extra/my_resource_dir/template.tex \
  --reference_doc extra/my_resource_dir/reference_doc.docx \
  --csl extra/my_resource_dir/reference_style.csl \
  --pdf output.pdf \
  input.tcg
```

## Rendering HTML (experimental)

HTML support is experimental. Known issues:

- `\listoffigures` and `\listoftables` are not supported, as they render without clickable links.
- Mermaid figures currently render as fixed-width.

To render a document to HTML:

```sh
./docker_run \
  --extra_resource_dir path/to/my_resource_dir \
  --template_html extra/my_resource_dir/html.template \
  --html_stylesheet extra/my_resource_dir/style1.css \
  --html_stylesheet extra/my_resource_dir/style2.css \
  --html output.html \
  input.tcg
```
