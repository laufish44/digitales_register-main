// Verifies the ShellExecuteW ffi binding used by lib/file_opener.dart without
// actually launching any application.
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef _Native = IntPtr Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>,
    Pointer<Utf16>, Pointer<Utf16>, Int32);
typedef _Dart = int Function(
    int, Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, int);

void main() async {
  final shellExecuteW = DynamicLibrary.open("shell32.dll")
      .lookupFunction<_Native, _Dart>("ShellExecuteW");
  print("ShellExecuteW resolved OK");

  int call(String path, String verb) {
    final v = verb.toNativeUtf16();
    final p = path.toNativeUtf16();
    try {
      return shellExecuteW(0, v, p, nullptr, nullptr, 1);
    } finally {
      malloc.free(v);
      malloc.free(p);
    }
  }

  // A path that does not exist must yield ERROR_FILE_NOT_FOUND (2).
  final missing = r"C:\Users\laurf\Downloads\__does_not_exist__.docx";
  print("missing file        -> ${call(missing, "open")}  (expected 2)");

  // A name with an unregistered extension -> SE_ERR_NOASSOC (31).
  final weird = File(r"C:\Users\laurf\AppData\Local\Temp\dr_assoc_probe.zzqq9");
  weird.writeAsStringSync("probe");
  print("no association      -> ${call(weird.path, "open")}  (expected 31)");
  weird.deleteSync();

  // Reproduce the original bug: the macOS `open` command on Windows.
  try {
    await Process.start("open", [missing]);
    print("Process.start(open) -> unexpectedly succeeded");
  } catch (e) {
    print("Process.start(open) -> $e");
  }
}
