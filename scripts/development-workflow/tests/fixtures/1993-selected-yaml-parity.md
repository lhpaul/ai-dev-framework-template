# Selected-private YAML parity corpus (#1993)

`1993-selected-yaml-parity.json` freezes the public repository fixture corpus at
`25e702d2cf8ea5c7d97c9080a44fec84a3607a63`. P11 in
`test_selected_private_yaml.py` passes each of its 1020 distinct documents through
both the own parser and the actual `yaml-source-check` CLI with PyYAML unavailable.
The corpus records 2117 origins (test file, source line, extraction kind/context).
This is syntax compatibility before independent schema/preference validation.
P12 explicitly preserves malformed reviewer-schema rejection for YAML-valid
nested scalars and accepts whitespace before mapping colons, including list items.
The DSH harness still separately rejects a BOM in an activated model envelope;
a BOM at the beginning of a YAML stream is valid syntax.

## Extraction and reference behavior

The development extraction examines every tracked test Bash/Python file (141),
all shell heredocs irrespective of delimiter, Python string constants including
embedded Python, shell single/double/newline literals and assembled printf/write-fixture arguments, and all 49 tracked public `.yaml`/`.yml` files, without filename filtering. It additionally executes all 28 original DSH model tests
in a public base snapshot with fake HOME, denied provider commands and file-only
Git transport, capturing all 742 assembled shared/local documents. Dynamic
shell scalar templates are indexed as literals, not expanded using workstation
environment or private configuration. Static fragments remain in the candidate
index with their baseline disposition; no arbitrary sample was substituted.

The overinclusive index contains 5827 candidates. Of these, 2097 origins pass
pinned develop's `parse_review_yaml` strict reader (full syntax and framework
representation, before reviewer schema). The corpus also includes 20 individually
classified valid legacy-context flow-mapping origins already supported by the
own syntax parser; no new schema or field preference is inferred. Repeated
origins share one document while retaining provenance.

The strict oracle rejects duplicate keys, unsupported representation and malformed
syntax. Success of develop's permissive `parse_yaml_snapshot` is never sufficient
to classify a document as valid. Each nonbinding candidate retains source context
and a reproducible disposition in the creator's extraction manifest/index:

- 1183 invalid-YAML/non-YAML candidates: YAML compose rejects the literal.
- 1640 nonmapping candidates: not a workflow configuration document.
- 327 empty/comment/non-config candidates.
- 453 candidates rejected by both baseline framework readers.
- 127 legacy-only candidates receive individual context dispositions: explicit
  negative duplicate/metadata/complex-key cases; lexical escaped fragments or
  diagnostic literals with separately indexed decoded/AST counterparts;
  CodeRabbit's separate platform grammar; remote response diagnostics; shared-only
  legacy compatibility cases that explicitly remove the private source; or the
  20 binding flow-mapping origins above.

Selected-private validation is not applied to another platform's grammar or to
absent-private shared-only legacy controls. Their actual original consumers and
rejection/compatibility tests remain intact. Unsupported metadata/references and
multiline constructs remain fail-closed for selected workflow sources.

The extraction script, complete per-candidate classification, baseline model
capture and old/new CLI proofs are retained with cycle8 creator evidence. The
fixture is pinned so tests do not depend on a shallow clone containing an old
Git object or on runtime PyYAML; PyYAML was only a development reference oracle.

The development oracle used PyYAML 6.0.3 with the pinned develop reader;
CI keeps its existing PyYAML6.0.2 provision. The corpus test itself needs neither
version at runtime. All49 tracked YAML files have individual reference outcomes
in the extraction manifest; unsupported platform/Actions multiline formats are
classified by their actual consumer grammar, not silently dropped.
