# Tarleaks ERP — Software Licence Agreement (Self-Hosted Edition)

Copyright © 2026 Tarleaks. All rights reserved.

> **DRAFT: pending review by Tarleaks' lawyer.** This text describes the
> terms the software enforces today. It is not yet the final licence
> agreement; the reviewed text will replace it. Questions in the meantime:
> info@tarleaks.com.

This repository contains **deployment files only** (configuration, scripts and
documentation). The Tarleaks ERP software itself is distributed exclusively as
**pre-built container images**. No source code is provided, and none is
licensed to you.

## 1. Grant

Subject to these terms and to a valid licence token issued by Tarleaks, you may:

1. pull the Tarleaks ERP container images and run them on hardware you control
   or rent;
2. use the software for your organisation's internal business purposes, within
   the plan, modules, user count and term stated in your licence token;
3. copy and modify the files in this repository (compose files, environment
   templates, scripts and examples) to run the software.

A trial licence grants the same rights for evaluation only, for the trial term.

## 2. Restrictions

You may not, and may not allow anyone else to:

1. reverse engineer, decompile, disassemble, or otherwise attempt to derive the
   source code, algorithms or data structures of the software, except to the
   extent applicable law expressly permits it despite this restriction;
2. modify, patch or adapt the binaries or container images, or remove,
   disable or circumvent the licence check, the daily check-in, the user limit
   or any other technical protection;
3. redistribute, sublicense, rent, lease, sell, or publish the container images
   or any part of them, or make the software available to third parties as a
   hosted service;
4. use one licence token on more than one installation at the same time;
5. use the software beyond the modules, user count or term of your licence.

## 3. Licence check-in

The software connects to `https://tarleaks.com` to activate and then about
**every six hours**, and **at least once a day**, to confirm the licence. The check-in sends only: the
licence identifier, an installation identifier, the software version, the CPU
type and the number of active users. **No business data, personal data or documents are
ever sent.**

If the installation cannot complete a check-in within the allowance stated in
your licence (by default 30 hours), the software stops serving until a
check-in succeeds. Allow outbound HTTPS (TCP 443) to `tarleaks.com`.

## 4. Your data

Your data stays on your infrastructure and belongs to you. You are responsible
for backups, security updates of the host, and compliance with the laws that
apply to the data you process.

## 5. Updates and support

Updates are published as new image versions. Support and updates are provided
according to your plan. Trials receive community support only.

## 6. Termination

This licence ends automatically when your licence token expires, is suspended
or revoked, or if you breach these terms. On termination you must stop using
the software. You may export your data before the end of the term.

## 7. Disclaimer and limitation of liability

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT, EXCEPT AS EXPRESSLY
AGREED IN A SEPARATE SIGNED CONTRACT. TO THE MAXIMUM EXTENT PERMITTED BY LAW,
TARLEAKS IS NOT LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL OR CONSEQUENTIAL
DAMAGES, OR FOR LOSS OF DATA OR PROFITS, ARISING FROM THE USE OF THE SOFTWARE.

## 8. Contact

Licensing and sales: info@tarleaks.com · https://tarleaks.com
