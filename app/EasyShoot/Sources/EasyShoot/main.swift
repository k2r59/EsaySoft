import AppKit

if MainActor.assumeIsolated({ AnnotationPreviewLauncher.runIfNeeded() }) { exit(0) }

// CLI transports must never register a competing GUI application with LaunchServices.
let delegate = MainActor.assumeIsolated { AppDelegate() }
if CommandLine.arguments.contains("--feature-tests") {
    Task.detached {do {try await runFeatureTests();exit(0)} catch {fputs("FAIL: \(error.localizedDescription)\n",stderr);exit(1)}}
    dispatchMain()
}
if CommandLine.arguments.contains("--self-test") {
    do { try MainActor.assumeIsolated { try runSelfTests(delegate) };exit(0) } catch { fputs("FAIL: \(error.localizedDescription)\n",stderr);exit(1) }
}
if CommandLine.arguments.contains("--mcp") {
    MCPServer(owner:delegate).serve()
    exit(0)
}
let app = NSApplication.shared
if CommandLine.arguments.contains("--capture-tests") {
    app.setActivationPolicy(.prohibited)
    Task { @MainActor in
        do { try await runCaptureTests(); exit(0) }
        catch { fputs("FAIL: \(error.localizedDescription)\n",stderr); exit(1) }
    }
    app.run(); exit(0)
}
if CommandLine.arguments.contains("--verify-screen-access") {
    Task { @MainActor in
        print("Screen access: \(CGPreflightScreenCaptureAccess())")
        do {
            let image=try await NativeScreenCapture.region(CGRect(x:0,y:0,width:64,height:64))
            print("Native screenshot: \(image.width) x \(image.height)")
        } catch { print("Capture check failed: \(error.localizedDescription)") }
        fflush(stdout);app.terminate(nil)
    }
    app.run();exit(0)
}
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
