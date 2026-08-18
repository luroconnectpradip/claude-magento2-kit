---
description: Check this repo is set up correctly for the luroConnect pipeline
---

Verify this repository against the luroConnect build contract.

Use the `luroconnect-m2` skill, Procedure D. Run the read-only checks and give me a
pass/fail line for each, then a short summary of anything to fix.

Remember:
- `app/etc/config.php` **must** be tracked — several public Magento `.gitignore`
  templates wrongly ignore it.
- `config.php.build` absent from git is **normal and correct**; luroConnect usually
  maintains it on the server. Never report that as a failure and never offer to
  create one.
- `app/etc/env.php`, `auth.json` and `id_rsa` must not be tracked.
