///|
pub(all) enum PullUnitCategory {
  Incoming
  PreservedLocal
  Converged
  Conflicted
  SkippedSuggestion
  SkippedUnsupported
} derive(Eq, @debug.Debug)

///|
pub(all) struct PullUnitReport {
  category : PullUnitCategory
  description : String
} derive(Eq, @debug.Debug)

///|
pub(all) struct PullPlan {
  source : String
  baseline : @pumd.DesiredDocument
  units : Array[PullUnitReport]
  incoming : Int
  preserved_local : Int
  converged : Int
  conflicted : Int
  skipped : Int
} derive(@debug.Debug)

///|
pub(all) enum PullReconcileError {
  InvalidLocalSource(String)
  AmbiguousAlignment(String)
  CanonicalSerialization(String)
} derive(Eq, @debug.Debug)

///|
pub fn PullReconcileError::user_message(self : PullReconcileError) -> String {
  match self {
    InvalidLocalSource(message) => "local Markdown cannot be patched safely: " + message
    AmbiguousAlignment(message) => "Google Docs content cannot be aligned safely: " + message
    CanonicalSerialization(message) => "canonical Markdown serialization failed: " + message
  }
}

///|
priv struct PullSourcePatch { start : Int; end : Int; replacement : String }

///|
priv struct PullSemanticMatch { base : Int; changed : Int }

///|
fn pull_newline(source : String) -> String {
  if source.contains("\r\n") { "\r\n" } else { "\n" }
}

///|
fn pull_slice(source : String, start : Int, end : Int) -> String {
  let output = StringBuilder::new()
  let mut index = 0
  for char in source {
    if index >= start && index < end { output.write_char(char) }
    index = index + 1
  }
  output.to_string()
}

///|
fn pull_trailing_newlines(source : String, newline : String) -> String {
  let mut remaining = source
  let mut count = 0
  while remaining.has_suffix(newline) {
    count = count + 1
    remaining = pull_slice(remaining, 0, remaining.length() - newline.length())
  }
  let output = StringBuilder::new()
  for index = 0; index < count; index = index + 1 {
    output.write_string(newline)
  }
  output.to_string()
}

///|
fn apply_pull_patches(source : String, patches : Array[PullSourcePatch]) -> String {
  patches.sort_by(fn(a, b) { b.start - a.start })
  let mut result = source
  for patch in patches {
    result = pull_slice(result, 0, patch.start) + patch.replacement +
      pull_slice(result, patch.end, result.length())
  }
  result
}

///|
fn add_pull_report(
  reports : Array[PullUnitReport],
  category : PullUnitCategory,
  description : String,
) -> Unit {
  reports.push({ category, description })
}

///|
fn semantic_sequence(
  entries : Array[RemoteSemanticEntry],
) -> Array[SourceSemanticUnit] {
  let result : Array[SourceSemanticUnit] = []
  for entry in entries {
    match entry.semantic { Some(unit) => result.push(unit); None => () }
  }
  result
}

///|
fn local_sequence(units : Array[LocalSemanticUnit]) -> Array[SourceSemanticUnit] {
  units.map(fn(unit) { unit.semantic })
}

///|
fn semantic_sequence_eq(
  left : Array[SourceSemanticUnit],
  right : Array[SourceSemanticUnit],
) -> Bool {
  if left.length() != right.length() { return false }
  for index = 0; index < left.length(); index = index + 1 {
    if left[index] != right[index] { return false }
  }
  true
}

///|
fn semantic_has_duplicates(units : Array[SourceSemanticUnit]) -> Bool {
  for index = 0; index < units.length(); index = index + 1 {
    for other = index + 1; other < units.length(); other = other + 1 {
      if units[index] == units[other] { return true }
    }
  }
  false
}

///|
fn semantic_lcs(
  base : Array[SourceSemanticUnit],
  changed : Array[SourceSemanticUnit],
) -> Array[PullSemanticMatch] {
  let lengths : Array[Array[Int]] = []
  for row = 0; row <= base.length(); row = row + 1 {
    let values : Array[Int] = []
    for column = 0; column <= changed.length(); column = column + 1 { values.push(0) }
    lengths.push(values)
  }
  for row = 1; row <= base.length(); row = row + 1 {
    for column = 1; column <= changed.length(); column = column + 1 {
      if base[row - 1] == changed[column - 1] {
        lengths[row][column] = lengths[row - 1][column - 1] + 1
      } else if lengths[row - 1][column] >= lengths[row][column - 1] {
        lengths[row][column] = lengths[row - 1][column]
      } else {
        lengths[row][column] = lengths[row][column - 1]
      }
    }
  }
  let reversed : Array[PullSemanticMatch] = []
  let mut row = base.length()
  let mut column = changed.length()
  while row > 0 && column > 0 {
    if base[row - 1] == changed[column - 1] {
      reversed.push({ base: row - 1, changed: column - 1 })
      row = row - 1
      column = column - 1
    } else if lengths[row - 1][column] >= lengths[row][column - 1] {
      row = row - 1
    } else {
      column = column - 1
    }
  }
  let result : Array[PullSemanticMatch] = []
  for index = reversed.length() - 1; index >= 0; index = index - 1 {
    result.push(reversed[index])
  }
  result
}

///|
fn pull_insertion(
  source : String,
  unit : SourceSemanticUnit,
  anchor : Int,
  newline : String,
) -> String {
  let markdown = serialize_source_semantic_unit(unit, newline~)
  if anchor == 0 {
    markdown + newline + newline
  } else if anchor == source.length() {
    (if source.has_suffix(newline) { newline } else { newline + newline }) +
      markdown + newline
  } else {
    markdown + newline + newline
  }
}

///|
fn pull_baseline(
  entries : Array[RemoteSemanticEntry],
  fallback : @pumd.DesiredDocument,
  base : Array[LocalSemanticUnit],
  newline : String,
) -> Result[@pumd.DesiredDocument, PullReconcileError] {
  let output = StringBuilder::new()
  let mut first = true
  let mut base_index = 0
  for entry in entries {
    match entry.semantic {
      Some(remote_unit) => {
        let unit = if entry.suggestions || entry.unsupported {
          if base_index < base.length() { base[base_index].semantic } else { remote_unit }
        } else {
          remote_unit
        }
        if !first { output.write_string(newline + newline) }
        first = false
        output.write_string(serialize_source_semantic_unit(unit, newline~))
        base_index = base_index + 1
      }
      _ => ()
    }
  }
  if first { return Ok(fallback) }
  match @pumd.render_markdown(output.to_string()) {
    Ok(document) => Ok(document)
    Err(_) => Err(CanonicalSerialization("generated Markdown was rejected by the renderer"))
  }
}

///|
/// Build a pure, non-mutating Pull plan. Merge Conflicts are ordinary plan
/// results with `conflicted > 0` and the exact input `source` retained.
pub fn plan_pull(
  source : String,
  baseline : @pumd.DesiredDocument,
  desired : @pumd.DesiredDocument,
  remote : RemoteContent,
) -> Result[PullPlan, PullReconcileError] {
  let base = local_semantic_units(baseline)
  let want = local_semantic_units(desired)
  let current = remote_semantic_entries(remote)
  let newline = pull_newline(source)
  let reports : Array[PullUnitReport] = []
  let patches : Array[PullSourcePatch] = []
  let mut incoming = 0
  let mut preserved_local = 0
  let mut converged = 0
  let mut conflicted = 0
  let mut skipped = 0
  let supported = current.filter(fn(entry) { entry.semantic is Some(_) })
  let base_sequence = local_sequence(base)
  let desired_sequence = local_sequence(want)
  let remote_sequence = semantic_sequence(current)
  let local_structure_changed = want.length() != base.length()
  let remote_structure_changed = supported.length() != base.length()
  if local_structure_changed {
    if !semantic_sequence_eq(remote_sequence, base_sequence) {
      return Err(AmbiguousAlignment("local and remote structural changes do not have unique common anchors"))
    }
    let changed = if want.length() > base.length() {
      want.length() - base.length()
    } else {
      base.length() - want.length()
    }
    preserved_local = changed
    for index = 0; index < changed; index = index + 1 {
      add_pull_report(reports, PreservedLocal, "local structural unit")
    }
    for entry in current {
      if entry.semantic is None {
        skipped = skipped + 1
        add_pull_report(reports, SkippedUnsupported, entry.description)
      }
    }
    let baseline_after_pull = match pull_baseline(current, baseline, base, newline) {
      Ok(document) => document
      Err(error) => return Err(error)
    }
    return Ok({
      source,
      baseline: baseline_after_pull,
      units: reports,
      incoming: 0,
      preserved_local,
      converged: 0,
      conflicted: 0,
      skipped,
    })
  }
  if remote_structure_changed {
    if !semantic_sequence_eq(desired_sequence, base_sequence) {
      return Err(AmbiguousAlignment("local edits overlap a remote structural insertion or deletion"))
    }
    if current.any(fn(entry) { entry.semantic is None }) {
      return Err(AmbiguousAlignment("unsupported remote structure prevents unique insertion or deletion alignment"))
    }
    if semantic_has_duplicates(base_sequence) || semantic_has_duplicates(remote_sequence) {
      return Err(AmbiguousAlignment("duplicate structural units do not provide unique insertion or deletion anchors"))
    }
    let matches = semantic_lcs(base_sequence, remote_sequence)
    let base_to_remote : Array[Int?] = []
    let remote_to_base : Array[Int?] = []
    for index = 0; index < base.length(); index = index + 1 { base_to_remote.push(None) }
    for index = 0; index < supported.length(); index = index + 1 { remote_to_base.push(None) }
    for pair in matches {
      base_to_remote[pair.base] = Some(pair.changed)
      remote_to_base[pair.changed] = Some(pair.base)
    }
    for base_index = 0; base_index < base.length(); base_index = base_index + 1 {
      if base_to_remote[base_index] is None {
        let range = match want[base_index].provenance {
          Some(range) => range
          None => return Err(InvalidLocalSource("deleted unit has no parser provenance"))
        }
        patches.push({ start: range.start, end: range.end, replacement: "" })
        incoming = incoming + 1
        add_pull_report(reports, Incoming, "deleted structural unit")
      }
    }
    for remote_index = 0; remote_index < supported.length(); remote_index = remote_index + 1 {
      if remote_to_base[remote_index] is None {
        let entry = supported[remote_index]
        if entry.suggestions || entry.unsupported {
          skipped = skipped + 1
          add_pull_report(
            reports,
            if entry.suggestions { SkippedSuggestion } else { SkippedUnsupported },
            entry.description,
          )
          continue
        }
        let mut anchor = source.length()
        for next = remote_index + 1; next < remote_to_base.length(); next = next + 1 {
          match remote_to_base[next] {
            Some(base_index) => {
              anchor = match want[base_index].provenance {
                Some(range) => range.start
                None => return Err(InvalidLocalSource("insertion anchor has no parser provenance"))
              }
              break
            }
            None => ()
          }
        }
        guard entry.semantic is Some(unit) else { abort("supported remote unit") }
        patches.push({
          start: anchor,
          end: anchor,
          replacement: pull_insertion(source, unit, anchor, newline),
        })
        incoming = incoming + 1
        add_pull_report(reports, Incoming, entry.description)
      }
    }
    let baseline_after_pull = match pull_baseline(current, baseline, base, newline) {
      Ok(document) => document
      Err(error) => return Err(error)
    }
    return Ok({
      source: apply_pull_patches(source, patches),
      baseline: baseline_after_pull,
      units: reports,
      incoming,
      preserved_local: 0,
      converged: 0,
      conflicted: 0,
      skipped,
    })
  }
  let has_opaque = current.any(fn(entry) { entry.semantic is None })
  if has_opaque {
    for index, entry in supported {
      guard entry.semantic is Some(remote_unit) else { continue }
      if remote_unit != base[index].semantic {
        for other = 0; other < base.length(); other = other + 1 {
          if other != index && remote_unit == base[other].semantic {
            return Err(AmbiguousAlignment("unsupported remote structure brackets a reordered unit"))
          }
        }
      }
    }
  }
  for index = 0; index < base.length(); index = index + 1 {
    let entry = supported[index]
    let remote_unit = match entry.semantic {
      Some(unit) => unit
      None => abort("filtered remote Source Semantics")
    }
    let local_changed = want[index].semantic != base[index].semantic
    let remote_changed = remote_unit != base[index].semantic
    if entry.suggestions {
      skipped = skipped + 1
      add_pull_report(reports, SkippedSuggestion, entry.description)
    } else if entry.unsupported {
      skipped = skipped + 1
      add_pull_report(reports, SkippedUnsupported, entry.description)
    } else if local_changed && remote_changed {
      if want[index].semantic == remote_unit {
        converged = converged + 1
        add_pull_report(reports, Converged, entry.description)
      } else {
        conflicted = conflicted + 1
        add_pull_report(reports, Conflicted, entry.description)
      }
    } else if local_changed {
      preserved_local = preserved_local + 1
      add_pull_report(reports, PreservedLocal, entry.description)
    } else if remote_changed {
      let range = match want[index].provenance {
        Some(range) => range
        None => return Err(InvalidLocalSource(entry.description + " has no parser provenance"))
      }
      patches.push({
        start: range.start,
        end: range.end,
        replacement: serialize_source_semantic_unit(remote_unit, newline~) +
          pull_trailing_newlines(
            pull_slice(source, range.start, range.end),
            newline,
          ),
      })
      incoming = incoming + 1
      add_pull_report(reports, Incoming, entry.description)
    }
  }
  for entry in current {
    if entry.semantic is None {
      skipped = skipped + 1
      add_pull_report(reports, SkippedUnsupported, entry.description)
    }
  }
  let next_source = if conflicted > 0 { source } else { apply_pull_patches(source, patches) }
  let next_baseline = if conflicted > 0 {
    baseline
  } else {
    match pull_baseline(current, baseline, base, newline) {
      Ok(document) => document
      Err(error) => return Err(error)
    }
  }
  Ok({
    source: next_source,
    baseline: next_baseline,
    units: reports,
    incoming,
    preserved_local,
    converged,
    conflicted,
    skipped,
  })
}
