# Collection rendering — architecture review

Tracking issue: metanorma/metanorma#573

Internal discussion document for the maintainer (opoudjis). Analysis only; no code
changes proposed for immediate execution. The overriding constraint throughout is
**performance must not regress** — this code has had real bottlenecks beaten out of
it, and several apparently-ugly constructs are load-bearing optimisations. Every
recommendation below carries an explicit **perf-risk** tag.

Scope: `lib/metanorma/collection/` — renderer, filelookup, sectionsplit,
xrefprocess, manifest, util. File:line references are to the tree as of commit
`5c05fbd` (the attachment-link sectionsplit fix).

---

## 1. Pipeline map — end-to-end collection render

### 1.1 Entry and setup

`Collection#render` (`collection.rb:129`) → `Renderer.render` (`renderer.rb:144`).
`Renderer.render` is the spine:

```
cr = new(col, dir, options)   # renderer.rb:146  — build FileLookup, isodoc, dirs
cr.files                      # renderer.rb:147  — compile every doc (the heavy loop)
cr.rxl(options)               # renderer.rb:148  — write collection.rxl
cr.concatenate(col, options)  # renderer.rb:149  — build collection.xml / .presentation.xml / pdf / doc
cr.coverpage                  # renderer.rb:150  — Liquid coverpage (html only)
cr.flush_files                # renderer.rb:151  — delete temp + sectionsplit leftovers
```

`Renderer#initialize` (`renderer.rb:36-85`) is where the *file table* is built:

- `@xml = Nokogiri::XML collection.to_xml` (`renderer.rb:38`) — the collection
  manifest, parsed once and kept.
- `@files = FileLookup.new(folder, self)` (`renderer.rb:81`) — reads **every**
  source XML, extracts bibdata/anchors/ids per file (see §1.5).
- `@files.add_section_split` (`renderer.rb:82`) — **expands sectionsplit documents
  in place** before the main render loop ever runs (see §2). This is the single most
  surprising piece of control flow: by the time `cr.files` runs, a sectionsplit
  document has already been split into N sub-entries in `@files`, each compiled to
  presentation XML on disk.

### 1.2 The per-file loop (`fileprocess.rb:59` `#files`)

For each identifier in `@files.keys`:

- **attachment** → `copy_file_to_dest` (`filelocation.rb:149`), no compile.
- **document** → read source (Semantic XML), `update_xrefs` (`fileparse.rb:17`),
  write the resolved XML to a tmp file, then `file_compile` (`fileprocess.rb:13`).

`internal_refs = locate_internal_refs` (`fileprocess.rb:61`) is computed **once**
before the loop and threaded through every `update_xrefs` call — a deliberate
hoist (see §1.5).

### 1.3 Semantic vs Presentation XML at each stage

This is the axis that makes the code hard to read, because the same variable names
(`xml`, `file`, `docxml`) carry *different* document grammars at different points:

| Stage | Grammar | Where |
|---|---|---|
| Source files read by FileLookup | **Semantic** | `filelookup.rb:81`, `:ref` files |
| `update_xrefs` input for a normal doc | **Semantic** | `fileprocess.rb:69`, `fileparse.rb:17` |
| `update_xrefs` input for a sectionsplit-output sub-file | **Presentation** (`:sectionsplit_output` truthy) | `fileparse.rb:34-39` |
| Sectionsplit `sectionsplit_prep` output | **Presentation** | `sectionsplit.rb:98-109` (compiles to `.presentation.xml`) |
| `file_compile` → flavour `Compile#compile` | Semantic → all formats | `fileprocess.rb:19` |
| `concatenate1` collecting per-doc outputs | Presentation/whatever ext | `renderer.rb:256-267` |

The pivot is `sso = @files.get(docid, :sectionsplit_output)` (`fileparse.rb:38`).
**`sso` truthy ⇒ the file is already Presentation XML**, so `update_xrefs` skips the
semantic-only passes (`xref_process`, indirect/sectionsplit doc resolution,
svgmap) and only does direct-ref + hide_refs + eref2link. This is correct but
**entirely implicit** — the only documentation is the one-line comment at
`fileparse.rb:34`.

### 1.4 The three reference-resolution passes (`fileparse.rb:17-32` `#update_xrefs`)

The header comment (`fileparse.rb:4-10`) is the best existing summary. In order:

1. **`xref_process`** (`fileparse.rb:18-21`) — only when `!@nested && !sso`.
   Delegates to `XrefProcess.xref_process` (`xrefprocess.rb:26`): turns intra-doc
   `xref`/`eref` into internal erefs, copies repo bibitems, inserts indirect biblio.
2. **`update_indirect_refs_to_docs`** (`fileparse.rb:23`, body `fileparse.rb:133`)
   — resolves `bibitem[@type='internal']` repository refs (anchor in an unknown
   collection file) to a concrete containing document.
3. **`add_document_suffix`** (`fileparse.rb:24` → `filelookup.rb:237`) — namespaces
   every `@id`/`@anchor` with a per-doc NCName suffix so concatenated docs don't
   collide. Mutates the tree.
4. **`update_sectionsplit_refs_to_docs`** (`fileparse.rb:25`, body `fileparse.rb:42`)
   — rewrites erefs that target a *sectionsplit* document to point at the specific
   split section file that contains the anchor.
5. **`update_direct_refs_to_docs`** (`fileparse.rb:27`, body `fileparse.rb:88`) —
   `repo(current-metanorma-collection/X)` → hyperlink + bibdata in situ; calls the
   `update_anchors` **bottleneck** (§3.6).
6. **`hide_refs`** (`fileparse.rb:28` → `util.rb:71`) — flags now-empty hidden
   references containers.
7. `eref2link` / `svgmap_resolve` post-passes.

All of 1-7 mutate the *same* Nokogiri tree in place. There is no intermediate
typed representation; the contract between passes is "the tree is now in state X",
documented only by reading the passes in order.

### 1.5 The lookup tables (built once, read hot)

`locate_internal_refs` (`fileprocess.rb:132`) builds a `schema → anchor → filename`
map by:

- `gather_internal_refs` (`fileprocess.rb:87`) — re-parses every non-attachment,
  non-sectionsplit source file (`Nokogiri::XML(file, &:huge)` at `:97`) to collect
  indirect-ref targets;
- `populate_internal_refs` (`fileprocess.rb:121`) — re-parses **every file again**
  (`locate_internal_refs1` → `locate_internal_refs1_prep`, `fileprocess.rb:156`) to
  build an `id/anchor → element` index per file and match the wanted ids.

So the reference graph costs **two full re-parses of every source document** before
the main loop. This is a known cost centre (see §3.1) but the result is hoisted out
of the per-file loop (`fileprocess.rb:61`), so it is paid once, not O(files²).

### 1.6 Concatenate / coverage

`concatenate` (`renderer.rb:164`) builds `collection.xml` and, if pdf/doc/bilingual
is requested, `collection.presentation.xml`, then runs mn2pdf / doc / bilingual
HTML. `concatenate1` (`renderer.rb:256`) pulls each doc's already-compiled output
back off disk via `@files.get(id, :outputs)[ext]`. Coverpage is a Liquid template
fill (`renderer.rb:277`).

---

## 2. Sectionsplit deep-dive

Sectionsplit is hard because it is **a collection render nested inside a collection
render**, wired together through the file table and several temp directories. Two
distinct entry paths exist.

### 2.1 Path A — sectionsplit inside an existing collection (the FileLookup path)

Triggered from `FileLookup#add_section_split` (`filelookup_sectionsplit.rb:6`),
called at `renderer.rb:82` during renderer construction, **before** the main loop.

```
add_section_split                         filelookup_sectionsplit.rb:6
  for each @files entry with :sectionsplit and not :attachment
    process_section_split_instance        filelookup_sectionsplit.rb:17
      original_out_path = @files[key][:out_path]   # saved for cleanup
      s, manifest = sectionsplit(key)     filelookup_sectionsplit.rb:142
        Sectionsplit.new(...).sectionsplit         sectionsplit.rb:41
        Sectionsplit#collection_manifest  sectionsplit/collection.rb:34
      for each split section file f1:
        add_section_split_instance        filelookup_sectionsplit.rb:98
          -> inserts a NEW @files entry per section (presentation XML,
             :sectionsplit_output=true, :parentid=key, :bare for idx>0)
      add_section_split_attachments       filelookup_sectionsplit.rb:89
      add_section_split_cover             filelookup_sectionsplit.rb:59
    cleanup_section_split_instance        filelookup_sectionsplit.rb:44
      schedule original parent html/xml/presentation.xml for deletion
      @files[key][:indirect_key] = @sectionsplit.key
```

The parent document's `@files` entry survives but is turned into a cover/index
attachment-like entry (`add_section_split_cover`, `filelookup_sectionsplit.rb:59`
sets `:out_path = cover`), and N new entries — one per section — are inserted.
**The `@files` hash is mutated and re-built** (`add_section_split` rebuilds it into
`ret` at `:7-14`).

### 2.2 The split itself (`sectionsplit.rb`)

`Sectionsplit#sectionsplit` (`sectionsplit.rb:41`):

1. `sectionsplit_prep` (`:98`) — reads the **Semantic** source, runs
   `sectionsplit_update_xrefs` (`:121`, which re-enters the *parent's*
   `update_xrefs` with `@nested=true` so unresolved erefs survive), writes a temp
   semantic file, then **compiles it to Presentation XML** via a fresh
   `Compile.new.compile` (`:104`) and reloads the `.presentation.xml`. So from here
   on `xml` is Presentation XML.
2. `xref_preprocess` (`:43` → `xrefprocess.rb:9`) — stamps a random 8-char `key` on
   the root and suffixes all anchor attrs. The `key` becomes the document's
   `:indirect_key` and ties the split files back together.
3. `empty_doc` (`:140`) — clones the doc and strips all section content to make the
   **template** every section file is built from. `empty_attachments` (`:151`) is
   just `xml.dup` (a second template used for idx>0; the only difference is the
   first file keeps the section-free `empty`).
4. `sectionsplit1` (`:53`) walks `SPLITSECTIONS` (`:34-38`: preface, sections,
   annex, bibliography, indexsect, colophon), conflates floating titles
   (`conflate_floatingtitles`, `:88`), and for each chunk posts a job to a
   **thread pool of size 1** (`:48`) that calls `sectionfile` (`:155`).
5. `sectionfile` → `create_sectionfile` (`:161`): inserts the chunk into a clone of
   the template, filters footnotes/annotations down to those referenced
   (`sectionfile_fn_filter` `:185`, `sectionfile_annotation_filter` `:237`), runs
   `XrefProcess.xref_process(out, xml, @key, ...)` to resolve cross-refs within the
   section, and writes the section file.

### 2.3 The flat-XML-vs-directory-HTML output split

This is the subtle invariant that the recent bug (`5c05fbd`) lives next to:

- **XML section files are always written flat** to `@splitdir` (the `_files`
  directory), basename only — `create_sectionfile` (`sectionsplit.rb:166-174`) is
  explicit about this in comments.
- **HTML output may carry a directory** from `sectionsplit_filename` (e.g.
  `split/{basename}.html`). The directory is reattached only at HTML compile time
  via `preserve_directory_structure?` (`filelookup.rb:359`) and the
  `file_compile_format` machinery (`filelocation.rb:65-79`).

The manifest YAML (`collectionyaml`, `sectionsplit/collection.rb:41-73`) encodes
this: `fileref` is always the basename (`:60`), but
`sectionsplit-filename`/`sectionsplit-output` are emitted only when there is a
directory (`:64-67`) so the *inner* renderer knows to re-expand it.

### 2.4 Path B — single-file sectionsplit building its own collection

`Sectionsplit#build_collection` (`sectionsplit/collection.rb:4`): used when a single
document is sectionsplit on its own. It runs `sectionsplit`, writes a generated
`*.html.yaml` manifest (`collectionyaml`), and calls `Metanorma::Collection.parse`
+ `.render` recursively (`:9-12`) — a **fully nested collection render** — then moves
attachments (`section_split_attachments`, `:79`).

### 2.5 Attachment handling and the early/late asymmetry (the recent bug)

`section_split_attachments` (`sectionsplit/collection.rb:79`) moves the
`_<basename>_attachments` directory from the temp split location to the collection
output. The attachment *links* inside section files are resolved during
`update_bibitem` (`fileparse.rb:170`).

The bug fixed in `5c05fbd`: attachment URLs were relativised against the
referencing document's **unsplit `:out_path`**, but a sectionsplit document's
content is actually emitted at the split output location, so `../../` overshot. The
fix introduced `referencing_html_location` (`fileparse.rb:208`) + helpers
`sectionsplit_ref_html` / `document_ref_html` (`:216`, `:223`) to choose the right
base. The regression spec (`spec/collection/attachment_link_path_spec.rb`) pins all
four cases. This fix is correct, but it is a *symptom* of pain point §3.2.

---

## 3. Maintainability pain points (evidence-based)

### 3.1 The reference graph is built from repeated full re-parses
`gather_internal_refs1` (`fileprocess.rb:97`), `locate_internal_refs1_prep`
(`fileprocess.rb:156`), and FileLookup's own `bibdata_process` (`filelookup.rb:81`)
each `Nokogiri::XML(file, &:huge)` the *same* source files. A given source document
is parsed at least 3× before its content is even compiled. **This is load-bearing
optimisation territory, not just waste** — see perf note in §4.

### 3.2 Early-vs-late reference resolution asymmetry
Some links are resolved *before* the split, against the unsplit `out_path`
(`update_bibitem` path); others are resolved *during* the inner render of the split
files. The two views of "where does this document's content live" diverge under
sectionsplit, which is exactly what produced the `5c05fbd` bug. The new
`referencing_html_location` (`fileparse.rb:208`) papers over one instance, but the
underlying asymmetry — *out_path is not where the content ends up for a sectionsplit
doc* — is undocumented as an invariant and will bite again (e.g. svgmap, images,
PDF cross-links).

### 3.3 Path computation is scattered across ≥4 files
Relative/output path logic lives in: `filelocation.rb`
(`preserve_output_dir_structure`, `move_file_to_subdirectory`,
`apply_custom_filename_pattern`, `:39-147`), `fileparse.rb`
(`referencing_html_location`, `sectionsplit_ref_html`, `document_ref_html`,
`out_path_to_html`, `:208-232`), `utils.rb` (`make_relative_path`, `:91`),
`filelookup.rb` (`output_file_path`, `file_entry_paths`,
`substitute_filename_pattern`, `ref_file_xml2html`, `:145-312`), and
`filelookup_sectionsplit.rb` (`add_section_split_instance` path assembly,
`:98-130`). Each does its own `File.dirname`/`File.basename`/`relative_path_from`
dance with slightly different rules (when to strip `.xml`, when to keep dirs, when
to disambiguate). The placeholder substitution (`{basename}`, `{basename_legacy}`,
`{document-num}`, `{sectionsplit-num}`) is implemented **twice** — once in
`FileLookup#substitute_filename_pattern` (`filelookup.rb:168`) and once inline in
`Sectionsplit#sectionsplit2` (`sectionsplit.rb:69-73`).

### 3.4 The `@files` entry is an untyped grab-bag
A FileLookup entry is a bare `Hash` carrying ~26 distinct keys (counted across the
codebase): `:format :outputs :out_path :url :type :attachment :ref :bibdata
:bibitem :sectionsplit :sectionsplit_output :sectionsplit_filename :rel_path
:indirect_key :index :parentid :idx :ids :document_suffix :presentationxml :pdffile
:bare :anchors :anchors_lookup :output_filename :extract_opts`. Access is via
`@files.get(id, :key)` (`base.rb:20`) with no schema, no validation, and several
near-synonyms whose distinction is only learnable by reading every writer:
- `:ref` (absolute source) vs `:rel_path` (relative to YAML) vs `:out_path`
  (destination) vs `:url` vs `:outputs[:html]` (post-compile actual path) — five
  notions of "where is this file", documented only in a comment block at
  `filelookup.rb:102-107` and `:128-134`.
- `:idx` vs `:index`; `:sectionsplit` vs `:sectionsplit_output`;
  `:sectionsplit_filename` vs `:output_filename`.
- `:type` holds the string `"fileref"`/`"id"` (`filelookup.rb:116,122`) — unrelated
  to document flavour `type`.

There is no single place that says "these are the fields and what they mean."

### 3.5 Duplicated / divergent method definitions in FileLookup
`filelookup/utils.rb` and `filelookup/base.rb` and `filelookup/filelookup.rb`
**redefine the same methods**. `filelookup.rb` requires both `base` (`:6`) and
`utils` (`:7`), with `utils` last. Duplicated: `read_ids`, `read_anchors`,
`read_anchors1`, `anchors_lookup`, `url`, `url?`, `key`, `keys`, `get`, `set`,
`each`, `each_with_index`, `ns`. Because `utils.rb` is required last, **its
definitions win** — and `read_anchors1` in `utils.rb` (`utils.rb:29-38`) uses the
regex `%r{<[^<>]+>}` whereas the copy in `filelookup.rb` (`:335-344`) uses
`%r{<[^>]+>}`. Whichever is actually live is decided by require order, not by
intent. This is a latent correctness hazard, not merely cosmetic. (`utils.rb` looks
like an extraction-in-progress that was never completed or wired exclusively.)

### 3.6 The `update_anchors` bottleneck (`fileparse.rb:195`, marked `# bottleneck`)
For each repository bibitem, `update_anchors` iterates `erefs_no_anchor` and
`erefs_anchors` and calls `update_anchors1` (`:208`) which consults
`@files.get(docid).dig(:anchors_lookup, ...)`. The `:anchors_lookup` table
(`anchors_lookup`, `utils.rb:40` / `filelookup.rb` via `bibdata_extract`) is a
flattened `{anchor => true}` set precomputed per file — this is the optimisation
that keeps the lookup O(1) instead of re-xpathing the target doc per eref. **Do not
remove `:anchors_lookup`** (see §5).

### 3.7 `@nested` flag overloading
`@nested` (`renderer.rb:70`) means "this Renderer will run again, don't do
finalising ref work." It gates five different behaviours in `update_xrefs`
(`fileparse.rb:19,23,25,30`) and the strip-unresolved logic
(`fileparse.rb:126`). Sectionsplit toggles it on the *parent* renderer temporarily
(`sectionsplit.rb:122-126`: save, set true, call, restore). One boolean encoding
"am I the root render?" + "should I preserve unresolved erefs?" + "skip svgmap" is
hard to reason about; the save/restore-around-call idiom is a smell that it is
really a per-call parameter, not object state.

### 3.8 Nested-manifest in-place expansion
`Manifest#manifest_expand_yaml` (`manifest.rb:118`) mutates entries in place,
setting `entry.entry = ...from_yaml(...)` and rewriting filepaths via
`update_filepaths` (`:141`). Combined with the several `manifest_*` passes that each
recurse the tree independently (`manifest_postprocess`, `:23-32` runs 7 separate
recursive walks), the manifest is normalised by a pipeline of mutating tree-walks
with order dependencies that are not stated.

### 3.9 Identifier/key normalisation duplicated
`key` is defined in `Util::key` (`util.rb:79`), `FileLookup#key` (`base.rb:11`,
`utils.rb:61`), and the decode+squeeze pattern recurs in `docid_prefix`
(`utils.rb` renderer, `:105`). `FileLookup#key` additionally strips a
`metanorma-collection ` prefix (`base.rb:13`) that `Util::key` does not — so they
are *not* interchangeable, yet both are called "key". Mixing them is a footgun.

### 3.10 Mutation-in-place through many passes
Every resolution pass mutates the shared Nokogiri tree (§1.4). There is no
checkpoint, no copy, no assertion of post-conditions. Debugging "which pass put the
tree in this state" means instrumenting each pass. This is partly inherent to
Nokogiri performance (copying trees is expensive), but the *absence of documented
invariants between passes* is the maintainability cost, not the mutation itself.

### 3.11 Dead / commented-out code and `warn` debug noise
Numerous `# KILL`, commented thread-pool variants, and `warn` timing/debug lines
remain: `renderer.rb:93-106` (two methods named `directives_normalise_coverpage_pdf_portfolio`,
the **second silently shadows the first**), `renderer.rb:132,145,165,179,200` warn
spam, `filelookup.rb:212` `warn ret`, `filelookup_sectionsplit.rb:32-42`
(`section_split_instance_threads` defined but unused), `fileprocess.rb:48-55`
commented `allowed_extension_keys`. The duplicate `directives_normalise_coverpage_pdf_portfolio`
(`renderer.rb:94` and `:108`) is an actual bug-shaped artifact: Ruby keeps the
second definition, so the first (more elaborate) one is dead.

---

## 4. Prioritised recommendations

Each carries a **perf-risk** tag: `NEUTRAL` (no runtime change), `COULD-HELP`,
`RISK` (could reintroduce a bottleneck — flagged loudly), `BENIGN-CLEANUP`.

### HIGH

**H1. Document the file-grammar and out_path invariants as code comments + a
one-page note.** State explicitly: (a) when `xml`/`file` is Semantic vs Presentation
and that `:sectionsplit_output` is the discriminator; (b) the load-bearing invariant
"for a sectionsplit document, content is emitted at the sectionsplit output
location, NOT at `:out_path`" (the §3.2 root cause). Put it at the top of
`fileparse.rb` and `sectionsplit.rb`.
*Gain:* directly prevents recurrences of the `5c05fbd` class of bug.
**perf-risk: NEUTRAL** (comments only).

**H2. Resolve the FileLookup method duplication (§3.5).** Pick one home for
`read_ids`/`read_anchors`/`read_anchors1`/`anchors_lookup`/`url`/`key`/etc., delete
the others, and reconcile the divergent `read_anchors1` regex (`<[^<>]+>` vs
`<[^>]+>`) deliberately. Right now correctness depends on require order.
*Gain:* removes a latent correctness hazard and ~80 lines of confusing duplication.
**perf-risk: NEUTRAL** (same code runs; you are just deleting the shadowed copy).
*Caveat:* verify which regex is currently live before deleting, so behaviour is
preserved exactly unless you intend to change it.

**H3. Introduce a typed `FileEntry` value object wrapping the `@files` hash
(§3.4).** Keep the hash as the backing store for perf, but give it named readers and
a documented field list, plus predicate methods (`#sectionsplit?`,
`#sectionsplit_output?`, `#attachment?`). Do this incrementally behind the existing
`get/set` API so call sites can migrate gradually.
*Gain:* the single biggest readability win; makes the 26-key grab-bag legible.
**perf-risk: COULD-HELP if done as a thin wrapper, RISK if naively done.** A
`Struct`/`Data` rebuilt per access, or replacing the hash with per-call object
allocation in the hot `update_anchors`/`gather_*` loops, **would** add allocation
pressure. Mark clearly: the wrapper must be allocated **once per entry**, not per
access, and the hot paths (`fileparse.rb:196-237`, `util.rb:17-45`) should keep
using direct hash reads or memoised readers. Stage it: wrapper first for the
cold-path call sites (manifest, setup), leave the bottleneck loops on raw hash
access until measured.

### MEDIUM

**M1. Consolidate path computation into one module (§3.3).** Gather
`make_relative_path`, `out_path_to_html`, `ref_file_xml2html`, `output_file_path`,
`preserve_output_dir_structure`, `substitute_filename_pattern`, and the inline
substitution in `sectionsplit.rb:69-73` into a single `PathResolver` with
well-named, individually-tested methods. De-duplicate the two placeholder
substituters first (they should be one function).
*Gain:* the next path bug (and §3.2 predicts more) gets fixed in one place with a
test, instead of hunting four files.
**perf-risk: NEUTRAL.** Pure string/Pathname math, not in an XML-parsing hot loop;
moving it does not change call frequency. Keep the functions pure (no I/O) so they
stay cheap.

**M2. Turn `@nested` into an explicit parameter or a small mode object (§3.7).**
The save/set-true/call/restore dance in `sectionsplit_update_xrefs`
(`sectionsplit.rb:122-126`) is the tell. Pass a `render_mode:` (`:root` /
`:nested`) argument through `update_xrefs`, or split `update_xrefs` into
`update_xrefs_root` / `update_xrefs_nested` that share helpers.
*Gain:* removes hidden global-ish state; makes the sectionsplit re-entry legible.
**perf-risk: NEUTRAL** (same branches, just parameterised).

**M3. Name the sectionsplit control flow seams (§2).** Extract well-named methods
for the three conceptual phases that are currently interleaved in
`add_section_split` / `process_section_split_instance`: *split-into-section-files*,
*register-section-entries-in-@files*, *register-cover-and-attachments*. The logic
need not move; just give the phases names and a comment each.
*Gain:* the hardest-to-follow file becomes a readable three-step.
**perf-risk: NEUTRAL** (method extraction only).

**M4. Delete dead code and shadowed definitions (§3.11).** Remove the shadowed
`directives_normalise_coverpage_pdf_portfolio` (`renderer.rb:94` — confirm which is
intended), unused `section_split_instance_threads`, commented `allowed_extension_keys`,
`# KILL` blocks. Gate the `warn` timing lines behind a debug flag rather than
unconditional stderr spam.
*Gain:* less noise, removes a real shadowing bug.
**perf-risk: BENIGN-CLEANUP** (removing `warn` calls is a micro-improvement; the
shadowed-method removal must preserve whichever definition is actually wanted).

### LOW

**L1. Unify identifier normalisation (§3.9).** Document the difference between
`Util::key` and `FileLookup#key` (the `metanorma-collection ` strip) and rename one
so they are not both `key`. Consider a single `Identifier` helper.
**perf-risk: NEUTRAL.**

**L2. Document the manifest normalisation pipeline order (§3.8).** Add a comment to
`manifest_postprocess` (`manifest.rb:23`) stating why the 7 passes run in that order
and which depend on which.
**perf-risk: NEUTRAL.**

**L3. Add post-condition comments (not assertions) to each `update_xrefs` pass
(§3.10)** describing the tree state each pass guarantees on exit.
**perf-risk: NEUTRAL.**

---

## 5. Do NOT do this — refactors that would reintroduce bottlenecks

- **Do NOT replace the precomputed `:anchors` / `:anchors_lookup` / `:ids` tables
  with on-demand xpath.** These are built once in `bibdata_extract`
  (`filelookup.rb:87-93`) / `read_anchors` and consumed in the `update_anchors`
  **bottleneck** (`fileparse.rb:196-213`) and `update_anchor_create_loc`
  (`fileparse.rb:229-237`). Re-xpathing the target document per eref would turn an
  O(1) lookup into O(anchors × erefs) re-traversal. The flattened `:anchors_lookup`
  set exists specifically to avoid that.

- **Do NOT remove the hoist of `locate_internal_refs` out of the per-file loop**
  (`fileprocess.rb:61`). Computing the internal-ref graph once and threading it in
  is what keeps the loop O(files) and not O(files²). Folding it back inside
  `update_xrefs` would re-derive the whole graph per file.

- **Do NOT "tidy up" by re-parsing XML where a parsed tree is already in hand, or
  by parsing more than necessary.** The code already pays for ~3 re-parses per
  source file (§3.1); that is the *floor* the maintainer has tuned to, not an
  invitation to add more. Conversely, if consolidating §3.1 ever looks tempting,
  treat caching parsed trees as a **measured** change — naively memoising every
  parsed Nokogiri document for the whole render would blow memory on large
  collections (these docs are huge; note the `&:huge` parse flag everywhere). Any
  parse-caching must be scoped and benchmarked. **perf-risk on this whole area:
  HIGH either direction.**

- **Do NOT bump the sectionsplit thread pool back to 4 without measuring**
  (`sectionsplit.rb:48` is deliberately `FixedThreadPool.new(1)`; the size-4 variant
  and `section_split_instance_threads` are commented out at
  `filelookup_sectionsplit.rb:32`). Nokogiri tree mutation across threads is not
  obviously safe here and the pools were dialled to 1 for a reason — likely
  correctness or contention. Treat re-parallelising as a separate, carefully-tested
  investigation, not a cleanup.

- **Do NOT convert the `@files` hash to per-access object allocation** (see H3
  caveat). The wrapper, if introduced, must be one allocation per entry, and the
  bottleneck loops should stay on raw reads until profiled.

- **Do NOT deep-clone Nokogiri trees between passes to "isolate" them.** The
  in-place mutation (§3.10) is ugly but cheap; cloning the tree per pass to get
  immutability would multiply parse/serialise cost across every document.

---

## Appendix — key file:line index

| Concern | Location |
|---|---|
| Render spine | `renderer.rb:144-153` |
| File table built + sectionsplit expanded | `renderer.rb:81-82` |
| Per-file compile loop | `fileprocess.rb:59-84` |
| The three ref passes | `fileparse.rb:17-32` |
| Semantic/Presentation pivot (`sso`) | `fileparse.rb:34-39` |
| Internal-ref graph (double re-parse) | `fileprocess.rb:87-168` |
| `update_anchors` bottleneck | `fileparse.rb:195-213` |
| Attachment-link fix (`referencing_html_location`) | `fileparse.rb:208-232` |
| Sectionsplit core | `sectionsplit.rb:41-175` |
| Flat-XML / dir-HTML invariant | `sectionsplit.rb:166-174`, `filelookup.rb:359-369` |
| Sectionsplit @files expansion | `filelookup_sectionsplit.rb:6-130` |
| `@files` entry key comments | `filelookup.rb:102-107,128-134` |
| Duplicated FileLookup methods | `filelookup/utils.rb` vs `base.rb` vs `filelookup.rb` |
| Path math scattered | `filelocation.rb`, `utils.rb:91`, `filelookup.rb:145-312`, `fileparse.rb:208-232` |
| Manifest normalisation pipeline | `manifest.rb:23-32` |
| Shadowed method (dead) | `renderer.rb:94` vs `:108` |

🤖
