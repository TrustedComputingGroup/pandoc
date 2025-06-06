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
  authors: (),
  abstract: [],
  doc,
) = {
  //
  // Font settings
  //
  // Normal text
  set text(
    font: "Manuale",
    size: 9pt,
  )
  // Math
  show math.equation: set text(
    font: "Inter",
    size: 9pt,
  )
  // Code
  show raw: set text(
    font: "Fira Code",
    size: 9pt,
  )
  // Headings
  set heading(numbering: "1.1")
  show heading: it => block()[
    #let size = 16pt - it.depth * 2pt
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

  set align(center)
  text(17pt, title)

  let count = authors.len()
  let ncols = calc.min(count, 3)
  grid(
    columns: (1fr,) * ncols,
    row-gutter: 24pt,
    ..authors.map(author => [
      #author.name \
      #author.affiliation \
      #link("mailto:" + author.email)
    ]),
  )

  par(justify: false)[
    *Abstract* \
    #abstract
  ]

  set align(left)

  pagebreak()

  heading("Disclaimers, Notices, and License Terms", level: 1)

  heading("Copyright Licenses", level: 2)

  [
    Trusted Computing Group (TCG) grants to the user of the source code in this
    specification (the \"Source Code\") a worldwide, irrevocable, nonexclusive,
    royalty free, copyright license to reproduce, create derivative works,
    distribute, display and perform the Source Code and derivative works
    thereof, and to grant others the rights granted herein.

    The TCG grants to the user of the other parts of the specification (other
    than the Source Code) the rights to reproduce, distribute, display, and
    perform the specification solely for the purpose of developing products
    based on such documents.
  ]

  heading("Source Code Distribution Conditions", level: 2)

  [
    Redistributions of Source Code must retain the above copyright licenses,
    this list of conditions and the following disclaimers.

    Redistributions in binary form must reproduce the above copyright licenses,
    this list of conditions and the following disclaimers in the documentation
    and/or other materials provided with the distribution.
  ]

  heading("Disclaimers", level: 2)

  [
    THE COPYRIGHT LICENSES SET FORTH ABOVE DO NOT REPRESENT ANY FORM OF LICENSE
    OR WAIVER, EXPRESS OR IMPLIED, BY ESTOPPEL OR OTHERWISE, WITH RESPECT TO
    PATENT RIGHTS HELD BY TCG MEMBERS (OR OTHER THIRD PARTIES) THAT MAY BE
    NECESSARY TO IMPLEMENT THIS SPECIFICATION OR OTHERWISE. Contact TCG
    Administration #link("mailto:admin@trustedcomputinggroup.org") for information on
    specification licensing rights available through TCG membership agreements.

    THIS SPECIFICATION IS PROVIDED “AS IS” WITH NO EXPRESS OR IMPLIED WARRANTIES
    WHATSOEVER, INCLUDING ANY WARRANTY OF MERCHANTABILITY OR FITNESS FOR A
    PARTICULAR PURPOSE, ACCURACY, COMPLETENESS, OR NONINFRINGEMENT OF
    INTELLECTUAL PROPERTY RIGHTS, OR ANY WARRANTY OTHERWISE ARISING OUT OF ANY
    PROPOSAL, SPECIFICATION OR SAMPLE.

    Without limitation, TCG and its members and licensors disclaim all
    liability, including liability for infringement of any proprietary rights,
    relating to use of information in this specification and to the
    implementation of this specification, and TCG disclaims all liability for
    cost of procurement of substitute goods or services, lost profits, loss of
    use, loss of data or any incidental, consequential, direct, indirect, or
    special damages, whether under contract, tort, warranty or otherwise,
    arising in any way out of use or reliance upon this specification or any
    information herein.

    Any marks and brands contained herein are the property of their respective
    owners.
  ]

  pagebreak()


  heading("Document Style", level: 1)

  heading("Key Words", level: 2)

  [
    The key words "MUST," "MUST NOT," "REQUIRED," "SHALL," "SHALL NOT," "SHOULD,"
    "SHOULD NOT," "RECOMMENDED," "MAY," and "OPTIONAL" in this document's normative
    statements are to be interpreted as described in
    [RFC 2119: Key words for use in RFCs to Indicate Requirement Levels](https://www.ietf.org/rfc/rfc2119.txt).
  ]

  heading("Statement Type", level: 2)

  [
    Please note an important distinction between different sections of text
    throughout this document. There are two distinctive kinds of text: *informative
    comments* and *normative statements*. Because most of the text in this
    specification will be of the kind *normative statements*, the authors have
    informally defined it as the default and, as such, have specifically called out
    text of the kind *informative comment*. They have done this by flagging the
    beginning and end of each informative comment and highlighting its text in gray.
    This means that unless text is specifically marked as of the kind *informative
    comment*, it can be considered a *normative statement*.
  ]

  informative(
    [Reach out to #link("mailto:admin@trustedcomputinggroup.org") with any questions about this document.
    ],
    kind: "Example",
  )

  pagebreak()

  doc
}
