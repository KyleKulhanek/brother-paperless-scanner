# Security policy

Report vulnerabilities through GitHub's private vulnerability reporting when
available. Do not open a public issue containing tokens, LAN addresses, packet
captures with private data, or Paperless documents.

Deployment recommendations:

- Use a dedicated, non-administrator Home Assistant account and token.
- Store the token only in `/etc/brother-paperless-scanner/home-assistant.env`
  with mode `0640` or stricter.
- Restrict the service account to the scan work and consume directories.
- Keep Home Assistant, the scanner, and this host on trusted networks.
- Revoke a token immediately if it appears in a log, shell history, issue, or
  commit. Rewriting Git history is not a substitute for revocation.
- Review scanner-produced files with Paperless's normal document-processing
  protections; do not add executable extensions to the allowed workflow.

The project intentionally provides no remote remediation or printer-management
write API.
