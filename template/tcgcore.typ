// Informative box
#let informative(
  content,
  kind: none,
) = context {
  let pre = if kind != none { kind } else { "Informative Text" }
  let post = none

  let meas = measure(content)
  if meas.height > 2in {
    post = "End of " + pre
    pre = "Start of " + pre
  }

  v(2pt)
  box(
    strong(pre) + v(-2pt) + content + if post != none { v(-2pt) + strong(post) },
    width: 100%,
    inset: 10pt,
    stroke: (
      top: .5pt,
      bottom: .5pt,
    ),
  )
}

#let conf(
  title: none,
  subtitle: none,
  doctype: none,
  status: none,
  version: none,
  date: none,
  year: none,
  doc,
) = context {
  //
  // Font settings
  //
  // Normal text
  set text(
    font: "Manuale",
    size: 10pt,
  )
  // Math
  show math.equation: set text(
    font: "Fira Math",
    size: 10pt,
  )
  // Code
  show raw: set text(
    font: "Fira Code",
    size: 10pt,
  )
  // Headings
  set heading(numbering: "1.1")
  show heading: it => block()[
    #let size = 20pt - it.level * 3pt
    #if size < 10pt { size = 10pt }
    #set align(center)
    #set text(
      font: "Inter",
      size: size,
      weight: "bold",
    )
    #it
  ]

  let horizontalrule = line(start: (25%, 0%), end: (75%, 0%))

  show terms: it => {
    it
      .children
      .map(child => [
        #strong[#child.term]
        #block(inset: (left: 1.5em, top: -0.4em))[#child.description]
      ])
      .join()
  }

  set table(
    inset: 6pt,
    stroke: 1pt,
  )

  show figure.where(kind: table): set figure.caption(position: bottom)

  show figure.where(kind: image): set figure.caption(position: bottom)

  //
  // Title page
  //
  set page(paper: "us-letter", margin: 1in)
  set align(left + top)

  image("tcg.png", width: 30%)

  set align(left + bottom)

  text(48pt, title, font: "Inter", weight: "extrabold")
  v(-30pt)

  if (subtitle != none) {
    text(32pt, subtitle, font: "Inter", weight: "medium")
    v(-20pt)
  }

  line(length: 100%, stroke: 2pt)
  v(-20pt)

  text(32pt, doctype, font: "Inter", weight: "light")
  v(-16pt)

  text(24pt, status, font: "Inter", weight: "extralight")
  v(-12pt)

  line(length: 100%, stroke: 2pt)

  v(-2pt)
  text(20pt, version, font: "Inter", weight: "light")
  v(-6pt)
  text(16pt, date, font: "Inter", weight: "light")
  v(-4pt)
  text(12pt, "Contact: " + link("mailto:admin@trustedcomputinggroup.org"), font: "Inter", weight: "extralight")

  //
  // Front matter
  //
  let foot = (
    line(length: 100%, stroke: 0.5pt)
      + grid(
        align: (left, center, right),
        columns: (1in, 5.5in, 1in),
        rows: 0.5in,
        sym.copyright + " " + year + " TCG",
        title + if subtitle != none { " " + subtitle },
        context counter(page).display(
          "1",
          both: false,
        ),
      )
  )
  set text(font: "Inter", weight: "light")
  set page(
    paper: "us-letter",
    margin: (bottom: 1in, rest: 0.5in),
    footer: foot,
  )

  set align(left + top)

  set text(font: "Manuale", size: 10pt)

  pagebreak()

  heading("Disclaimers, Notices, and License Terms", level: 1, numbering: none, outlined: false)

  [
    THIS SPECIFICATION IS PROVIDED “AS IS” WITH NO WARRANTIES WHATSOEVER, INCLUDING ANY WARRANTY OF MERCHANTABILITY, NONINFRINGEMENT, FITNESS FOR ANY PARTICULAR PURPOSE, OR ANY WARRANTY OTHERWISE ARISING OUT OF ANY PROPOSAL, SPECIFICATION OR SAMPLE.

    Without limitation, TCG disclaims all liability, including liability for infringement of any proprietary rights, relating to use of information in this specification and to the implementation of this specification, and TCG disclaims all liability for cost of procurement of substitute goods or services, lost profits, loss of use, loss of data or any incidental, consequential, direct, indirect, or special damages, whether under contract, tort, warranty or otherwise, arising in any way out of use or reliance upon this specification or any information herein.

    This document is copyrighted by Trusted Computing Group (TCG), and no license, express or implied, is granted herein other than as follows: You may not copy or reproduce the document or distribute it to others without written permission from TCG, except that you may freely do so for the purposes of (a) examining or implementing TCG specifications or (b) developing, testing, or promoting information technology standards and best practices, so long as you distribute the document with these disclaimers, notices, and license terms.
    Contact the Trusted Computing Group at www.trustedcomputinggroup.org for information on specification licensing through membership agreements.
    Any marks and brands contained herein are the property of their respective owners.
  ]

  heading("Statement Types", level: 1, numbering: none, outlined: false)

  [
    Please note an important distinction between different sections of text
    throughout this document. There are two distinctive kinds of text: *informative
    comments* and *normative statements*.

    Whether a statement is normative or informative is typically
    clear from context. In cases where the context does not
    provide sufficient clarity, the following rules apply:

    1. A statement with a capitalized RFC key word ("MUST," "MUST NOT," "REQUIRED," "SHALL," "SHALL NOT," "SHOULD,"
      "SHOULD NOT," "RECOMMENDED," "MAY," and "OPTIONAL") as in RFC 8174 is always normative.

    2. Text that is delimited by horizontal rules and labeled as an informative statement, note, example, etc. is always informative.
  ]

  informative(
    kind: "Example",
    [Reach out to #link("mailto:admin@trustedcomputinggroup.org") with any questions about this document.
    ],
  )

  pagebreak()

  outline()
  outline(title: "Figures", target: figure.where(kind: image))
  outline(title: "Tables", target: figure.where(kind: table))
  pagebreak()

  doc
}
