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
priv struct PullStructuralEdit {
  base_start : Int
  base_end : Int
  changed_start : Int
  changed_end : Int
}

///|
fn pull_newline(source : String) -> String {
  if source.contains("\r\n") { "\r\n" } else { "\n" }
}

///|
fn pull_codepoint_length(source : String) -> Int {
  let mut length = 0
  for _ in source { length = length + 1 }
  length
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
    remaining = pull_slice(
      remaining,
      0,
      pull_codepoint_length(remaining) - pull_codepoint_length(newline),
    )
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
      pull_slice(result, patch.end, pull_codepoint_length(result))
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
fn semantic_baseline_anchors_unique(
  base : Array[SourceSemanticUnit],
  changed : Array[SourceSemanticUnit],
) -> Bool {
  for base_unit in base {
    let mut occurrences = 0
    for changed_unit in changed {
      if base_unit == changed_unit { occurrences = occurrences + 1 }
    }
    if occurrences > 1 { return false }
  }
  true
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
fn pull_structural_edits(
  base_length : Int,
  changed_length : Int,
  matches : Array[PullSemanticMatch],
) -> Array[PullStructuralEdit] {
  let edits : Array[PullStructuralEdit] = []
  let mut previous_base = -1
  let mut previous_changed = -1
  for match_ in matches {
    if match_.base > previous_base + 1 || match_.changed > previous_changed + 1 {
      edits.push({
        base_start: previous_base + 1,
        base_end: match_.base,
        changed_start: previous_changed + 1,
        changed_end: match_.changed,
      })
    }
    previous_base = match_.base
    previous_changed = match_.changed
  }
  if previous_base + 1 < base_length || previous_changed + 1 < changed_length {
    edits.push({
      base_start: previous_base + 1,
      base_end: base_length,
      changed_start: previous_changed + 1,
      changed_end: changed_length,
    })
  }
  edits
}

///|
fn pull_structural_edits_overlap(
  left : PullStructuralEdit,
  right : PullStructuralEdit,
) -> Bool {
  let left_insertion = left.base_start == left.base_end
  let right_insertion = right.base_start == right.base_end
  if left_insertion && right_insertion {
    return left.base_start == right.base_start
  }
  if left_insertion {
    return left.base_start > right.base_start && left.base_start < right.base_end
  }
  if right_insertion {
    return right.base_start > left.base_start && right.base_start < left.base_end
  }
  left.base_start < right.base_end && right.base_start < left.base_end
}

///|
fn pull_structural_edits_converge(
  local_edit : PullStructuralEdit,
  remote : PullStructuralEdit,
  desired : Array[SourceSemanticUnit],
  current : Array[SourceSemanticUnit],
) -> Bool {
  if local_edit.base_start != remote.base_start ||
    local_edit.base_end != remote.base_end {
    return false
  }
  let local_length = local_edit.changed_end - local_edit.changed_start
  let remote_length = remote.changed_end - remote.changed_start
  if local_length != remote_length { return false }
  for offset = 0; offset < local_length; offset = offset + 1 {
    if desired[local_edit.changed_start + offset] != current[remote.changed_start + offset] {
      return false
    }
  }
  true
}

///|
fn pull_serialized_units(
  units : Array[SourceSemanticUnit],
  start : Int,
  end : Int,
  newline : String,
) -> String {
  let output = StringBuilder::new()
  for index = start; index < end; index = index + 1 {
    if index > start { output.write_string(newline + newline) }
    output.write_string(serialize_source_semantic_unit(units[index], newline~))
  }
  output.to_string()
}

///|
fn pull_edit_size(edit : PullStructuralEdit) -> Int {
  let removed = edit.base_end - edit.base_start
  let added = edit.changed_end - edit.changed_start
  if removed > added { removed } else { added }
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
  } else if anchor == pull_codepoint_length(source) {
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
  let units : Array[SourceSemanticUnit] = []
  let mut base_index = 0
  for entry in entries {
    match entry.semantic {
      Some(remote_unit) => {
        let unit = if entry.suggestions || entry.unsupported {
          if base_index < base.length() { base[base_index].semantic } else { remote_unit }
        } else {
          remote_unit
        }
        units.push(unit)
        base_index = base_index + 1
      }
      _ => ()
    }
  }
  pull_baseline_units(units, fallback, newline)
}

///|
fn pull_baseline_units(
  units : Array[SourceSemanticUnit],
  fallback : @pumd.DesiredDocument,
  newline : String,
) -> Result[@pumd.DesiredDocument, PullReconcileError] {
  if units.is_empty() { return Ok(fallback) }
  let output = StringBuilder::new()
  for index, unit in units {
    if index > 0 { output.write_string(newline + newline) }
    output.write_string(serialize_source_semantic_unit(unit, newline~))
  }
  match @pumd.render_markdown(output.to_string()) {
    Ok(document) => {
      if !semantic_sequence_eq(local_sequence(local_semantic_units(document)), units) {
        Err(CanonicalSerialization("generated Markdown changed Source Semantics"))
      } else {
        Ok(document)
      }
    }
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
  if local_structure_changed && remote_structure_changed {
    if current.any(fn(entry) { entry.semantic is None }) {
      return Err(AmbiguousAlignment("unsupported remote structure prevents unique simultaneous structural alignment"))
    }
    if semantic_has_duplicates(base_sequence) ||
      !semantic_baseline_anchors_unique(base_sequence, desired_sequence) ||
      !semantic_baseline_anchors_unique(base_sequence, remote_sequence) {
      return Err(AmbiguousAlignment("duplicate structural units do not provide unique simultaneous structural anchors"))
    }
    let local_matches = semantic_lcs(base_sequence, desired_sequence)
    let remote_matches = semantic_lcs(base_sequence, remote_sequence)
    let local_edits = pull_structural_edits(
      base.length(),
      want.length(),
      local_matches,
    )
    let remote_edits = pull_structural_edits(
      base.length(),
      supported.length(),
      remote_matches,
    )
    let base_to_desired : Array[Int?] = []
    for index = 0; index < base.length(); index = index + 1 {
      base_to_desired.push(None)
    }
    for pair in local_matches {
      base_to_desired[pair.base] = Some(pair.changed)
    }
    let local_converged : Array[Bool] = []
    for _ in local_edits { local_converged.push(false) }
    for remote_edit in remote_edits {
      let mut overlap_index : Int? = None
      let mut multiple_overlaps = false
      for local_index, local_edit in local_edits {
        if pull_structural_edits_overlap(local_edit, remote_edit) {
          match overlap_index {
            None => overlap_index = Some(local_index)
            Some(_) => multiple_overlaps = true
          }
        }
      }
      match overlap_index {
        Some(local_index) if !multiple_overlaps &&
          pull_structural_edits_converge(
            local_edits[local_index],
            remote_edit,
            desired_sequence,
            remote_sequence,
          ) => {
          local_converged[local_index] = true
          converged = converged + pull_edit_size(remote_edit)
          add_pull_report(reports, Converged, "identical local and remote structural edit")
          continue
        }
        _ => ()
      }
      if overlap_index is Some(_) {
        conflicted = conflicted + 1
        add_pull_report(reports, Conflicted, "overlapping local and remote structural edits")
        continue
      }
      let replacement = pull_serialized_units(
        remote_sequence,
        remote_edit.changed_start,
        remote_edit.changed_end,
        newline,
      )
      if remote_edit.base_start == remote_edit.base_end {
        let mut anchor = pull_codepoint_length(source)
        for base_index = remote_edit.base_start; base_index < base.length(); base_index = base_index + 1 {
          match base_to_desired[base_index] {
            Some(desired_index) => {
              anchor = match want[desired_index].provenance {
                Some(range) => range.start
                None => return Err(InvalidLocalSource("insertion anchor has no parser provenance"))
              }
              break
            }
            None => ()
          }
        }
        let insertion = if anchor == 0 {
          replacement + newline + newline
        } else if anchor == pull_codepoint_length(source) {
          (if source.has_suffix(newline) { newline } else { newline + newline }) +
            replacement + newline
        } else {
          replacement + newline + newline
        }
        patches.push({ start: anchor, end: anchor, replacement: insertion })
      } else {
        let first_desired = match base_to_desired[remote_edit.base_start] {
          Some(index) => index
          None => return Err(AmbiguousAlignment("remote structural edit lost its local baseline anchor"))
        }
        let last_desired = match base_to_desired[remote_edit.base_end - 1] {
          Some(index) => index
          None => return Err(AmbiguousAlignment("remote structural edit lost its local baseline anchor"))
        }
        let first_range = match want[first_desired].provenance {
          Some(range) => range
          None => return Err(InvalidLocalSource("structural edit anchor has no parser provenance"))
        }
        let last_range = match want[last_desired].provenance {
          Some(range) => range
          None => return Err(InvalidLocalSource("structural edit anchor has no parser provenance"))
        }
        let local_text = pull_slice(source, first_range.start, last_range.end)
        patches.push({
          start: first_range.start,
          end: last_range.end,
          replacement: if replacement == "" { "" } else {
            replacement + pull_trailing_newlines(local_text, newline)
          },
        })
      }
      incoming = incoming + pull_edit_size(remote_edit)
      add_pull_report(reports, Incoming, "remote structural edit")
    }
    for local_index, local_edit in local_edits {
      if !local_converged[local_index] {
        preserved_local = preserved_local + pull_edit_size(local_edit)
        add_pull_report(reports, PreservedLocal, "local structural edit")
      }
    }
    let baseline_after_pull = if conflicted > 0 { baseline } else {
      match pull_baseline_units(remote_sequence, baseline, newline) {
        Ok(document) => document
        Err(error) => return Err(error)
      }
    }
    return Ok({
      source: if conflicted > 0 { source } else { apply_pull_patches(source, patches) },
      baseline: baseline_after_pull,
      units: reports,
      incoming,
      preserved_local,
      converged,
      conflicted,
      skipped,
    })
  }
  if local_structure_changed {
    if semantic_has_duplicates(base_sequence) || semantic_has_duplicates(desired_sequence) {
      return Err(AmbiguousAlignment("duplicate local structural units do not provide unique anchors"))
    }
    let local_matches = semantic_lcs(base_sequence, desired_sequence)
    let base_to_desired : Array[Int?] = []
    let desired_to_base : Array[Int?] = []
    for index = 0; index < base.length(); index = index + 1 { base_to_desired.push(None) }
    for index = 0; index < want.length(); index = index + 1 { desired_to_base.push(None) }
    for pair in local_matches {
      base_to_desired[pair.base] = Some(pair.changed)
      desired_to_base[pair.changed] = Some(pair.base)
    }
    for desired_index = 0; desired_index < want.length(); desired_index = desired_index + 1 {
      if desired_to_base[desired_index] is None {
        preserved_local = preserved_local + 1
        add_pull_report(reports, PreservedLocal, "local inserted structural unit")
      }
    }
    for base_index = 0; base_index < base.length(); base_index = base_index + 1 {
      let entry = supported[base_index]
      guard entry.semantic is Some(remote_unit) else { abort("supported remote unit") }
      let remote_changed = remote_unit != base[base_index].semantic
      match base_to_desired[base_index] {
        None => {
          preserved_local = preserved_local + 1
          add_pull_report(reports, PreservedLocal, "local deleted structural unit")
          if remote_changed {
            conflicted = conflicted + 1
            add_pull_report(reports, Conflicted, entry.description)
          }
        }
        Some(_) if entry.suggestions || entry.unsupported => {
          skipped = skipped + 1
          add_pull_report(
            reports,
            if entry.suggestions { SkippedSuggestion } else { SkippedUnsupported },
            entry.description,
          )
        }
        Some(desired_index) if remote_changed => {
          if want[desired_index].remote_rewrite_lossy {
            conflicted = conflicted + 1
            add_pull_report(reports, Conflicted, entry.description)
          } else {
            let range = match want[desired_index].provenance {
              Some(range) => range
              None => return Err(InvalidLocalSource("remote edit anchor has no parser provenance"))
            }
            patches.push({
              start: range.start,
              end: range.end,
              replacement: serialize_source_semantic_unit(remote_unit, newline~) +
                pull_trailing_newlines(pull_slice(source, range.start, range.end), newline),
            })
            incoming = incoming + 1
            add_pull_report(reports, Incoming, entry.description)
          }
        }
        Some(_) => ()
      }
    }
    for entry in current {
      if entry.semantic is None {
        skipped = skipped + 1
        add_pull_report(reports, SkippedUnsupported, entry.description)
      }
    }
    let baseline_after_pull = if conflicted > 0 { baseline } else {
      match pull_baseline(current, baseline, base, newline) {
        Ok(document) => document
        Err(error) => return Err(error)
      }
    }
    return Ok({
      source: if conflicted > 0 { source } else { apply_pull_patches(source, patches) },
      baseline: baseline_after_pull,
      units: reports,
      incoming,
      preserved_local,
      converged: 0,
      conflicted,
      skipped,
    })
  }
  if remote_structure_changed {
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
      let local_changed = want[base_index].semantic != base[base_index].semantic
      if base_to_remote[base_index] is None {
        if local_changed {
          conflicted = conflicted + 1
          add_pull_report(reports, Conflicted, "remotely deleted structural unit")
        } else {
          let range = match want[base_index].provenance {
            Some(range) => range
            None => return Err(InvalidLocalSource("deleted unit has no parser provenance"))
          }
          patches.push({ start: range.start, end: range.end, replacement: "" })
          incoming = incoming + 1
          add_pull_report(reports, Incoming, "deleted structural unit")
        }
      } else if local_changed {
        preserved_local = preserved_local + 1
        add_pull_report(reports, PreservedLocal, "locally edited structural unit")
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
        let mut anchor = pull_codepoint_length(source)
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
    let baseline_units : Array[SourceSemanticUnit] = []
    for remote_index, entry in supported {
      guard entry.semantic is Some(remote_unit) else { continue }
      match remote_to_base[remote_index] {
        Some(base_index) if entry.suggestions || entry.unsupported =>
          baseline_units.push(base[base_index].semantic)
        Some(_) => baseline_units.push(remote_unit)
        None if entry.suggestions || entry.unsupported => ()
        None => baseline_units.push(remote_unit)
      }
    }
    let baseline_after_pull = if conflicted > 0 { baseline } else {
      match pull_baseline_units(baseline_units, baseline, newline) {
        Ok(document) => document
        Err(error) => return Err(error)
      }
    }
    return Ok({
      source: if conflicted > 0 { source } else { apply_pull_patches(source, patches) },
      baseline: baseline_after_pull,
      units: reports,
      incoming,
      preserved_local,
      converged: 0,
      conflicted,
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
      if want[index].remote_rewrite_lossy {
        conflicted = conflicted + 1
        add_pull_report(reports, Conflicted, entry.description)
        continue
      }
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
