/// Why an import attempt terminated unsuccessfully. Drives the calm
/// inline copy rendered by `_ImportSection`.
///
/// - [userCancelled]: the OS file picker returned `null` (user clicked
///   Cancel). The UI returns silently to idle — no error surface.
/// - [invalidFile]: the parser produced an empty tree with no folders
///   AND no bookmarks (the file isn't a Netscape bookmark export, or
///   wasn't HTML at all). Shows the calm inline message.
/// - [storageError]: a repository write failed mid-import. Partial
///   writes are NOT rolled back (per writer contract); the user sees
///   the muted "Couldn't save" copy and the button remains enabled.
enum ImportFailureReason {
  userCancelled,
  invalidFile,
  storageError,
}
