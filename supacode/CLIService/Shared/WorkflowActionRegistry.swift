// ProwlShared/WorkflowActionRegistry.swift
// Typed schemas of the V1 native actions (dsl-spec.md §4). The validator and `prowl workflow
// schema` read them; execution arrives with the runner.

import Foundation

nonisolated public struct WorkflowActionInput: Equatable, Sendable {
  public enum Kind: String, Equatable, Sendable {
    /// Templated text.
    case string
    /// Templated path.
    case path
    /// A role name declared by the workflow; never templated.
    case role
  }

  public let name: String
  public let required: Bool
  public let kind: Kind
  public let description: String

  public init(name: String, required: Bool, kind: Kind = .string, description: String) {
    self.name = name
    self.required = required
    self.kind = kind
    self.description = description
  }
}

nonisolated public struct WorkflowActionOutput: Equatable, Sendable {
  public let name: String
  public let description: String

  public init(name: String, description: String) {
    self.name = name
    self.description = description
  }
}

nonisolated public struct WorkflowActionSchema: Equatable, Sendable {
  public let id: String
  public let description: String
  public let inputs: [WorkflowActionInput]
  public let outputs: [WorkflowActionOutput]

  public init(id: String, description: String, inputs: [WorkflowActionInput], outputs: [WorkflowActionOutput]) {
    self.id = id
    self.description = description
    self.inputs = inputs
    self.outputs = outputs
  }

  public func input(named name: String) -> WorkflowActionInput? {
    inputs.first { $0.name == name }
  }

  public func hasOutput(named name: String) -> Bool {
    outputs.contains { $0.name == name }
  }
}

nonisolated public enum WorkflowActionRegistry {
  public static let all: [WorkflowActionSchema] = [
    WorkflowActionSchema(
      id: "handoff.transition",
      description:
        "Archive-first `.prowl/handoff/` transition from one role to another; without a briefing "
        + "it becomes a context-only transition.",
      inputs: [
        WorkflowActionInput(
          name: "briefing", required: false, kind: .path, description: "Path to the validated briefing"),
        WorkflowActionInput(name: "from", required: true, kind: .role, description: "Outgoing role"),
        WorkflowActionInput(name: "to", required: true, kind: .role, description: "Receiving role"),
        WorkflowActionInput(name: "note", required: false, description: "Log note"),
      ],
      outputs: [
        WorkflowActionOutput(name: "kickoff_prompt", description: "Kickoff prompt for the receiver"),
        WorkflowActionOutput(name: "artifact_path", description: "Path of the handoff artifact"),
        WorkflowActionOutput(name: "has_briefing", description: "Whether a briefing was delivered"),
      ]
    ),
    WorkflowActionSchema(
      id: "handoff.checkpoint",
      description: "Save progress for a later successor; regenerates `context.md`.",
      inputs: [
        WorkflowActionInput(
          name: "briefing", required: false, kind: .path, description: "Path to the validated briefing"),
        WorkflowActionInput(name: "note", required: false, description: "Log note"),
      ],
      outputs: [
        WorkflowActionOutput(name: "artifact_path", description: "Path of the handoff artifact"),
        WorkflowActionOutput(name: "has_briefing", description: "Whether a briefing was delivered"),
      ]
    ),
    WorkflowActionSchema(
      id: "git.context",
      description: "Generate a markdown summary of the worktree's repository state.",
      inputs: [
        WorkflowActionInput(
          name: "root", required: false, kind: .path, description: "Repository root; defaults to the worktree")
      ],
      outputs: [
        WorkflowActionOutput(name: "path", description: "Path to the generated markdown summary"),
        WorkflowActionOutput(name: "branch", description: "Checked-out branch"),
      ]
    ),
  ]

  public static func schema(for id: String, in actions: [WorkflowActionSchema] = all) -> WorkflowActionSchema? {
    actions.first { $0.id == id }
  }
}
