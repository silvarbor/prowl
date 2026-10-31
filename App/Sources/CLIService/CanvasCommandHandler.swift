// App/Sources/CLIService/CanvasCommandHandler.swift
// Handles `prowl canvas`: show/hide Canvas, apply a layout, fit, and report status.

import Foundation
import ProwlCLIShared

/// Canvas state the handler reports and decides on.
struct CanvasCLISnapshot: Equatable {
  var isShowing: Bool
  var layoutMode: CanvasLayoutMode?
  var cardCount: Int
  /// The view-local command request Canvas has not consumed yet, if any.
  var pendingCommandRequestID: Int?
  /// The last view-local request Canvas actually ran.
  var lastPerformedCommandRequestID: Int?
}

/// What the handler asks the app to do.
enum CanvasCLIOperation: Equatable {
  case show
  case hide
  case command(CanvasCommandRequest.Command)
}

@MainActor
final class CanvasCommandHandler: CommandHandler {
  typealias SnapshotProvider = @MainActor () -> CanvasCLISnapshot
  /// Performs the operation; for `.command`, returns the ID of the request.
  typealias Performer = @MainActor (CanvasCLIOperation) -> Int?
  /// Waits until the condition holds or a timeout passes; returns whether it held.
  typealias Waiter = @MainActor (_ condition: @escaping @MainActor () -> Bool) async -> Bool

  private static let command = "canvas"
  private static let schemaVersion = "prowl.cli.canvas.v1"

  private let snapshot: SnapshotProvider
  private let perform: Performer
  private let waitUntil: Waiter

  init(snapshot: @escaping SnapshotProvider, perform: @escaping Performer, waitUntil: @escaping Waiter) {
    self.snapshot = snapshot
    self.perform = perform
    self.waitUntil = waitUntil
  }

  func handle(envelope: CommandEnvelope) async -> CommandResponse {
    guard case .canvas(let input) = envelope.command else {
      return errorResponse(code: CLIErrorCode.canvasFailed, message: "Invalid command.")
    }

    switch input.action {
    case .status:
      break
    case .show:
      if let failure = await show() { return failure }
    case .hide:
      if snapshot().isShowing {
        _ = perform(.hide)
        guard await waitUntil({ [snapshot] in !snapshot().isShowing }) else {
          return errorResponse(code: CLIErrorCode.canvasFailed, message: "Canvas did not close.")
        }
      }
    case .layout:
      guard let layout = input.layout else {
        return errorResponse(
          code: CLIErrorCode.invalidArgument,
          message: "canvas layout requires arrange, organize, or tile."
        )
      }
      if let failure = await runViewCommand(.layout(CanvasLayoutKind(layout)), showing: input.show) {
        return failure
      }
    case .fit:
      if let failure = await runViewCommand(.fit, showing: input.show) { return failure }
    }
    return successResponse(action: input.action)
  }

  /// Show Canvas and wait until it is the current view.
  private func show() async -> CommandResponse? {
    guard !snapshot().isShowing else { return nil }
    _ = perform(.show)
    guard await waitUntil({ [snapshot] in snapshot().isShowing }) else {
      return errorResponse(
        code: CLIErrorCode.canvasUnavailable,
        message: "Canvas could not open. Open a worktree first."
      )
    }
    return nil
  }

  /// Run a command that only the Canvas view can perform, and wait until the
  /// view has taken it.
  private func runViewCommand(_ command: CanvasCommandRequest.Command, showing: Bool) async -> CommandResponse? {
    if !snapshot().isShowing {
      guard showing else {
        return errorResponse(
          code: CLIErrorCode.canvasNotShowing,
          message: "Canvas is not showing. Pass --show to switch to it first."
        )
      }
      if let failure = await show() { return failure }
    }
    guard let requestID = perform(.command(command)) else {
      return errorResponse(code: CLIErrorCode.canvasFailed, message: "Canvas did not accept the request.")
    }
    guard await waitUntil({ [snapshot] in snapshot().pendingCommandRequestID != requestID }) else {
      return errorResponse(code: CLIErrorCode.canvasFailed, message: "Canvas did not respond.")
    }
    // Leaving the slot is not enough: another request may have replaced it, or
    // Canvas may have closed and dropped it.
    guard snapshot().lastPerformedCommandRequestID == requestID else {
      return errorResponse(
        code: CLIErrorCode.canvasFailed,
        message: "Canvas closed or received another request before applying this one."
      )
    }
    return nil
  }

  private func successResponse(action: CanvasAction) -> CommandResponse {
    let state = snapshot()
    let payload = CanvasCommandPayload(
      action: action,
      showing: state.isShowing,
      layout: state.layoutMode.map(Self.name(of:)),
      cardCount: state.cardCount
    )
    do {
      return try CommandResponse(
        ok: true,
        command: Self.command,
        schemaVersion: Self.schemaVersion,
        data: RawJSON(encoding: payload)
      )
    } catch {
      return errorResponse(code: CLIErrorCode.canvasFailed, message: "Failed to encode the Canvas state.")
    }
  }

  private func errorResponse(code: String, message: String) -> CommandResponse {
    CommandResponse(
      ok: false,
      command: Self.command,
      schemaVersion: Self.schemaVersion,
      error: CommandError(code: code, message: message)
    )
  }

  static func name(of mode: CanvasLayoutMode) -> String {
    mode.automaticKind?.rawValue ?? "freeform"
  }
}

extension CanvasLayoutKind {
  init(_ name: CanvasLayoutName) {
    switch name {
    case .arrange: self = .arrange
    case .organize: self = .organize
    case .tile: self = .tile
    }
  }
}
