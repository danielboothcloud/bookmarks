import 'package:freezed_annotation/freezed_annotation.dart';

part 'url_metadata.freezed.dart';

/// Result of fetching metadata for a URL. Both fields are nullable: the title
/// fetch and favicon fetch fail independently. Null in either field means
/// "nothing useful was retrieved" -- callers should fall back to existing
/// values (URL as title, placeholder favicon).
@freezed
abstract class UrlMetadata with _$UrlMetadata {
  const factory UrlMetadata({
    String? title,
    String? faviconBase64,
  }) = _UrlMetadata;
}
