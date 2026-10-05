# SCI intermediate certificate

`certum-dv-tls-g2-r39.der` is a public intermediate certificate, not a private key or a new trust anchor.

- Subject: Certum DV TLS G2 R39 CA
- Issuer: Certum Trusted Root CA
- Official source: https://certumdvtlsg2r39ca.repository.certum.pl/certumdvtlsg2r39ca.cer
- Certificate catalogue: https://www.certum.pl/pl/cert_wiedza_zaswiadczenia_klucze_certum/
- SHA-256: `83c0a5a76844c840dfaf820ffd02adf6573a26823ef6af758a3384a0ac044083`
- Validity: 2024-06-18 through 2039-06-05
- Reviewed: 2026-10-05

SCI currently omits this issuer from its TLS chain. `sci_tls` supplies it only as intermediate chain-building material for `amar.org.ir` and `www.amar.org.ir`. The default WebPKI root set stays unchanged, and the normal verifier checks the complete chain, hostname, validity and signatures. A different host gets no supplementation. TLS handshake signatures are delegated to the same verifier.

No certificate is downloaded dynamically by the workaround. If SCI rotates its issuer or the intermediate expires, review the new chain and update this asset deliberately. Never add the intermediate to the root store or bypass verification.

The DER files under `../fixtures` are public server certificates captured on the review date. Tests use fixed timestamps within and outside the leaf certificate's validity, so they remain deterministic after the live certificate rotates. The unrelated root fixture proves that supplying the intermediate alone cannot establish trust.
