# Zenodo DOI (GitHub ↔ Zenodo)

The repository is public. A DOI is minted by Zenodo when it archives a GitHub **Release**.

## One-time setup (Primatio org owner)

1. Open [https://zenodo.org/login](https://zenodo.org/login) → **Log in with GitHub**.
2. Authorize Zenodo. If prompted for organization access, a **Primatio** owner must approve the Zenodo OAuth app under GitHub → Organization settings → Third-party access.
3. Open [https://zenodo.org/account/settings/github/](https://zenodo.org/account/settings/github/).
4. Find `Primatio/vault-vital-trace` and toggle **On**.

## After enabling

- Prefer enabling Zenodo **before** creating the release that should receive the DOI.
- If `v0.1.0` was published before the toggle, either:
  - use Zenodo’s GitHub page to sync / retry that release, or
  - publish a follow-up release (e.g. `v0.1.1`) after the toggle is On.

## Update citation files

When Zenodo shows the DOI (often `10.5281/zenodo.……`):

1. Uncomment and fill `identifiers` in [`CITATION.cff`](../CITATION.cff).
2. Replace the BibTeX `note` in [`README.md`](../README.md) with `doi = {10.5281/zenodo.……}`.
3. Commit and push.
