# ML Kit looks its parts up at run time, in a registry it fills by
# reflection. Shrinking breaks that lookup: the document scanner then finds
# no SharedPrefManager and can't start in a release build. ML Kit and the
# registry it uses are kept whole.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_document_scanner.** { *; }
-keep class com.google.firebase.components.** { *; }
