import AppKit
import Vision

@MainActor func runSelfTests(_ owner:AppDelegate) throws {
    func check(_ condition:Bool,_ message:String) throws { if !condition { throw NSError(domain:"EasyShoot.SelfTest",code:1,userInfo:[NSLocalizedDescriptionKey:message]) };print("PASS: \(message)") }
    guard let image=owner.demoImage() else { throw NSError(domain:"EasyShoot.SelfTest",code:2) }
    let canvas=AnnotationView(image:image)
    canvas.marks=[Mark(tool:.arrow,points:[NSPoint(x:500,y:400),NSPoint(x:800,y:400)],color:.systemOrange,width:8),Mark(tool:.redact,points:[NSPoint(x:100,y:100),NSPoint(x:900,y:540)],color:.black)]
    let rendered=canvas.rendered()
    guard let data=rendered.tiffRepresentation,let rep=NSBitmapImageRep(data:data),let png=rep.representation(using:.png,properties:[:]) else { throw NSError(domain:"EasyShoot.SelfTest",code:3) }
    try check(rep.pixelsWide == 1000 && rep.pixelsHigh == 640,"L’export conserve 1000 × 640 pixels, y compris sur écran Retina")
    let center=rep.colorAt(x:500,y:320)!.usingColorSpace(.deviceRGB)!
    try check(center.redComponent < 0.01 && center.greenComponent < 0.01 && center.blueComponent < 0.01 && center.alphaComponent > 0.99,"Le masquage remplace les pixels par du noir opaque")
    let directory=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("EasyShoot-tests")
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    try png.write(to:directory.appendingPathComponent("redaction.png"))
    if let source=NSBitmapImageRep(data:image.tiffRepresentation!)?.representation(using:.png,properties:[:]) { try source.write(to:directory.appendingPathComponent("ocr-source.png")) }
    canvas.marks.removeLast();try check(canvas.marks.count == 1,"L’annulation retire uniquement la dernière annotation")
    let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.recognitionLanguages=["fr-FR","en-US"]
    try VNImageRequestHandler(data:image.tiffRepresentation!).perform([request])
    let text=(request.results ?? []).compactMap{$0.topCandidates(1).first?.string}.joined(separator:"\n")
    try check(text.lowercased().contains("easyshoot"),"Vision reconnaît le titre EasyShoot en local")
    try check(text.lowercased().contains("capture"),"Vision reconnaît le texte de démonstration")
    print("Tous les contrôles ont réussi. Export de contrôle : \(directory.path)")
}
