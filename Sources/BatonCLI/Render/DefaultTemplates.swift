/// Bundled default Jinja templates for the human-facing local report formats.
///
/// Embedded as string constants rather than `Bundle.module` resources: Baton ships
/// relocatable single binaries (macOS/Linux/Windows) and uses no SwiftPM resources,
/// so bundle-path lookup would be fragile. Only user *overrides* are read from disk.
///
/// Rendered with `Template.Options(lstripBlocks: true, trimBlocks: true)`, so a block
/// tag alone on a line contributes no output and each block is prefixed with a blank
/// line — see `ReportTemplating`.
enum DefaultTemplates {
    /// The `markdown` report. Reproduces the built-in rendering's structure: an H1,
    /// then a `## ⚠️ scope / review` block per failed task and a `## scope / review`
    /// block per result, each finding as `- <badge> **<title>** (<location>)` + body.
    static let markdown = """
    # Baton review
    {% if not run.has_findings and not run.has_failures %}

    No findings. ✅
    {% endif %}
    {% for f in run.failures %}

    ## ⚠️ {{ f.scope_display }} / {{ f.review }}

    {{ f.error_message }}
    {% endfor %}
    {% for r in run.results %}

    ## {{ r.scope_display }} / {{ r.review }}
    {% for fd in r.findings %}

    - {{ fd.badge }} **{{ fd.title }}** (`{{ fd.location }}`)

      {{ fd.body }}
    {% endfor %}
    {% endfor %}
    """

    /// The rolling `learn` pull-request body: proposed review-setup edits per scope.
    static let learnPRBody = """
    ## Baton learn

    Proposed edits to Baton's review setup based on recent review signal.
    {% for p in learn.proposals %}

    ### `{{ p.scope_display }}`

    {{ p.signal_volume }} thread(s), {{ p.relax }} relax / {{ p.reinforce }} reinforce candidate(s)
    {% for e in p.edits %}
    - `{{ e.path }}`{{ e.summary_suffix }}
    {% endfor %}
    {% endfor %}
    {% if not learn.has_proposals %}

    _No setup edits proposed this run._
    {% endif %}
    """
}
