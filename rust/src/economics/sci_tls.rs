use rustls::{
    ClientConfig, DigitallySignedStruct, Error, RootCertStore, SignatureScheme,
    client::{
        WebPkiServerVerifier,
        danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier},
    },
    pki_types::{CertificateDer, ServerName, UnixTime},
};
use std::sync::Arc;

const INTERMEDIATE: &[u8] = include_bytes!("certificates/certum-dv-tls-g2-r39.der");

pub(super) fn client() -> Result<reqwest::Client, String> {
    let mut roots = RootCertStore::empty();
    roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    let normal = WebPkiServerVerifier::builder(Arc::new(roots))
        .build()
        .map_err(|_| "iran_tls_failed")?;
    let config = ClientConfig::builder()
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(SciVerifier { normal }))
        .with_no_client_auth();
    reqwest::Client::builder()
        .use_preconfigured_tls(config)
        .https_only(true)
        .timeout(std::time::Duration::from_secs(20))
        .redirect(reqwest::redirect::Policy::none())
        .user_agent("Pouch economic profiles")
        .build()
        .map_err(|_| "iran_transport_failed".into())
}

#[derive(Debug)]
struct SciVerifier {
    normal: Arc<WebPkiServerVerifier>,
}

impl ServerCertVerifier for SciVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        intermediates: &[CertificateDer<'_>],
        server_name: &ServerName<'_>,
        ocsp_response: &[u8],
        now: UnixTime,
    ) -> Result<ServerCertVerified, Error> {
        let allowed = match server_name {
            ServerName::DnsName(name) => matches!(name.as_ref(), "amar.org.ir" | "www.amar.org.ir"),
            _ => false,
        };
        if !allowed {
            return self.normal.verify_server_cert(
                end_entity,
                intermediates,
                server_name,
                ocsp_response,
                now,
            );
        }
        let mut chain = intermediates.to_vec();
        // Chain-building material only; the normal trusted roots remain unchanged.
        chain.push(CertificateDer::from(INTERMEDIATE));
        self.normal
            .verify_server_cert(end_entity, &chain, server_name, ocsp_response, now)
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        signature: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        self.normal.verify_tls12_signature(message, cert, signature)
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        signature: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        self.normal.verify_tls13_signature(message, cert, signature)
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.normal.supported_verify_schemes()
    }
}

pub(super) fn request_error(error: &reqwest::Error) -> String {
    use std::error::Error as _;
    if error.is_timeout() {
        return "iran_timeout".into();
    }
    let mut cause = error.source();
    while let Some(value) = cause {
        if value.downcast_ref::<rustls::Error>().is_some()
            || value
                .downcast_ref::<std::io::Error>()
                .and_then(std::io::Error::get_ref)
                .is_some_and(|inner| inner.downcast_ref::<rustls::Error>().is_some())
        {
            return "iran_tls_failed".into();
        }
        cause = value.source();
    }
    "iran_transport_failed".into()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn normal(roots: RootCertStore) -> Arc<WebPkiServerVerifier> {
        WebPkiServerVerifier::builder(Arc::new(roots))
            .build()
            .expect("verifier")
    }

    fn roots() -> RootCertStore {
        let mut roots = RootCertStore::empty();
        roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
        roots
    }

    fn leaf() -> CertificateDer<'static> {
        CertificateDer::from(include_bytes!("fixtures/sci-leaf-2026.der").as_slice())
    }

    fn time(date: &str) -> UnixTime {
        let seconds = chrono::DateTime::parse_from_rfc3339(date)
            .expect("date")
            .timestamp();
        UnixTime::since_unix_epoch(std::time::Duration::from_secs(seconds as u64))
    }

    #[test]
    fn missing_intermediate_is_supplied_without_changing_roots() {
        let normal = normal(roots());
        let host = ServerName::try_from("amar.org.ir").expect("host");
        let now = time("2026-10-05T12:00:00Z");
        assert!(
            normal
                .verify_server_cert(&leaf(), &[], &host, &[], now)
                .is_err()
        );
        let verifier = SciVerifier { normal };
        assert!(
            verifier
                .verify_server_cert(&leaf(), &[], &host, &[], now)
                .is_ok()
        );
        let alternate = ServerName::try_from("www.amar.org.ir").expect("host");
        assert!(
            verifier
                .verify_server_cert(&leaf(), &[], &alternate, &[], now)
                .is_ok()
        );
    }

    #[test]
    fn hostname_validity_and_trust_failures_are_rejected() {
        let verifier = SciVerifier {
            normal: normal(roots()),
        };
        let host = ServerName::try_from("amar.org.ir").expect("host");
        for date in ["2026-04-17T12:00:00Z", "2026-11-04T12:00:00Z"] {
            assert!(
                verifier
                    .verify_server_cert(&leaf(), &[], &host, &[], time(date))
                    .is_err()
            );
        }
        let other = ServerName::try_from("example.com").expect("host");
        let now = time("2026-10-05T12:00:00Z");
        assert!(
            verifier
                .verify_server_cert(
                    &leaf(),
                    &[CertificateDer::from(INTERMEDIATE)],
                    &other,
                    &[],
                    now
                )
                .is_err()
        );
        let mut unrelated = RootCertStore::empty();
        unrelated
            .add(CertificateDer::from(
                include_bytes!("fixtures/sci-unrelated-root.der").as_slice(),
            ))
            .expect("root");
        let verifier = SciVerifier {
            normal: normal(unrelated),
        };
        assert!(
            verifier
                .verify_server_cert(&leaf(), &[], &host, &[], now)
                .is_err()
        );
    }

    #[test]
    fn supplementation_is_scoped_and_cannot_accept_a_bad_signature() {
        let verifier = SciVerifier {
            normal: normal(roots()),
        };
        let now = time("2026-10-05T12:00:00Z");
        let other = ServerName::try_from("example.com").expect("host");
        assert!(matches!(
            verifier.verify_server_cert(&leaf(), &[], &other, &[], now),
            Err(Error::InvalidCertificate(
                rustls::CertificateError::UnknownIssuer
            ))
        ));
        let mut altered = leaf().as_ref().to_vec();
        let last = altered.last_mut().expect("certificate signature");
        *last ^= 1;
        let host = ServerName::try_from("amar.org.ir").expect("host");
        assert!(
            verifier
                .verify_server_cert(&CertificateDer::from(altered), &[], &host, &[], now)
                .is_err()
        );
    }
}
