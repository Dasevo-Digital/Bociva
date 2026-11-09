# PreppSuite patch: zxing-cpp builds its options, results and positions
# from native code by class and field name, so R8 must leave them as they
# are. The ML Kit rules went with ML Kit.
-keep class zxingcpp.** { *; }

-keepclassmembers class * extends java.lang.Enum {
    <fields>;
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
