/// Why an import attempt terminated unsuccessfully. Drives the calm
/// inline copy rendered by `_ImportSection`.
///
/// User-cancel is NOT in this enum — cancel transitions the notifier
/// straight back to [ImportIdle] (per AC7 / state-machine contract);
/// no failed state is recorded.
///
/// - [invalidFile]: the parser produced an empty tree with no folders
///   AND no bookmarks (the file isn't a Netscape bookmark export, or
///   wasn't HTML at all). Shows the calm inline message.
/// - [storageError]: a repository write failed mid-import. Partial
///   writes are NOT rolled back (per writer contract); the user sees
///   the muted "Couldn't save" copy and the button remains enabled.
enum ImportFailureReason {
  invalidFile,
  storageError,
}
