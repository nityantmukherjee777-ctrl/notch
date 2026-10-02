#!/usr/bin/env python3
"""Run the existing simple tests with a small assertion runner when CLT's
Testing.framework cannot load. This is explicit, never a silent swift-test pass.
No sources or SDK/framework files are patched. Unsupported macros fail closed.
"""
import os
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parent.parent
os.chdir(root)
env = os.environ.copy()
env["CLANG_MODULE_CACHE_PATH"] = str(root / ".build/ModuleCache")
env["SWIFT_MODULECACHE_PATH"] = env["CLANG_MODULE_CACHE_PATH"]
env.setdefault("SDKROOT", "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk")
subprocess.run(["swift", "build", "--disable-sandbox", "--scratch-path", ".build", "--cache-path", ".build/cache"], env=env, check=True)
binpath = Path(subprocess.check_output(["swift", "build", "--show-bin-path", "--disable-sandbox"], env=env, text=True).strip())
out = root / ".build/compatible-tests"
out.mkdir(exist_ok=True)
calls = []
transformed = []
for path in sorted((root / "Tests/NotchCoreTests").glob("*.swift")):
    text = path.read_text()
    suite = None
    for line in text.splitlines():
        match = re.search(r"\bstruct (\w+Tests)\b", line)
        if match:
            suite = match[1]
        match = re.search(r"@Test func (\w+)\(\)([^\{]*)\{", line)
        if match:
            if not suite:
                raise SystemExit("Unrecognised test suite")
            name, flags = match.groups()
            call = ("try " if "throws" in flags else "") + ("await " if "async" in flags else "") + f"{suite}().{name}()"
            calls.append(f'        {call}\n        print("PASS: {suite}.{name}")')
    text = text.replace("import Testing", "").replace("@testable import Notch\n", "")
    text = re.sub(r"@Suite(?:\(\.serialized\))?\s*", "", text)
    text = text.replace("@Test ", "").replace("#expect(", "expect(").replace("#require(", "require(")
    if "@Test" in text or "#expect" in text or "#require" in text or "@Suite" in text:
        raise SystemExit("Unsupported test annotation; update the compatibility runner explicitly")
    target = out / path.name
    target.write_text(text)
    transformed.append(str(target))
runner = out / "Runner.swift"
runner.write_text('''import Foundation
var failures = 0
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try condition() { return } } catch { print("Assertion threw: \\(error)") }
    failures += 1; print("FAIL: \\(file):\\(line) \\(message)")
}
enum CheckError: Error { case missingValue }
func require<T>(_ value: T?) throws -> T { guard let value else { throw CheckError.missingValue }; return value }
@main struct Runner {
    @MainActor static func main() async throws {
''' + "\n".join(calls) + f'''
        print("Executed {len(calls)} tests; \\(failures) failed assertions (compatibility runner)")
        if failures > 0 {{ exit(1) }}
    }}
}}
''')
sources = [str(p) for p in sorted((root / "Sources/Notch").glob("*.swift")) if p.name != "main.swift"]
objects = [str(p) for p in (binpath / "NotchCore.build").glob("*.swift.o")]
sparkle = root / ".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", "-module-cache-path", env["CLANG_MODULE_CACHE_PATH"],
    "-I", str(binpath / "Modules"), "-F", str(sparkle), "-framework", "Sparkle",
    "-Xlinker", "-rpath", "-Xlinker", str(sparkle),
    *sources, *transformed, str(runner), *objects, "-o", str(out / "checks")], env=env, check=True)
subprocess.run([str(out / "checks")], env=env, check=True)
