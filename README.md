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
