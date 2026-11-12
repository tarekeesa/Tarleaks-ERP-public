# Tarleaks ERP Self-Hosted Licence

Version 1.1 · Licensor: **TARLEAKS FOR TRADING FZE LLC**, a free zone company licensed in the United Arab Emirates
("Tarleaks", "we", "us")

This licence is a binding agreement between Tarleaks and the organisation that installs or uses Tarleaks ERP on its own
infrastructure ("you"). By installing, starting or using the Software, or by entering a Licence Key, you accept this
licence electronically on behalf of your organisation and confirm that you are authorised to do so. If you do not
accept it, do not install or use the Software.

The Software is for **business use only**. You confirm that you are acquiring it for the purposes of your trade,
business, profession or public function, and not as a consumer.

If you have a signed agreement, order form or government contract with Tarleaks for the Software, that document takes
precedence where it differs from this licence.

## 1. Definitions

- **"Software"** means the Tarleaks ERP container images published by Tarleaks (for example from
  `registry.tarleaks.com`, or in an offline bundle), every update to them, and the deployment kit in this repository
  (installers, the `tarleaks` command, Docker Compose files, configuration templates, scripts and documentation).
- **"Licence Key"** means a licence key or trial key issued by Tarleaks. It states the plan, the apps, the number of
  users and the term you are entitled to.
- **"Installation"** means one running copy of the Software, identified by its installation identifier.
- **"Your Data"** means the data, including any personal data, that you or your users put into or process with the
  Software.
- **"Affiliate"** means an entity that controls, is controlled by, or is under common control with you, where
  "control" means owning more than 50 % of the voting rights or the power to direct its management.
- **"Applicable Data Protection Law"** means every data protection law that applies to Your Data, which may include
  the UAE Federal Decree-Law No. 45 of 2021 on the Protection of Personal Data, the Saudi Personal Data Protection Law,
  the Qatar, Bahrain, Oman and Kuwait data protection laws, the DIFC Data Protection Law, the ADGM Data Protection
  Regulations and any other law of the countries where you operate.

The Software is provided as pre-built binaries. No source code of the ERP is included, and none is licensed to you.

## 2. Licence grant

While you hold a valid Licence Key, and as long as you comply with this licence, Tarleaks grants you a non-exclusive,
non-transferable, non-sublicensable licence to:

1. download the container images and run them on hardware you own, rent or control (including a cloud account in your
   name), in any country where this is lawful;
2. use the Software for the internal business purposes of your organisation and its Affiliates, within the plan, apps,
   number of users and term stated in your Licence Key; and
3. copy and modify the deployment kit files (not the container images) as needed to install, operate, back up and
   update the Software.

Contractors and service providers may operate the Software on your behalf, for your internal purposes only, if you
remain responsible for their compliance with this licence.

**Trial keys.** A trial key grants the same rights for evaluation only, for the trial term stated in it, and not for
production use. One trial is available per organisation and e-mail address. When the trial ends the Installation locks
until a paid Licence Key is entered; your data is kept.

Tarleaks reserves all rights not expressly granted. The Software, its copyright, trademarks, know-how and all other
intellectual property rights in it remain the property of Tarleaks and its licensors. You acquire no ownership of the
Software.

## 3. What you may not do

You may not, and may not allow anyone else to:

1. reverse engineer, decompile, disassemble or otherwise try to obtain the source code, algorithms or data structures
   of the binaries, except to the extent applicable law expressly permits it despite this restriction;
2. modify, patch or adapt the binaries or container images, or remove, disable or work around the licence check, the
   check-in, the user limit or any other technical protection;
3. copy, distribute, publish, sell, rent, lease, lend or sublicense the container images or the offline bundle, or any
   part of them, to a third party;
4. provide the Software to third parties as a hosted, managed, outsourced or bureau service, or use it to process the
   data of organisations other than your own and your Affiliates, unless Tarleaks agrees to it in writing (for example
   under a Tarleaks partner agreement);
5. run one Licence Key on more than one Installation at a time (a cold standby or disaster-recovery copy that is not
   serving users is allowed), share a Licence Key outside your organisation, or use the Software beyond the apps, users
   or term of your Licence Key;
6. remove or alter any copyright, trademark, licence or other notice in the Software; or
7. use the Software, or knowledge of its internals obtained in breach of this section, to build a competing product.

## 4. Licence check-in

The Software contacts `tarleaks.com` over HTTPS to activate and then about every six hours to confirm the Licence Key.
If no check-in succeeds within the allowance stated in your Licence Key (by default 30 hours), the Installation stops
serving until a check-in succeeds; your data is not affected. A Licence Key with check-ins switched off (offline
licence) still needs one activation.

A check-in sends licence and installation information only: the identifiers, version, apps and user counts listed in
`docs/licensing.md` of this repository, together with the network address it connects from. It never sends business
records such as employees, payroll, invoices, customers, documents, user names or passwords.

**Verification.** On reasonable written notice, and not more than once in any twelve months, you will confirm in
writing the number of users and Installations you run. If you used more than your Licence Key allows, you will pay the
fees for the excess at the then-current price.

## 5. Your Data and data protection

1. **Ownership and location.** Your Data belongs to you. It stays on the infrastructure and in the country you choose.
   Tarleaks does not access it unless you give access for support.
2. **Your role.** For Your Data you are the controller (data owner). You are responsible for the lawful basis of the
   processing, notices to and the rights of your employees, customers and other data subjects, cross-border transfers
   you decide on, retention, backups, securing the host, and for complying with Applicable Data Protection Law and
   sector rules (for example labour, tax, health, banking or government data rules).
3. **Support access.** If you give Tarleaks access to an Installation or to Your Data for support, Tarleaks acts only
   on your documented instructions, keeps the data confidential, uses it only to provide that support, does not keep a
   copy after the support case ends unless you ask it to, and notifies you without undue delay if it becomes aware of a
   breach affecting that data. Where Applicable Data Protection Law requires a written data processing agreement, Tarleaks
   will sign its standard data processing agreement with you on request.
4. **Licence data.** Tarleaks processes the licence and contact information it holds about you (for example the name
   and e-mail address of the person who requested a key) under its privacy notice at https://tarleaks.com.
5. **Export.** Your Data stays in the database on your own server. You may export it at any time, including after the
   licence ends, for example with the `tarleaks backup` command or your own database tools.

## 6. Third-party components

The container images include open-source components. Each is licensed to you under its own licence, which governs that
component and takes precedence over this licence for it. A list of these components and their licences is available
on request and in `docs/` of this repository. Nothing in this licence limits a right that an open-source licence gives
you.

## 7. Updates and support

Updates are published as new image versions. Updates and support are provided according to your plan; trials receive
community support only. Tarleaks may change or withdraw features in future versions. Release candidates and preview
versions are for evaluation and are not covered by any support commitment.

## 8. Fees and taxes

1. Paid plans are invoiced as agreed when the Licence Key is issued. Fees are payable within 30 days of the invoice
   unless your order says otherwise, and are non-refundable except where your signed agreement or applicable law says
   otherwise.
2. Fees are exclusive of value added tax and any other taxes, duties or charges, which you will pay in addition where
   they apply.
3. If the law of your country requires you to withhold any tax from a payment to Tarleaks (for example withholding tax
   on payments to a non-resident), you will increase the payment so that Tarleaks receives the full amount it would have
   received without the withholding, unless your signed agreement provides otherwise. If you obtain a reduction under a
   double taxation agreement, you will give Tarleaks the official withholding certificate.
4. If an invoice remains unpaid 30 days after its due date, Tarleaks may, after written notice, suspend the Licence Key
   until it is paid.

## 9. Term and termination

This licence starts when you first install or use the Software and ends when your Licence Key expires or is revoked.
Tarleaks may suspend or revoke a Licence Key, or end this licence, if you breach it and do not cure the breach within
30 days of written notice, or at once for a breach of section 3 that cannot be cured, or if you become insolvent or
subject to sanctions described in section 12. You may end this licence at any time by uninstalling the Software; fees
already paid are not refunded unless your signed agreement or applicable law says otherwise. When the licence ends you
must stop using the Software, except to export Your Data as described in section 5. Sections 3, 5, 6, 8 (for
amounts due) and 10 to 15 survive termination.

## 10. Warranty

1. For paid plans, Tarleaks warrants that, for 90 days from the date a paid Licence Key is first issued, the Software
   will perform materially as described in its documentation. Your only remedy for a breach of this warranty is that
   Tarleaks will, at its option, correct the defect within a reasonable time or end the licence and refund the fees paid
   for the period after the defect was reported.
2. EXCEPT AS STATED IN SECTION 10.1, AND TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, THE SOFTWARE IS PROVIDED
   "AS IS" AND "AS AVAILABLE", AND TARLEAKS GIVES NO OTHER WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING ANY
   WARRANTY OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, NON-INFRINGEMENT, OR THAT THE SOFTWARE WILL BE
   ERROR-FREE OR UNINTERRUPTED, UNLESS A SIGNED AGREEMENT EXPRESSLY SAYS OTHERWISE.
3. The Software helps you prepare tax, payroll, labour, e-invoicing and other regulatory records and filings. You remain
   responsible for checking that its output and its configuration (for example rates, country packs and registrations)
   are correct for your organisation before you rely on, submit or pay anything, and for meeting your own legal
   deadlines.

## 11. Limitation of liability

TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW:

1. NEITHER PARTY IS LIABLE TO THE OTHER FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL OR PUNITIVE DAMAGES, OR FOR
   LOSS OF PROFITS, REVENUE, BUSINESS, GOODWILL OR DATA, HOWEVER CAUSED; AND
2. TARLEAKS'S TOTAL LIABILITY ARISING OUT OF OR RELATING TO THE SOFTWARE OR THIS LICENCE, WHETHER IN CONTRACT, TORT OR
   OTHERWISE, IS LIMITED TO THE FEES YOU PAID FOR THE SOFTWARE IN THE TWELVE MONTHS BEFORE THE EVENT THAT GAVE RISE TO
   THE CLAIM, OR ONE HUNDRED US DOLLARS (USD 100) IF YOU PAID NO FEES (FOR EXAMPLE DURING A TRIAL).

Section 11.1 does not limit your obligation to pay fees, your liability for a breach of section 3 or for infringing
Tarleaks's intellectual property. Nothing in this licence limits or excludes liability for fraud, gross negligence,
wilful misconduct, death or personal injury, or any other liability that cannot be limited or excluded under applicable
law. The parties agree that these limits reflect the allocation of risk in the fees and are a fundamental part of this
licence.

## 12. Compliance and sanctions

You will use the Software in compliance with applicable laws, including the export control and sanctions laws of the
United Arab Emirates, the United Nations, and any other country that applies to you. You confirm that you are not
listed on, or owned or controlled by a person listed on, a sanctions list that applies to Tarleaks, and you will not
use the Software, or allow it to be used, by any such person or in any country or for any purpose where that is
prohibited.

## 13. Force majeure

Neither party is liable for a delay or failure to perform (other than a payment obligation) caused by events beyond its
reasonable control, including natural disasters, epidemics, war, terrorism, government action, power or network
failures and failures of third-party hosting or registry providers, provided it takes reasonable steps to limit the
effect.

## 14. Governing law and disputes

1. This licence, and any non-contractual obligation arising out of or in connection with it, is governed by the laws of
   the Emirate of Dubai and, to the extent applicable there, the federal laws of the United Arab Emirates.
2. The parties will first try in good faith to settle any dispute by negotiation between senior representatives within
   30 days of a written notice describing it.
3. Any dispute that is not settled will be finally resolved by arbitration under the Arbitration Rules of the Dubai
   International Arbitration Centre (DIAC) in force at the time. The seat of arbitration is Dubai, United Arab Emirates;
   there is one arbitrator; the language is English. The award is final and binding and may be enforced in any court of
   competent jurisdiction, including under the New York Convention.
4. Nothing in this section prevents Tarleaks from seeking urgent interim or injunctive relief in any competent court to
   protect its intellectual property or to stop a breach of section 3, or from bringing a claim for unpaid fees before
   the competent courts of your place of business.
5. If you are a government entity whose law requires a different forum, your signed agreement with Tarleaks may set it.

## 15. General

1. This licence (together with any signed agreement or order form for the Software) is the entire agreement about the
   Software and replaces any earlier understanding about it.
2. You may not assign or transfer this licence without Tarleaks's written consent. Tarleaks may assign it to an
   Affiliate or to a successor of its business, on notice to you.
3. If any provision is held invalid or unenforceable, it is enforced to the maximum extent permitted and the rest
   remains in effect. A failure or delay to enforce a provision is not a waiver.
4. Notices to Tarleaks are sent to info@tarleaks.com (legal and licensing) and are effective when received. Notices to
   you are sent to the e-mail address associated with your Licence Key.
5. This licence is written in English. If it is translated, the English version prevails to the extent permitted by
   law.
6. Tarleaks may publish new versions of this licence. A new version applies to Software versions released with it and
   to Licence Keys issued or renewed after it is published, not to versions you already installed under an earlier key.

## 16. Contact

Licensing, sales and support: info@tarleaks.com · https://tarleaks.com
Security reports: see [SECURITY.md](SECURITY.md) (private reporting, or dev@tarleaks.com).
