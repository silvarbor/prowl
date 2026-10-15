import CoreGraphics
import Foundation
import Testing

@testable import Prowl

@MainActor
struct CanvasLayoutStoreTests {
  @Test func releasesSynchronouslyWithTaskLocalStorageOutsideATask() async {
    // Swift Testing runs in a Task. A main-queue callback reproduces synchronous
    // UI teardown with thread-local TaskLocal storage instead of task-owned storage.
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          #expect(Thread.isMainThread)
          withUnsafeCurrentTask { #expect($0 == nil) }
          let defaults = makeDefaults()
          defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
          let layouts = ["tab-a": CanvasCardLayout(position: CGPoint(x: 10, y: 20))]

          CanvasLayoutStoreTestLocal.$marker.withValue(1) {
            var store: CanvasLayoutStore? = CanvasLayoutStore(defaults: defaults)
            weak let releasedStore = store
            store?.setCardLayouts(layouts)
            store = nil

            #expect(releasedStore == nil)
            #expect(CanvasLayoutStoreTestLocal.marker == 1)
            #expect(CanvasLayoutStore(defaults: defaults).cardLayouts == layouts)
          }
          #expect(CanvasLayoutStoreTestLocal.marker == 0)
          continuation.resume()
        }
      }
    }
  }

  @Test func loadsLegacyCardLayoutDictionary() throws {
    let defaults = makeDefaults()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let legacyLayouts = [
      "tab-a": CanvasCardLayout(position: CGPoint(x: 10, y: 20), size: CGSize(width: 300, height: 200)),
      "tab-b": CanvasCardLayout(position: CGPoint(x: 30, y: 40), size: CGSize(width: 500, height: 400)),
    ]
    let data = try JSONEncoder().encode(legacyLayouts)
    defaults.set(data, forKey: "canvasCardLayouts")

    let store = CanvasLayoutStore(defaults: defaults)

    #expect(store.cardLayouts == legacyLayouts)
    #expect(Set(store.zOrder) == Set(legacyLayouts.keys))
    #expect(store.mode == .freeform)
    #expect(store.layoutForEntry(cardKeys: ["tab-a", "tab-b"], defaultKind: .tile) == nil)
  }

  @Test func layoutsStoredBeforeModesExistedLoadAsFreeform() {
    let defaults = makeDefaults()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let store = CanvasLayoutStore(defaults: defaults)
    store.setCardLayouts([
      "tab-a": CanvasCardLayout(position: CGPoint(x: 10, y: 20)),
      "tab-b": CanvasCardLayout(position: CGPoint(x: 30, y: 40)),
    ])

    let restoredStore = CanvasLayoutStore(defaults: defaults)

    #expect(restoredStore.mode == .freeform)
    #expect(restoredStore.layoutForEntry(cardKeys: ["tab-a", "tab-b"], defaultKind: .tile) == nil)
    #expect(restoredStore.mode == .freeform)
  }

  @Test func freshCanvasStartsInTheDefaultLayout() {
    let defaults = makeDefaults()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let store = CanvasLayoutStore(defaults: defaults)

    #expect(store.mode == nil)
    #expect(store.layoutForEntry(cardKeys: ["tab-a"], defaultKind: .arrange) == .arrange)
    #expect(store.mode == .automatic(.arrange))
    #expect(store.layoutForEntry(cardKeys: [], defaultKind: .tile) == nil)
  }

  @Test func rememberedAutomaticLayoutSurvivesUnknownCards() {
    // Without terminal layout restore, every launch brings new tab IDs.
    let defaults = makeDefaults()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let store = CanvasLayoutStore(defaults: defaults)
    store.setCardLayouts(["tab-a": CanvasCardLayout(position: .zero)])
    store.mode = .automatic(.organize)

    let restoredStore = CanvasLayoutStore(defaults: defaults)

    #expect(restoredStore.layoutForEntry(cardKeys: ["tab-x", "tab-y"], defaultKind: .tile) == .organize)
    #expect(restoredStore.mode == .automatic(.organize))
  }

  @Test func freeformCanvasWhoseCardsAreAllUnknownStartsInTheDefaultLayout() {
    let defaults = makeDefaults()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let store = CanvasLayoutStore(defaults: defaults)
    store.setCardLayouts(["tab-a": CanvasCardLayout(position: .zero)])
    store.mode = .freeform

    let restoredStore = CanvasLayoutStore(defaults: defaults)

    #expect(restoredStore.layoutForEntry(cardKeys: ["tab-c", "tab-d"], defaultKind: .tile) == .tile)
    #expect(restoredStore.mode == .automatic(.tile))
  }

  @Test func rememberedAutomaticLayoutAppliesOnEntry() {
    let defaults = makeDefaults()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let store = CanvasLayoutStore(defaults: defaults)
    store.setCardLayouts(["tab-a": CanvasCardLayout(position: .zero)])
    store.mode = .automatic(.organize)

    let restoredStore = CanvasLayoutStore(defaults: defaults)

    #expect(restoredStore.mode == .automatic(.organize))
    #expect(restoredStore.layoutForEntry(cardKeys: ["tab-a", "tab-b"], defaultKind: .tile) == .organize)
  }

  @Test func unknownStoredModeKeepsTheCardLayouts() throws {
    let defaults = makeDefaults()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let json = """
      {"cardLayouts":{"tab-a":{"positionX":1,"positionY":2,"width":300,"height":200}},\
      "zOrder":["tab-a"],"mode":"spiral"}
      """
    defaults.set(Data(json.utf8), forKey: "canvasCardLayouts")

    let store = CanvasLayoutStore(defaults: defaults)

    #expect(store.cardLayouts["tab-a"]?.size == CGSize(width: 300, height: 200))
    #expect(store.mode == .freeform)
  }

  @Test func applyLayoutsKeepsUncoveredCardsBelowTheLaidOutOnes() {
    let defaults = makeDefaults()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let store = CanvasLayoutStore(defaults: defaults)
    let hidden = CanvasCardLayout(position: CGPoint(x: 5, y: 5))
    store.setCardLayouts(
      [
        "tab-a": CanvasCardLayout(position: .zero),
        "tab-hidden": hidden,
        "tab-b": CanvasCardLayout(position: .zero),
      ],
      zOrder: ["tab-a", "tab-hidden", "tab-b"]
    )

    let laidOut = [
      "tab-a": CanvasCardLayout(position: CGPoint(x: 100, y: 100)),
      "tab-b": CanvasCardLayout(position: CGPoint(x: 200, y: 200)),
    ]
    store.applyLayouts(laidOut, order: ["tab-b", "tab-a"])

    #expect(store.cardLayouts["tab-a"] == laidOut["tab-a"])
    #expect(store.cardLayouts["tab-b"] == laidOut["tab-b"])
    #expect(store.cardLayouts["tab-hidden"] == hidden)
    #expect(store.zOrder == ["tab-hidden", "tab-b", "tab-a"])
  }

  @Test func moveToFrontPersistsZOrder() {
    let defaults = makeDefaults()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let store = CanvasLayoutStore(defaults: defaults)
    store.setCardLayouts(
      [
        "tab-a": CanvasCardLayout(position: .zero),
        "tab-b": CanvasCardLayout(position: .zero),
      ],
      zOrder: ["tab-a", "tab-b"]
    )

    store.moveToFront("tab-a")
    let restoredStore = CanvasLayoutStore(defaults: defaults)

    #expect(restoredStore.zOrder == ["tab-b", "tab-a"])
    #expect(restoredStore.zIndex(for: "tab-a") > restoredStore.zIndex(for: "tab-b"))
  }

  @Test func pruneRemovesStaleLayoutsAndZOrder() {
    let defaults = makeDefaults()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let store = CanvasLayoutStore(defaults: defaults)
    store.setCardLayouts(
      [
        "tab-a": CanvasCardLayout(position: .zero),
        "tab-b": CanvasCardLayout(position: .zero),
      ],
      zOrder: ["tab-a", "tab-b"]
    )

    store.prune(to: ["tab-b"])

    #expect(Array(store.cardLayouts.keys) == ["tab-b"])
    #expect(store.zOrder == ["tab-b"])
  }
}

private enum CanvasLayoutStoreTestLocal {
  @TaskLocal static var marker = 0
}

private func makeDefaults() -> UserDefaults {
  let suiteName = "CanvasLayoutStoreTests-\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.set(suiteName, forKey: "__suiteName")
  return defaults
}

private func defaultsSuiteName(_ defaults: UserDefaults) -> String {
  defaults.string(forKey: "__suiteName")!
}
