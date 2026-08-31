// ProwlShared/WorkflowDocumentParser.swift
// YAML → WorkflowDefinition with positioned diagnostics. Structural rules only (keys, types,
// shapes); cross-reference rules live in WorkflowValidator.

import Foundation
import Yams

nonisolated public struct WorkflowParseResult: Equatable, Sendable {
  /// Present only when no error diagnostic was produced.
  public let definition: WorkflowDefinition?
  public let diagnostics: [WorkflowDiagnostic]
}

nonisolated public enum WorkflowDocumentParser {
  public static func parse(_ yaml: String) -> WorkflowParseResult {
    let collector = DiagnosticCollector()
    let root: Node?
    do {
      root = try Yams.compose(yaml: yaml)
    } catch let error as YamlError {
      collector.error("yaml_syntax", error.problemDescription, at: error.problemLocation)
      return WorkflowParseResult(definition: nil, diagnostics: collector.diagnostics)
    } catch {
      collector.error("yaml_syntax", error.localizedDescription)
      return WorkflowParseResult(definition: nil, diagnostics: collector.diagnostics)
    }
    guard let root, case .mapping = root,
      let mapping = MappingReader(node: root, collector: collector, path: "document")
    else {
      collector.error("document_not_mapping", "The workflow file must be a YAML mapping.", at: root?.sourceLocation)
      return WorkflowParseResult(definition: nil, diagnostics: collector.diagnostics)
    }
    let definition = parseDocument(mapping)
    let diagnostics = collector.diagnostics
    return WorkflowParseResult(definition: diagnostics.hasErrors ? nil : definition, diagnostics: diagnostics)
  }

  // MARK: - Document

  private static func parseDocument(_ document: MappingReader) -> WorkflowDefinition? {
    document.checkKeys(["schema", "id", "name", "description", "icon", "inputs", "roles", "steps"])
    let schema = document.requiredString("schema")
    if let schema, schema != WorkflowSchema.identifier {
      document.collector.error(
        "unsupported_schema",
        "Unsupported schema '\(schema)'; expected '\(WorkflowSchema.identifier)'.",
        at: document.location(of: "schema")
      )
    }
    let id = document.requiredString("id")
    let name = document.requiredString("name")
    let inputs = document.mapping("inputs").map(parseInputs) ?? []
    let roles = document.mapping("roles").map(parseRoles) ?? []
    let steps =
      document.requiredSequence("steps").map { parseSteps($0, insideRepeat: false, at: document.location) } ?? []
    guard let id, let name else { return nil }
    return WorkflowDefinition(
      id: id,
      name: name,
      description: document.string("description"),
      icon: document.string("icon"),
      inputs: inputs,
      roles: roles,
      steps: steps
    )
  }

  // MARK: - Inputs

  private static func parseInputs(_ inputs: MappingReader) -> [WorkflowInputDefinition] {
    inputs.entries().compactMap { name, node in
      guard let input = MappingReader(node: node, collector: inputs.collector, path: "inputs.\(name)") else {
        return nil
      }
      return parseInput(name: name, input)
    }
  }

  private static func parseInput(name: String, _ input: MappingReader) -> WorkflowInputDefinition? {
    input.checkKeys(["type", "default", "min", "max", "prompt", "values"])
    guard let type = input.requiredEnum("type", WorkflowInputType.self) else { return nil }
    let defaultValue: WorkflowScalar? =
      switch type {
      case .integer: input.int("default").map(WorkflowScalar.integer)
      case .string, .enum: input.string("default").map(WorkflowScalar.string)
      }
    for key in ["min", "max"] where type != .integer && input.has(key) {
      input.collector.error(
        "key_requires_type", "'\(key)' applies to integer inputs only.", at: input.location(of: key))
    }
    if type != .enum, input.has("values") {
      input.collector.error(
        "key_requires_type", "'values' applies to enum inputs only.", at: input.location(of: "values"))
    }
    if type == .enum, !input.has("values") {
      input.collector.error("missing_key", "Enum input '\(name)' needs 'values'.", at: input.location)
    }
    return WorkflowInputDefinition(
      name: name,
      type: type,
      defaultValue: defaultValue,
      prompt: input.string("prompt"),
      minimum: input.int("min"),
      maximum: input.int("max"),
      values: input.stringList("values") ?? [],
      location: input.location
    )
  }

  // MARK: - Roles

  private static func parseRoles(_ roles: MappingReader) -> [WorkflowRoleDefinition] {
    roles.entries().compactMap { name, node in
      guard let role = MappingReader(node: node, collector: roles.collector, path: "roles.\(name)") else {
        return nil
      }
      return parseRole(name: name, role)
    }
  }

  private static let launchOnlyKeys = ["kind", "agents", "suggest", "bind", "placement", "direction", "background"]

  private static func parseRole(name: String, _ role: MappingReader) -> WorkflowRoleDefinition? {
    role.checkKeys(["source"] + launchOnlyKeys)
    guard let source = role.requiredEnum("source", WorkflowRoleSource.self) else { return nil }
    guard source == .launch else {
      for key in launchOnlyKeys where role.has(key) {
        role.collector.error(
          "key_requires_launch", "'\(key)' applies to launch roles only.", at: role.location(of: key))
      }
      return WorkflowRoleDefinition(name: name, source: source, location: role.location)
    }
    if let kind = role.string("kind"), WorkflowRoleKind(rawValue: kind) == nil {
      let message =
        kind == "headless"
        ? "'kind: headless' is reserved for a later version; only 'interactive' is accepted."
        : "Unknown kind '\(kind)'; only 'interactive' is accepted."
      role.collector.error("reserved_kind", message, at: role.location(of: "kind"))
    }
    var suggest: WorkflowProfileSuggestion?
    if let suggestion = role.mapping("suggest") {
      suggestion.checkKeys(["agent", "model", "reasoning_effort", "execution_mode"])
      suggest = WorkflowProfileSuggestion(
        agent: suggestion.string("agent"),
        model: suggestion.string("model"),
        reasoningEffort: suggestion.string("reasoning_effort"),
        executionMode: suggestion.string("execution_mode")
      )
    }
    let placement = role.enumValue("placement", WorkflowPlacement.self) ?? .split
    if placement == .tab, role.has("direction") {
      role.collector.warning(
        "direction_ignored", "'direction' applies to split placement only.", at: role.location(of: "direction"))
    }
    return WorkflowRoleDefinition(
      name: name,
      source: source,
      launch: WorkflowLaunchRequirements(
        agents: role.stringList("agents"),
        suggest: suggest,
        bind: role.enumValue("bind", WorkflowBindMode.self) ?? .ask,
        placement: placement,
        direction: role.enumValue("direction", WorkflowSplitDirection.self) ?? .right,
        background: role.bool("background") ?? false
      ),
      location: role.location
    )
  }

  // MARK: - Steps

  private static let verbKeys = ["message", "launch", "action", "notify", "close", "repeat"]

  private static func parseSteps(
    _ steps: SequenceReader, insideRepeat: Bool, at location: WorkflowSourceLocation?
  ) -> [WorkflowStepDefinition] {
    if steps.isEmpty {
      steps.collector.error("steps_empty", "'\(steps.path)' needs at least one step.", at: location)
    }
    return steps.mappings().compactMap { parseStep($0, insideRepeat: insideRepeat) }
  }

  private static func parseStep(_ step: MappingReader, insideRepeat: Bool) -> WorkflowStepDefinition? {
    let verbs = verbKeys.filter(step.has)
    guard verbs.count == 1, let verb = verbs.first else {
      step.collector.error(
        "step_verb",
        verbs.isEmpty
          ? "A step needs exactly one verb (\(verbKeys.joined(separator: ", ")))."
          : "A step has exactly one verb; found \(verbs.joined(separator: ", ")).",
        at: step.location
      )
      return nil
    }
    let idNode = step.requiredString("id")
    let action = parseAction(verb: verb, step, insideRepeat: insideRepeat)
    guard let id = idNode, let action else { return nil }
    return WorkflowStepDefinition(id: id, title: step.string("title"), action: action, location: step.location)
  }

  private static func parseAction(verb: String, _ step: MappingReader, insideRepeat: Bool) -> WorkflowStepAction? {
    switch verb {
    case "message": return parseMessage(step)
    case "launch": return parseLaunch(step, insideRepeat: insideRepeat)
    case "action": return parseNativeAction(step)
    case "notify":
      step.checkKeys(["id", "title", "notify", "expect"])
      rejectExpect(step)
      return step.requiredString("notify").map(WorkflowStepAction.notify)
    case "close":
      step.checkKeys(["id", "title", "close", "expect"])
      rejectExpect(step)
      return step.requiredString("close").map { WorkflowStepAction.close(role: $0) }
    case "repeat": return parseRepeat(step, insideRepeat: insideRepeat)
    default: return nil
    }
  }

  private static func rejectExpect(_ step: MappingReader) {
    guard step.has("expect") else { return }
    step.collector.error(
      "expect_not_allowed",
      "'expect' is valid on message and launch steps only; native actions return typed outputs synchronously.",
      at: step.location(of: "expect")
    )
  }

  private static func parseMessage(_ step: MappingReader) -> WorkflowStepAction? {
    step.checkKeys(["id", "title", "message", "text", "instruction", "expect"])
    let role = step.requiredString("message")
    let text = step.string("text")
    let instruction = step.string("instruction")
    let content: WorkflowMessageContent?
    switch (text, instruction) {
    case (let text?, nil): content = .text(text)
    case (nil, let instruction?): content = .instruction(instruction)
    default:
      step.collector.error(
        "message_content", "A message step needs exactly one of 'text' or 'instruction'.", at: step.location)
      content = nil
    }
    let expect = parseExpect(step)
    guard let role, let content else { return nil }
    return .message(role: role, content: content, expect: expect)
  }

  private static func parseLaunch(_ step: MappingReader, insideRepeat: Bool) -> WorkflowStepAction? {
    step.checkKeys(["id", "title", "launch", "prompt", "skill", "expect"])
    if insideRepeat {
      step.collector.error("launch_inside_repeat", "'launch' is not allowed inside 'repeat'.", at: step.location)
    }
    let role = step.requiredString("launch")
    let prompt = step.requiredString("prompt")
    let expect = parseExpect(step)
    guard let role, let prompt else { return nil }
    return .launch(role: role, prompt: prompt, skill: step.string("skill"), expect: expect)
  }

  private static func parseNativeAction(_ step: MappingReader) -> WorkflowStepAction? {
    step.checkKeys(["id", "title", "action", "with", "expect"])
    rejectExpect(step)
    guard let id = step.requiredString("action") else { return nil }
    var inputs: [String: String] = [:]
    if let with = step.mapping("with") {
      for (key, node) in with.entries() {
        if let value = with.scalarText(node, key: key) {
          inputs[key] = value
        }
      }
    }
    return .action(id: id, inputs: inputs)
  }

  private static func parseRepeat(_ step: MappingReader, insideRepeat: Bool) -> WorkflowStepAction? {
    step.checkKeys(["id", "title", "repeat", "steps"])
    rejectExpect(step)
    if insideRepeat {
      step.collector.error("nested_repeat", "'repeat' cannot be nested.", at: step.location)
    }
    guard let body = MappingReader(node: step.node(for: "repeat"), collector: step.collector, path: "repeat") else {
      return nil
    }
    body.checkKeys(["max", "until"])
    let max = parseRepeatBound(body)
    let until = body.string("until").flatMap { parseUntil($0, at: body.location(of: "until"), body.collector) }
    let steps = step.requiredSequence("steps").map { parseSteps($0, insideRepeat: true, at: step.location) }
    guard let max, let steps else { return nil }
    return .repeat(max: max, until: until, steps: steps)
  }

  private static func parseRepeatBound(_ body: MappingReader) -> WorkflowRepeatBound? {
    guard let node = body.node(for: "max") else {
      body.collector.error("missing_key", "'repeat' needs 'max'.", at: body.location)
      return nil
    }
    if node.isPlainScalar, let value = node.int {
      return .literal(value)
    }
    if let text = node.string, WorkflowTemplate.containsReference(text) {
      return .template(text)
    }
    body.collector.error(
      "repeat_max",
      "'max' must be a positive integer literal or a template of one integer input.",
      at: body.location(of: "max")
    )
    return nil
  }

  private static func parseUntil(
    _ text: String, at location: WorkflowSourceLocation?, _ collector: DiagnosticCollector
  ) -> WorkflowUntilCondition? {
    // The same grammar as the published schema's `until` pattern: slug tokens only.
    let pattern =
      /^outputs\.([a-z0-9][a-z0-9_-]{0,63})\.verdict\s*(?:==\s*([a-z0-9][a-z0-9_-]{0,63})|in\s*\[([^\]]*)\])$/
    guard let match = text.wholeMatch(of: pattern) else {
      collector.error(
        "until_syntax",
        "'until' must be 'outputs.<name>.verdict == <value>' or 'outputs.<name>.verdict in [<values>]'.",
        at: location
      )
      return nil
    }
    let output = String(match.1)
    let values: [String]
    if let single = match.2 {
      values = [String(single)]
    } else {
      values = (match.3 ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    }
    return WorkflowUntilCondition(output: output, values: values, location: location)
  }

  // MARK: - Expect

  private static func parseExpect(_ step: MappingReader) -> WorkflowExpectation? {
    guard let expect = MappingReader(node: step.node(for: "expect"), collector: step.collector, path: "expect") else {
      return nil
    }
    expect.checkKeys(["output", "format", "sections", "verdict", "timeout", "on_timeout", "strict"])
    let timeout = expect.string("timeout").flatMap { text -> Int? in
      guard let seconds = parseDuration(text) else {
        expect.collector.error(
          "timeout_syntax", "'timeout' must be a duration like 90s, 10m, or 2h.", at: expect.location(of: "timeout"))
        return nil
      }
      return seconds
    }
    let onTimeout = expect.enumValue("on_timeout", WorkflowTimeoutPolicy.self)
    if onTimeout != nil, !expect.has("timeout") {
      expect.collector.error(
        "on_timeout_requires_timeout", "'on_timeout' applies only together with 'timeout'.",
        at: expect.location(of: "on_timeout"))
    }
    return WorkflowExpectation(
      output: expect.string("output"),
      format: expect.enumValue("format", WorkflowOutputFormat.self) ?? .markdown,
      sections: expect.stringList("sections") ?? [],
      verdict: expect.stringList("verdict"),
      timeoutSeconds: timeout,
      onTimeout: onTimeout,
      strict: expect.bool("strict") ?? false,
      location: expect.location
    )
  }

  public static func parseDuration(_ text: String) -> Int? {
    guard let match = text.wholeMatch(of: /^(\d+)\s*([smh])$/),
      let amount = Int(match.1)
    else { return nil }
    let factor =
      switch match.2 {
      case "s": 1
      case "m": 60
      default: 3600
      }
    let (seconds, overflow) = amount.multipliedReportingOverflow(by: factor)
    return overflow ? nil : seconds
  }
}

// MARK: - Readers

nonisolated final class DiagnosticCollector {
  private(set) var diagnostics: [WorkflowDiagnostic] = []

  func error(_ code: String, _ message: String, at location: WorkflowSourceLocation? = nil) {
    diagnostics.append(.error(code, message, at: location))
  }

  func warning(_ code: String, _ message: String, at location: WorkflowSourceLocation? = nil) {
    diagnostics.append(.warning(code, message, at: location))
  }
}

nonisolated extension Node {
  var sourceLocation: WorkflowSourceLocation? {
    mark.map { WorkflowSourceLocation(line: $0.line, column: $0.column) }
  }

  /// Unquoted scalars resolve to YAML's core types; quoted ones are always strings.
  var isPlainScalar: Bool {
    guard case .scalar(let scalar) = self else { return false }
    return scalar.style == .plain
  }
}

nonisolated extension YamlError {
  var problemDescription: String {
    switch self {
    case .scanner(_, let problem, _, _), .parser(_, let problem, _, _), .composer(_, let problem, _, _):
      return problem
    case .reader(let problem, _, _, _), .writer(let problem):
      return problem
    default:
      return localizedDescription
    }
  }

  var problemLocation: WorkflowSourceLocation? {
    switch self {
    case .scanner(_, _, let mark, _), .parser(_, _, let mark, _), .composer(_, _, let mark, _):
      return WorkflowSourceLocation(line: mark.line, column: mark.column)
    default:
      return nil
    }
  }
}

/// Reads one YAML mapping, reporting unknown keys and type mismatches with positions.
nonisolated struct MappingReader {
  let mapping: Node.Mapping
  let collector: DiagnosticCollector
  let path: String
  let location: WorkflowSourceLocation?

  init?(node: Node?, collector: DiagnosticCollector, path: String) {
    guard let node else { return nil }
    guard case .mapping(let mapping) = node else {
      collector.error("type_mismatch", "'\(path)' must be a mapping.", at: node.sourceLocation)
      return nil
    }
    self.mapping = mapping
    self.collector = collector
    self.path = path
    location = node.sourceLocation
  }

  func has(_ key: String) -> Bool { mapping[key] != nil }

  func node(for key: String) -> Node? { mapping[key] }

  func location(of key: String) -> WorkflowSourceLocation? {
    mapping[key]?.sourceLocation ?? location
  }

  /// Key/value pairs in document order; non-string keys are errors.
  func entries() -> [(String, Node)] {
    mapping.compactMap { key, value in
      guard let name = key.string else {
        collector.error("type_mismatch", "Keys in '\(path)' must be strings.", at: key.sourceLocation)
        return nil
      }
      return (name, value)
    }
  }

  func checkKeys(_ allowed: [String]) {
    for (key, node) in mapping where key.string.map({ !allowed.contains($0) }) ?? false {
      collector.error(
        "unknown_key", "Unknown key '\(key.string ?? "?")' in \(path).",
        at: key.sourceLocation ?? node.sourceLocation)
    }
  }

  /// A string-valued field. Unquoted scalars that YAML resolves to a number, boolean, or null are
  /// type errors so that `id: 1` cannot masquerade as the string "1" (quote it to keep text).
  func string(_ key: String) -> String? {
    guard let node = mapping[key] else { return nil }
    return strictText(node, key: key)
  }

  func strictText(_ node: Node, key: String) -> String? {
    if node.isPlainScalar, node.int != nil || node.bool != nil || node.float != nil {
      collector.error(
        "type_mismatch", "'\(key)' in \(path) must be a string; quote the value to keep it as text.",
        at: node.sourceLocation)
      return nil
    }
    return scalarText(node, key: key)
  }

  func requiredString(_ key: String) -> String? {
    guard let value = string(key) else {
      if !has(key) {
        collector.error("missing_key", "'\(path)' needs '\(key)'.", at: location)
      }
      return nil
    }
    return value
  }

  /// A scalar's source text; sequences, mappings, and nulls are type errors.
  func scalarText(_ node: Node, key: String) -> String? {
    guard case .scalar(let scalar) = node, !(node.isPlainScalar && node.null != nil) else {
      collector.error("type_mismatch", "'\(key)' in \(path) must be a string.", at: node.sourceLocation)
      return nil
    }
    return scalar.string
  }

  func int(_ key: String) -> Int? {
    guard let node = mapping[key] else { return nil }
    guard node.isPlainScalar, let value = node.int else {
      collector.error("type_mismatch", "'\(key)' in \(path) must be an integer.", at: node.sourceLocation)
      return nil
    }
    return value
  }

  func bool(_ key: String) -> Bool? {
    guard let node = mapping[key] else { return nil }
    guard node.isPlainScalar, let value = node.bool else {
      collector.error("type_mismatch", "'\(key)' in \(path) must be true or false.", at: node.sourceLocation)
      return nil
    }
    return value
  }

  func enumValue<T: RawRepresentable>(_ key: String, _ type: T.Type) -> T? where T.RawValue == String {
    guard let text = string(key) else { return nil }
    guard let value = T(rawValue: text) else {
      collector.error("invalid_value", "'\(key)' in \(path) has unsupported value '\(text)'.", at: location(of: key))
      return nil
    }
    return value
  }

  func requiredEnum<T: RawRepresentable>(_ key: String, _ type: T.Type) -> T? where T.RawValue == String {
    guard has(key) else {
      collector.error("missing_key", "'\(path)' needs '\(key)'.", at: location)
      return nil
    }
    return enumValue(key, type)
  }

  func stringList(_ key: String) -> [String]? {
    guard let node = mapping[key] else { return nil }
    guard case .sequence(let sequence) = node else {
      collector.error("type_mismatch", "'\(key)' in \(path) must be a list.", at: node.sourceLocation)
      return nil
    }
    return sequence.compactMap { strictText($0, key: key) }
  }

  func mapping(_ key: String) -> MappingReader? {
    MappingReader(node: mapping[key], collector: collector, path: "\(path).\(key)")
  }

  func requiredSequence(_ key: String) -> SequenceReader? {
    guard let node = mapping[key] else {
      collector.error("missing_key", "'\(path)' needs '\(key)'.", at: location)
      return nil
    }
    return SequenceReader(node: node, collector: collector, path: "\(path).\(key)")
  }
}

nonisolated struct SequenceReader {
  let sequence: Node.Sequence
  let collector: DiagnosticCollector
  let path: String

  init?(node: Node, collector: DiagnosticCollector, path: String) {
    guard case .sequence(let sequence) = node else {
      collector.error("type_mismatch", "'\(path)' must be a list.", at: node.sourceLocation)
      return nil
    }
    self.sequence = sequence
    self.collector = collector
    self.path = path
  }

  var isEmpty: Bool { sequence.isEmpty }

  func mappings() -> [MappingReader] {
    sequence.enumerated().compactMap { index, node in
      MappingReader(node: node, collector: collector, path: "\(path)[\(index)]")
    }
  }
}
