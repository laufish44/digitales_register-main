# biometric_storage pulls in slf4j, whose optional static binder classes are
# never shipped. They are only looked up reflectively at runtime and the
# fallback no-op logger is used instead, so R8 can ignore them.
-dontwarn org.slf4j.impl.StaticLoggerBinder
-dontwarn org.slf4j.impl.StaticMarkerBinder

# Google Tink (through flutter_secure_storage / androidx.security) is compiled
# against the JSR-305 annotations but does not depend on them at runtime. They
# used to arrive with the Firebase SDK; since that was removed they have to be
# ignored explicitly, otherwise R8 refuses to finish.
-dontwarn javax.annotation.**
-dontwarn com.google.errorprone.annotations.**
