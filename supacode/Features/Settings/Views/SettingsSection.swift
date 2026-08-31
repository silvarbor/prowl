import Foundation

enum SettingsSection: Hashable {
  case general
  case notifications
  case shortcuts
  case worktree
  case updates
  case advanced
  case github
  case customCommands
  case profiles
  case commandLineTool
  case repository(Repository.ID)
}
