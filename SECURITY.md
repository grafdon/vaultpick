# Security

vaultpick handles passwords, so reports about anything that could expose a
secret are very welcome. Examples: a value that ends up on screen, in a file,
in a process list or in a log; entry data that can run commands or control the
terminal; a clipboard that is not cleared when it should be.

## Reporting

Please do not open a public issue for a vulnerability. Use GitHub's private
reporting instead: on the repository page, go to **Security**, then
**Report a vulnerability**.

Include the versions of vaultpick, rbw and fzf, your operating system, and the
steps to reproduce. Never include real secrets; `tests/demo` runs vaultpick
against a demo vault.

Only the latest release is supported.

## Out of scope

- Problems in rbw, fzf, jq or the clipboard tools themselves. Please report
  those to the respective project.
- Other programs in your session reading the clipboard while a value is on it.
  That is how clipboards work; see the security notes in the README.
