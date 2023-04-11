---
title: "Lorem Ipsum Platform Dolor Sit Amet Profile for TPM 2.0"
version: 0.1
revision: 196
date-english: August 11, 2022
date: 8/11/2022
year: 2022
type: SPECIFICATION
status: DRAFT
...

---

# Disclaimers, Notices, and License Terms

THIS SPECIFICATION IS PROVIDED “AS IS” WITH NO WARRANTIES WHATSOEVER, INCLUDING
ANY WARRANTY OF MERCHANTABILITY, NONINFRINGEMENT, FITNESS FOR ANY PARTICULAR
PURPOSE, OR ANY WARRANTY OTHERWISE ARISING OUT OF ANY PROPOSAL, SPECIFICATION OR
SAMPLE.

Without limitation, TCG disclaims all liability, including liability for
infringement of any proprietary rights, relating to use of information in this
specification and to the implementation of this specification, and TCG disclaims
all liability for cost of procurement of substitute goods or services, lost
profits, loss of use, loss of data or any incidental, consequential, direct,
indirect, or special damages, whether under contract, tort, warranty or
otherwise, arising in any way out of use or reliance upon this specification or
any information herein. This document is copyrighted by Trusted Computing Group
(TCG), and no license, express or implied, is granted herein other than as
follows: You may not copy or reproduce the document or distribute it to others
without written permission from TCG, except that you may freely do so for the
purposes of (a) examining or implementing TCG specifications or (b) developing,
testing, or promoting information technology standards and best practices, so long
as you distribute the document with these disclaimers, notices, and license terms.
Contact the Trusted Computing Group at www.trustedcomputinggroup.org for
information on specification licensing through membership agreements. Any marks
and brands contained herein are the property of their respective owners.

---

# Change History

| **Revision** | **Date**   | **Description** |
| ------------ | ---------- | --------------- |
| 0.2/17       | 2022/08/10 | Initial draft   |
| 0.2/18       | 2022/08/10 | Add page breaks |

---

\tableofcontents

\listoftables

\listoffigures

---

# Introduction

Draft specification, with a list of tables and a list of figures.

> Informative!

> Informative text 2: here is a block of
> informative text.

## Details

Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor
incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis
nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu
fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in
culpa qui officia deserunt mollit anim id est laborum.

## Figures

### Computer

![a computer](computer.jpg){#fig:computer}

## Tables

### Mandatory Algorithms

Table: List of Mandatory Algorithms

| **Algorithm ID** | **M/R/O/D** | **Comments**                                  |
| ---------------- | ----------- | --------------------------------------------- |
| TPM_ALG_ECC      | M           | Support for 256 and 384-bit keys is required. |
| TPM_ALG_ECDSA    | M           |
| TPM_ALG_ECDH     | M           |
| TPM_ALG_ECDAA    | O           |
| TPM_ALG_RSA      | O           |
| TPM_ALG_RSAES    | O           |
| TPM_ALG_RSAPSS   | O           |
| TPM_ALG_RSAOAEP  | O           |
| TPM_ALG_AES      | M           |
| TPM_ALG_SHA256   | M           |
| TPM_ALG_SHA384   | M           |
| TPM_ALG_SHA512   | O           |
| TPM_ALG_HMAC     | M           |
| TPM_ALG_SHA3_256 | O           |
| TPM_ALG_SHA3_384 | O           |
| TPM_ALG_SHA3_512 | O           |
| TPM_ALG_NULL     | M           |

### Mandatory Curves

Table: List of Mandatory Curves

| **Curve Identifier** | **M/R/O/D** | **Comments** |
| -------------------- | ----------- | ------------ |
| TPM_ECC_NIST_P256    | M           |
| TPM_ECC_NIST_P384    | M           |

## Code

```c++
#include <string>

int main() {
    std::string result = "Trusted Computing Group";
    return 1;
}
```

## Another Couple Tables

Uncaptioned table:

| **Column 1** | **Column 2** | **Column 3** |
| ------------ | ------------ | ------------ |
| AAAAAAAA     | BBBBBBBB     | CCCCCCCC     |

Table: Fantastic Table

| **Column 1** | **Column 2** | **Column 3** |
| ------------ | ------------ | ------------ |
| AAAAAAAA     | BBBBBBBB     | CCCCCCCC     |

> Table: Informative Table
>
> | **Column 1** | **Column 2** | **Column 3** |
> | ------------ | ------------ | ------------ |
> | AAAAAAAA     | BBBBBBBB     | CCCCCCCC     |
> | DDDDDDDD     | EEEEEEEE     | FFFFFFFF     |
>

# References

[1] Trusted Computing Group, "DICE Protection Environment," 2023. [Online].
    Available: https://trustedcomputinggroup.org.

[2] Trusted Computing Group, "DICE Certificate Profiles," 2020. [Online].
    Available: https://trustedcomputinggroup.org.

[3] Internet Engineering Task Force, "Cryptographic Message Syntax (CMS)," 2009. [Online].
    Avilable: https://www.ietf.org/rfc/rfc5652.txt

[4] Internet Engineering Task Force, "PKCS #10: Certification Request Syntax Specification Version 1.7," 2000. [Online].
    Avilable: https://www.ietf.org/rfc/rfc2986.txt


Trusted Computing Group, "DICE Protection Environment," 2023. [Online].
    Available: https://trustedcomputinggroup.org.

Trusted Computing Group, "DICE Certificate Profiles," 2020. [Online].
    Available: https://trustedcomputinggroup.org.

Internet Engineering Task Force, "Cryptographic Message Syntax (CMS)," 2009. [Online].
    Avilable: https://www.ietf.org/rfc/rfc5652.txt

Internet Engineering Task Force, "PKCS #10: Certification Request Syntax Specification Version 1.7," 2000. [Online].
    Avilable: https://www.ietf.org/rfc/rfc2986.txt

> 
> Trusted Computing Group, "DICE Protection Environment," 2023. [Online].
>     Available: https://trustedcomputinggroup.org.
> 
> Trusted Computing Group, "DICE Certificate Profiles," 2020. [Online].
>     Available: https://trustedcomputinggroup.org.
>
> Internet Engineering Task Force, "Cryptographic Message Syntax (CMS)," 2009. [Online].
>     Avilable: https://www.ietf.org/rfc/rfc5652.txt
>
> Internet Engineering Task Force, "PKCS #10: Certification Request Syntax Specification Version 1.7," 2000. [Online].
>     Avilable: https://www.ietf.org/rfc/rfc2986.txt
>
