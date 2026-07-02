# Platform Setup Guide — genesis_ai_sdk + flutter_gemma

This guide covers everything you need to run on-device models via `GemmaProvider`
on every supported platform. Cloud providers (Gemini, OpenAI, Anthropic, Ollama)
need no platform-specific setup beyond internet access.

---

## File format quick reference

| Format | Extension | macOS | Windows | Linux | Android | iOS |
|--------|-----------|:-----:|:-------:|:-----:|:-------:|:---:|
| LiteRT-LM | `.litertlm` | ✅ | ✅ | ✅ | ✅ | ✅ |
| MediaPipe Task | `.task` | ❌ | ❌ | ❌ | ✅ | ✅ |
| Binary / TFLite | `.bin` / `.tflite` | ⚠️ | ⚠️ | ⚠️ | ✅ | ✅ |

**Rule of thumb:** always use `.litertlm` — it works on every platform.

---

## Downloading models

```dart
// By model ID (uses the built-in URL catalogue):
await GemmaModelManager.download(
  modelId: 'qwen3-0.6b',
  destinationPath: '/path/to/models/qwen3-0.6b.litertlm',
  onProgress: (received, total) {
    if (total > 0) print('${(received / total * 100).toStringAsFixed(1)}%');
  },
);

// By arbitrary URL (any HuggingFace or CDN link):
await GemmaModelManager.downloadFromUrl(
  url: 'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/qwen3-0.6b-q4_1.litertlm',
  destinationPath: '/path/to/models/qwen3-0.6b.litertlm',
);
```

**HuggingFace tokens** for gated/private repos are read from environment
automatically (`HF_TOKEN` or `HUGGINGFACE_TOKEN`), or pass `hfToken:` directly.

---

## macOS

### Minimum OS: 10.15 (Catalina)

### 1. Podfile — copy companion dylibs

flutter_gemma 0.16.x ships three native dylibs that must be bundled as
`.framework`s inside the app. Add this to your `macos/Podfile`:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_macos_build_settings(target)
  end

  installer.aggregate_targets.each do |aggregate_target|
    aggregate_target.user_targets.each do |user_target|
      phase_name = '[flutter_gemma] Setup LiteRT-LM macOS'
      existing = user_target.shell_script_build_phases.find { |p| p.name == phase_name }
      phase = existing || user_target.new_shell_script_build_phase(phase_name)
      phase.shell_script = <<~SHELL
        set -e
        FRAMEWORKS="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks"
        [ -d "${FRAMEWORKS}" ] || exit 0
        for base in LiteRtMetalAccelerator LiteRtTopKMetalSampler GemmaModelConstraintProvider; do
          rm -f "${FRAMEWORKS}/lib${base}.dylib"
        done
        for candidate in \
            "${HOME}/Library/Caches/flutter_gemma/native/macos_arm64" \
            "${PODS_ROOT}/../Flutter/ephemeral/.symlinks/plugins/flutter_gemma/native/litert_lm/prebuilt/macos_arm64" \
            "${SRCROOT}/../../native/litert_lm/prebuilt/macos_arm64"; do
          if [ -f "${candidate}/libGemmaModelConstraintProvider.dylib" ]; then
            PLUGIN_PREBUILT="${candidate}"; break
          fi
        done
        [ -n "${PLUGIN_PREBUILT:-}" ] || { echo "[flutter_gemma] ERROR: dylibs not found. Run 'flutter clean && flutter pub get'."; exit 1; }
        for base in GemmaModelConstraintProvider LiteRtMetalAccelerator LiteRtTopKMetalSampler; do
          src="${PLUGIN_PREBUILT}/lib${base}.dylib"
          [ -f "${src}" ] || continue
          fw_dir="${FRAMEWORKS}/${base}.framework"
          mkdir -p "${fw_dir}/Versions/A/Resources"
          cp "${src}" "${fw_dir}/Versions/A/${base}"
          install_name_tool -id "@rpath/${base}.framework/Versions/A/${base}" "${fw_dir}/Versions/A/${base}" 2>/dev/null || true
          (cd "${fw_dir}" && ln -sfh A Versions/Current && ln -sfh "Versions/Current/${base}" "${base}" && ln -sfh "Versions/Current/Resources" Resources)
          cat > "${fw_dir}/Versions/A/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>${base}</string>
  <key>CFBundleIdentifier</key><string>dev.flutterberlin.flutter_gemma.${base}</string>
  <key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
</dict></plist>
EOF
        done
        LITERTLM="${FRAMEWORKS}/LiteRtLm.framework/Versions/A/LiteRtLm"
        if [ -f "${LITERTLM}" ]; then
          install_name_tool -change @rpath/libGemmaModelConstraintProvider.dylib \
            @rpath/GemmaModelConstraintProvider.framework/Versions/A/GemmaModelConstraintProvider \
            "${LITERTLM}" 2>/dev/null || true
          codesign --force --sign - "${LITERTLM}" 2>/dev/null || true
        fi
      SHELL
    end
  end
end
```

### 2. Entitlements — network + file access

Add to **both** `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:

```xml
<!-- Required: download models from HuggingFace / any URL -->
<key>com.apple.security.network.client</key>
<true/>
<!-- Required: bind a local HTTP server (only needed if running integration tests) -->
<key>com.apple.security.network.server</key>
<true/>
<!-- If model files are stored in ~/Downloads -->
<key>com.apple.security.files.downloads.read-only</key>
<true/>
<!-- For user-selected files (e.g. via FilePicker) -->
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
```

> **Without `network.client`** the app cannot open any `http://` or `https://`
> connection — model downloads will silently fail.

### 3. Initialize before use

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize();  // ← required
  runApp(MyApp());
}
```

### 4. Create the provider

```dart
final provider = GemmaProvider(
  modelId: 'qwen3-0.6b',
  modelPath: '/Users/you/Downloads/qwen3-0.6b.litertlm',
);
```

---

## iOS

### Minimum OS: iOS 16

### 1. No Podfile changes needed

flutter_gemma handles iOS bundling automatically via its own `.podspec`.

### 2. Info.plist — model file access

If downloading model files to the Documents folder:

```xml
<!-- ios/Runner/Info.plist -->
<key>UIFileSharingEnabled</key>
<true/>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
```

### 3. Initialize before use

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize();
  runApp(MyApp());
}
```

### 4. Model file placement

Store models in the app's Documents directory (persists across updates):

```dart
import 'package:path_provider/path_provider.dart';

final dir = await getApplicationDocumentsDirectory();
final modelPath = '${dir.path}/qwen3-0.6b.litertlm';

if (!await GemmaModelManager.isDownloaded(modelPath)) {
  await GemmaModelManager.download(
    modelId: 'qwen3-0.6b',
    destinationPath: modelPath,
    onProgress: (r, t) => print('${r ~/ 1e6} MB / ${t ~/ 1e6} MB'),
  );
}

final provider = GemmaProvider(
  modelId: 'qwen3-0.6b',
  modelPath: modelPath,
);
```

### 5. Format note

Both `.litertlm` (LiteRT-LM) and `.task` (MediaPipe) work on iOS.
Prefer `.litertlm` for cross-platform code; use `.task` only for
gemma-3n multimodal models (`.litertlm` not yet available).

---

## Android

### Minimum SDK: API 24 (Android 7.0)

### 1. `android/app/build.gradle[.kts]`

```kotlin
android {
    defaultConfig {
        // Increase NDK heap for large models
        manifestPlaceholders["android.max_aspect"] = "2.4"
    }
    // Required for flutter_gemma native libs
    packagingOptions {
        jniLibs.useLegacyPackaging = true
    }
}
```

### 2. `AndroidManifest.xml`

```xml
<!-- Download models over WiFi -->
<uses-permission android:name="android.permission.INTERNET"/>
<!-- Write to external storage (Android < 10) — optional -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="28"/>
```

### 3. Initialize before use

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize();
  runApp(MyApp());
}
```

### 4. Model file placement

Use `getApplicationSupportDirectory()` — app-private, survives updates, not
shared with the user or other apps:

```dart
// Easiest: let the SDK pick the right directory automatically
final modelsDir = await AgenticHub.platformModelsDir();
final modelPath = '$modelsDir/qwen3-0.6b.litertlm';

// Or use path_provider yourself:
import 'package:path_provider/path_provider.dart';
final dir = await getApplicationSupportDirectory();
final modelPath = '${dir.path}/qwen3-0.6b.litertlm';
```

> ⚠️ **Do NOT write to `/tmp` or `/sdcard`** on Android.
> `/tmp` is per-process temp space that is wiped between runs;
> `/sdcard` requires the deprecated `WRITE_EXTERNAL_STORAGE` permission.

### 5. Format note

Both `.litertlm` and `.task` work on Android. `.litertlm` is preferred —
it uses the LiteRT-LM backend which tends to be faster on modern Snapdragon
and Tensor chips.

---

## Windows

### Minimum: Windows 10 (64-bit)

### 1. No special setup

flutter_gemma bundles its native DLLs automatically via the Windows build.

### 2. Visual C++ Redistributable

Ensure the target machine has **MSVC 2019** runtime installed, or bundle it:
- Download: https://aka.ms/vs/17/release/vc_redist.x64.exe

### 3. Initialize before use

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize();
  runApp(MyApp());
}
```

### 4. Model file placement

Any absolute path works on Windows:

```dart
import 'package:path_provider/path_provider.dart';

final dir = await getApplicationSupportDirectory();
final modelPath = '${dir.path}\\qwen3-0.6b.litertlm';
```

---

## GGUF models — LlamaCppProvider

GGUF models use `LlamaCppProvider` backed by `llama_cpp_dart`.

### Library loading

| Platform | Do I need to set `Llama.libraryPath`? |
|----------|--------------------------------------|
| **Android** | **No** — the `.so` is bundled inside the plugin AAR; auto-loaded |
| **iOS** | **No** — linked via CocoaPods; but see note below |
| **macOS** (bundled app) | **No** — linked via CocoaPods |
| **macOS** (unit tests / CLI) | **Yes** — point to the prebuilt dylib in pub-cache |
| **Windows** | **Yes** — download `llama.dll` from llama_cpp_dart releases |
| **Linux** | **Yes** — download `libllama.so` from llama_cpp_dart releases |

```dart
// Only needed on macOS outside a bundled app, or on Windows/Linux:
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
Llama.libraryPath = '/path/to/libmtmd.dylib';
```

### iOS caveat (llama_cpp_dart 0.2.x)

The pre-built `Llama.xcframework` for iOS is **not included** in the published
0.2.x package — it must be compiled from source using the scripts in
`~/.pub-cache/hosted/pub.dev/llama_cpp_dart-0.2.2/darwin/`. This is a
known limitation of the 0.2.x release series.

**Recommended alternative on iOS**: use a `.litertlm` model with `GemmaProvider`
instead. LiteRT-LM works on iOS 16+ without any manual compilation.

### Android — no extra steps

`llama_cpp_dart` builds the native `.so` with the Android NDK via CMake.
Flutter includes it in the APK automatically. GGUF inference works on any
arm64-v8a or x86_64 Android device.

---

## Model recommendations by use case

| Use case | Recommended model | Size | Platforms |
|----------|------------------|------|-----------|
| General chat, desktop | `qwen3-0.6b` | 400 MB | All |
| Smallest possible model | `smollm-135m` | 90 MB | Mobile only |
| Tool / function calling | `function-gemma-270m` | 271 MB | All |
| Vision + chat (mobile) | `gemma-3n-e2b-it` | 1.1 GB | Mobile only |
| Higher quality chat | `gemma-3-1b-it` | 500 MB | All |
| Best quality, desktop | `phi-4-mini` | 2.4 GB | All |

---

## Complete cross-platform example

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:genesis_ai_sdk/genesis_ai_sdk.dart';
import 'package:genesis_ai_sdk/src/providers/gemma_provider.dart';
import 'package:path_provider/path_provider.dart';

Future<GemmaProvider> loadModel() async {
  final dir = await getApplicationDocumentsDirectory();
  final modelPath = '${dir.path}/qwen3-0.6b.litertlm';

  if (!await GemmaModelManager.isDownloaded(modelPath)) {
    await GemmaModelManager.download(
      modelId: 'qwen3-0.6b',
      destinationPath: modelPath,
      onProgress: (received, total) {
        if (total > 0) {
          final pct = (received / total * 100).round();
          debugPrint('Downloading… $pct%');
        }
      },
    );
  }

  return GemmaProvider(modelId: 'qwen3-0.6b', modelPath: modelPath);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize();

  final provider = await loadModel();
  final agent = AgenticAgent(
    provider: provider,
    systemPrompt: 'You are a helpful assistant.',
  );

  final response = await agent.chat('What is the capital of France?');
  debugPrint(response.text);

  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Done!')))));
}
```
