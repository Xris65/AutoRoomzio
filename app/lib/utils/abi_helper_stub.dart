/// Returns the primary Android ABI of the current device, or `null` on
/// non-IO platforms such as Web.
Future<String?> getPrimaryAndroidAbi() => Future<String?>.value(null);
