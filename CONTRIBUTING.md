# Contributing

Issues and pull requests are welcome, especially compatibility results for other
eSCL-capable Brother models.

Before submitting:

```bash
shellcheck bin/*.sh install.sh uninstall.sh
python3 -m unittest discover -s tests -v
```

Never attach real access tokens, documents, private hostnames/IPs, unsanitized
packet captures, or proprietary Brother packages. Include scanner model,
firmware version, SANE backend/version, OS, and redacted logs when relevant.
