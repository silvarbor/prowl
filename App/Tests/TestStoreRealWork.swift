extension Duration {
  /// The `TestStore.timeout` for a store whose effects do real work (git processes, file system,
  /// kernel events). TCA's 1 s default flakes on a loaded runner. It stays moderate because a
  /// waiting store polls without suspending: a non-exhaustive `finish()` spends the whole budget
  /// on an effect that outlives the test, and many such waits at once slow the whole run.
  static let realWorkTestStoreTimeout: Duration = .seconds(5)
}
