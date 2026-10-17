import AppKit
import ImageIO

@MainActor func runCaptureTests() async throws {
    var checks = 0
    func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw NSError(domain: "EasyShoot.CaptureTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
        checks += 1
        print("PASS: \(message)")
    }

    let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
    for end in [NSPoint(x: 100, y: 80), NSPoint(x: 1000, y: 80),
                NSPoint(x: 100, y: 700), NSPoint(x: 1000, y: 700)] {
        let view = SelectionView(frame: frame)
        var result: CGRect?
        var calls = 0
        view.done = { result = $0; calls += 1 }
        view.begin(at: NSPoint(x: 500, y: 400))
        view.finish(at: end)
        view.cancel()
        try check(result == CGRect(x: min(500, end.x), y: min(400, end.y),
            width: abs(end.x - 500), height: abs(end.y - 400)) && calls == 1,
            "Sélection dans la direction \(end), avec une seule validation")
    }
    let clipped = SelectionView(frame: frame)
    clipped.begin(at: NSPoint(x: 600, y: 400))
    clipped.update(to: NSPoint(x: 9999, y: -999))
    try check(clipped.selection == CGRect(x: 600, y: 0, width: 680, height: 400),
              "La sélection reste dans les limites de l’écran")
    for cancel in [false, true] {
        let view = SelectionView(frame: frame)
        var cancelled = false
        view.done = { cancelled = $0 == nil }
        view.begin(at: NSPoint(x: 200, y: 200))
        if cancel { view.cancel() } else { view.finish(at: NSPoint(x: 201, y: 201)) }
        try check(cancelled, cancel ? "Échap annule la sélection" : "Un clic ne crée pas une capture vide")
    }

    let window = SelectionWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let view = SelectionView(frame: frame)
    window.contentView = view
    view.begin(at: NSPoint(x: 600, y: 400))
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: frame) else {
        throw NSError(domain: "EasyShoot.CaptureTests", code: 2)
    }
    let start = Date()
    for i in 0..<10_000 {
        autoreleasepool {
            view.update(to: NSPoint(x: (i * 37) % 1281, y: (i * 71) % 801))
            if i % 100 == 0 {
                view.layoutSubtreeIfNeeded()
                view.cacheDisplay(in: frame, to: bitmap)
            }
        }
    }
    try check(view.subviews.count == 2 && view.layer?.sublayers?.filter { $0 is CAShapeLayer }.count == 1,
              "10 000 mouvements et 100 rendus sans accumuler de vues ni de calques")
    print(String(format: "METRIC: sélection et rendus hors écran : %.3f s", Date().timeIntervalSince(start)))
    window.contentView = nil
    window.close()

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("EasyShoot-capture-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("test.png")
    guard let context = CGContext(data: nil, width: 4000, height: 3000, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "EasyShoot.CaptureTests", code: 3)
    }
    context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
    let original = context.makeImage()!
    try await NativeScreenCapture.savePNG(original, to: url)
    let assets = CaptureAssets()
    guard let preview = await assets.preview(for: url), let cached = await assets.preview(for: url) else {
        throw NSError(domain: "EasyShoot.CaptureTests", code: 4)
    }
    try check(preview.image.width == 640 && preview.image.height == 480, "L’aperçu 12 Mpx est décodé en 640 × 480")
    try check(preview.originalWidth == 4000 && preview.originalHeight == 3000, "Les dimensions originales restent disponibles")
    try check(preview === cached, "Un aperçu déjà chargé réutilise la même image en cache")
    try check(preview.memoryCost < 1_300_000, "Le bitmap de l’aperçu occupe moins de 1,3 Mo, contre 48 Mo pour l’original")
    let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
    let saved = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    try check(saved.width == 4000 && saved.height == 3000, "Le PNG enregistré conserve sa pleine résolution")
    print("METRIC: mémoire du bitmap miniature : \(preview.memoryCost) octets ; original : \(original.bytesPerRow * original.height) octets")
    let cropped = original.cropping(to: CGRect(x: 0, y: 0, width: 2000, height: 1000))!
    try await NativeScreenCapture.savePNG(cropped, to: url)
    let replacement = await assets.preview(for: url)
    try check(replacement !== preview && replacement?.originalWidth == 2000, "Remplacer un fichier invalide sa miniature")
    let missing = await assets.preview(for: directory.appendingPathComponent("missing.png"))
    try check(missing == nil, "Un fichier manquant ne provoque pas de plantage")
    try Data("invalid image".utf8).write(to: directory.appendingPathComponent("invalid.png"))
    let invalid = await assets.preview(for: directory.appendingPathComponent("invalid.png"))
    try check(invalid == nil, "Un fichier corrompu ne provoque pas de plantage")
    let entries = await assets.list(in: directory)
    try check(entries.contains(where: { $0.url.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() }), "La bibliothèque retrouve les captures enregistrées")

    let owner = AppDelegate()
    weak var releasedEditor: EditorController?
    autoreleasepool {
        let editor = EditorController(image: NSImage(cgImage: cropped, size: .zero), owner: owner)
        releasedEditor = editor
        owner.editors.append(editor)
        editor.window?.close()
    }
    try check(owner.editors.isEmpty && releasedEditor == nil, "Fermer l’éditeur libère son contrôleur et son image")
    weak var releasedPreview: QuickCaptureController?
    autoreleasepool {
        let quick = QuickCaptureController(url: url, owner: owner)
        releasedPreview = quick
        owner.quickCapture = quick
        quick.dismiss()
    }
    try check(owner.quickCapture == nil && releasedPreview == nil, "Fermer l’aperçu libère son contrôleur")
    print("\(checks) contrôles de capture et de mémoire réussis.")
}
