# ML Kit looks its parts up at run time, in a registry it fills by
# reflection. Shrinking breaks that lookup: the document scanner then finds
# no SharedPrefManager and can't start in a release build, and text
# recognition is built the same way. ML Kit and the registry it uses are
# kept whole.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google.firebase.components.** { *; }
