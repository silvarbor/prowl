// ProwlCLI/Commands/CanvasCommand.swift

import ArgumentParser
import ProwlCLIShared

struct CanvasCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "canvas",
    abstract: "Show, hide, and lay out the Canvas view.",
    subcommands: [
      CanvasShowCommand.self,
      CanvasHideCommand.self,
      CanvasLayoutCommand.self,
      CanvasFitCommand.self,
      CanvasStatusCommand.self,
    ]
  )

  static func execute(_ input: CanvasInput, options: GlobalOptions) throws {
    try CLIExecution.run(command: "canvas", output: options.outputMode, colorEnabled: options.colorEnabled) {
      try CLIRunner.execute(CommandEnvelope(output: options.outputMode, command: .canvas(input)))
    }
  }
}

extension CanvasLayoutName: @retroactive ExpressibleByArgument {}

struct CanvasShowCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "show",
    abstract: "Switch to the Canvas view."
  )

  @OptionGroup var options: GlobalOptions

  mutating func run() throws {
    try CanvasCommand.execute(CanvasInput(action: .show), options: options)
  }
}

struct CanvasHideCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "hide",
    abstract: "Leave Canvas for the normal view."
  )

  @OptionGroup var options: GlobalOptions

  mutating func run() throws {
    try CanvasCommand.execute(CanvasInput(action: .hide), options: options)
  }
}

struct CanvasLayoutCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "layout",
    abstract: "Lay out every card and keep that layout as cards come and go.",
    discussion: """
      arrange packs cards at their current sizes, organize puts them in a uniform grid, \
      and tile resizes them to fill the window. Canvas keeps applying the layout until a \
      card is moved by hand.
      """
  )

  @Argument(help: "The layout to apply.")
  var layout: CanvasLayoutName

  @Flag(name: .long, help: "Switch to Canvas first when it is hidden.")
  var show = false

  @OptionGroup var options: GlobalOptions

  mutating func run() throws {
    try CanvasCommand.execute(CanvasInput(action: .layout, layout: layout, show: show), options: options)
  }
}

struct CanvasFitCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "fit",
    abstract: "Zoom and pan Canvas so every card is visible."
  )

  @Flag(name: .long, help: "Switch to Canvas first when it is hidden.")
  var show = false

  @OptionGroup var options: GlobalOptions

  mutating func run() throws {
    try CanvasCommand.execute(CanvasInput(action: .fit, show: show), options: options)
  }
}

struct CanvasStatusCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: "Report whether Canvas is showing, its layout, and its card count."
  )

  @OptionGroup var options: GlobalOptions

  mutating func run() throws {
    try CanvasCommand.execute(CanvasInput(action: .status), options: options)
  }
}
