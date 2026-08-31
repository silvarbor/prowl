import Foundation

nonisolated struct UserGlobalSettings: Codable, Equatable, Sendable {
  var customCommands: [UserCustomCommand]
  var agentProfiles: [AgentProfile]
  /// One-shot seeding marker for agent profiles (docs-ai 053): seeded profiles
  /// the user deletes must never respawn.
  var didSeedAgentProfiles: Bool
  /// `<scope>/<id>` keys of workflow definitions switched off (docs-ai 063 B1; Settings UI in D1).
  var disabledWorkflowIDs: [String]
  /// Remembered `launch` role bindings (dsl-spec §3): one profile per requirements-digest key.
  var workflowBindings: [WorkflowRememberedBinding]

  static let `default` = UserGlobalSettings(customCommands: [])

  private enum CodingKeys: String, CodingKey {
    case customCommands
    case agentProfiles
    case didSeedAgentProfiles
    case disabledWorkflowIDs
    case workflowBindings
  }

  init(
    customCommands: [UserCustomCommand],
    agentProfiles: [AgentProfile] = [],
    didSeedAgentProfiles: Bool = false,
    disabledWorkflowIDs: [String] = [],
    workflowBindings: [WorkflowRememberedBinding] = []
  ) {
    self.customCommands = UserCustomCommand.normalizedCommands(customCommands)
    self.agentProfiles = AgentProfile.normalizedProfiles(agentProfiles)
    self.didSeedAgentProfiles = didSeedAgentProfiles
    self.disabledWorkflowIDs = Self.normalizedWorkflowIDs(disabledWorkflowIDs)
    self.workflowBindings = WorkflowRememberedBinding.normalized(workflowBindings)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let commands = try container.decodeIfPresent([UserCustomCommand].self, forKey: .customCommands) ?? []
    customCommands = UserCustomCommand.normalizedCommands(commands)
    let profiles = try container.decodeIfPresent([AgentProfile].self, forKey: .agentProfiles) ?? []
    agentProfiles = AgentProfile.normalizedProfiles(profiles)
    didSeedAgentProfiles = try container.decodeIfPresent(Bool.self, forKey: .didSeedAgentProfiles) ?? false
    let disabled = try container.decodeIfPresent([String].self, forKey: .disabledWorkflowIDs) ?? []
    disabledWorkflowIDs = Self.normalizedWorkflowIDs(disabled)
    let bindings = try container.decodeIfPresent([WorkflowRememberedBinding].self, forKey: .workflowBindings) ?? []
    workflowBindings = WorkflowRememberedBinding.normalized(bindings)
  }

  func normalized() -> UserGlobalSettings {
    UserGlobalSettings(
      customCommands: customCommands,
      agentProfiles: agentProfiles,
      didSeedAgentProfiles: didSeedAgentProfiles,
      disabledWorkflowIDs: disabledWorkflowIDs,
      workflowBindings: workflowBindings
    )
  }

  func rememberedWorkflowBinding(for key: WorkflowBindingMemoryKey) -> UUID? {
    workflowBindings.first { $0.key == key }?.profileID
  }

  mutating func remember(workflowBinding key: WorkflowBindingMemoryKey, profileID: UUID) {
    workflowBindings = WorkflowRememberedBinding.normalized(
      workflowBindings.filter { $0.key != key } + [WorkflowRememberedBinding(key: key, profileID: profileID)])
  }

  /// Stable order, no duplicates: the set semantics of a persisted list.
  static func normalizedWorkflowIDs(_ ids: [String]) -> [String] {
    Array(Set(ids)).sorted()
  }
}

/// One remembered `launch` binding: the profile that satisfied a role's requirements last time.
nonisolated struct WorkflowRememberedBinding: Codable, Equatable, Sendable {
  let key: WorkflowBindingMemoryKey
  let profileID: UUID

  enum CodingKeys: String, CodingKey {
    case key
    case profileID = "profile_id"
  }

  /// One entry per key, in a stable order.
  static func normalized(_ bindings: [WorkflowRememberedBinding]) -> [WorkflowRememberedBinding] {
    var seen: Set<WorkflowBindingMemoryKey> = []
    var unique: [WorkflowRememberedBinding] = []
    for binding in bindings.reversed() where seen.insert(binding.key).inserted {
      unique.append(binding)
    }
    return unique.sorted {
      ($0.key.scope, $0.key.workflowID, $0.key.role, $0.key.digest)
        < ($1.key.scope, $1.key.workflowID, $1.key.role, $1.key.digest)
    }
  }
}
