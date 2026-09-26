# ML Kit's text-recognition plugin can load the Chinese, Devanagari, Japanese
# and Korean models, but only compiles against them; the app ships the Latin
# one alone. Tell R8 their absence is on purpose.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
