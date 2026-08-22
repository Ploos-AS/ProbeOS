<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Common document metadata contract

Hardware reports, diagnostics, benchmarks, stability results, and
qualification records remain independent, independently versioned schemas.
They describe different claims and are not members of one giant result schema.

Where applicable, new documents should use these common concepts with their
existing schema's naming conventions:

- `document_type`: stable kind identifier;
- `schema_version`: version of that document only;
- ProbeOS identity: version/product version, build channel, Git commit, and
  architecture;
- generation timestamp and timestamp reliability; and
- a run/qualification ID or privacy profile only when meaningful.

Existing schema 1.1 hardware reports and schema 1.0 diagnostics, benchmark,
stability, and qualification documents remain valid. Adoption is additive and
must not reinterpret an existing field. A future incompatible adoption needs
that individual schema's version change, not a global envelope version bump.

Identity answers which build produced evidence. Qualification bundle SHA-256
links identify the exact bytes of each linked document. The common vocabulary
does not replace, weaken, or normalize those hashes.
