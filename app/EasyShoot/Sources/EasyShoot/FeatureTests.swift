import AVFoundation
import AppKit
import AudioToolbox

func featureCheck(_ condition:Bool,_ description:String)throws {
    guard condition else{throw NSError(domain:"EasyShoot.Tests",code:1,userInfo:[NSLocalizedDescriptionKey:description])}
    print("PASS: \(description)")
}
func syntheticPage(width:Int,height:Int)throws->CGImage {
    var pixels=[UInt8](repeating:255,count:width*height*4)
    for y in 0..<height {for x in 0..<width {
        let row=y/24
        let inside=y%24>=6 && y%24<=15 && x>18 && x<width-20 && ((x/7+row*13) % 17)<(row%9+5)
        let i=(y*width+x)*4
        if inside {pixels[i]=UInt8((row*31)%160);pixels[i+1]=UInt8((row*53)%160);pixels[i+2]=UInt8((row*71)%160)}
        else {pixels[i]=UInt8(235+(row%17));pixels[i+1]=UInt8(236+(row%16));pixels[i+2]=245}
        if x<10 {pixels[i]=UInt8(y%251);pixels[i+1]=UInt8((y/5)%251);pixels[i+2]=70}
    }}
    let provider=CGDataProvider(data:Data(pixels) as CFData)!
    return CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
}
func runScrollingTests(directory:URL)throws {
    let page=try syntheticPage(width:320,height:2200)
    let positions=[0,217,504,723,1001]
    let frames=positions.map {page.cropping(to:CGRect(x:0,y:$0,width:320,height:480))!}
    var accumulator=ScrollAccumulator()
    for (index,frame) in frames.enumerated() {
        let match=try accumulator.append(frame)
        try featureCheck(match.kind == .shifted,"Défilement : portion \(index+1) reconnue")
        if index>0 {try featureCheck(match.offset == positions[index]-positions[index-1],"Raccord exact à \(match.offset) pixels")}
    }
    let duplicate=try accumulator.append(frames.last!)
    try featureCheck(duplicate.kind == .duplicate,"Une portion identique n’est pas ajoutée deux fois")
    let result=try ScrollStitcher.assemble(accumulator.strips)
    try featureCheck(result.height == 1481 && result.width == 320,"Assemblage aux dimensions exactes, sans lignes répétées")
    let expected=page.cropping(to:CGRect(x:0,y:0,width:320,height:1481))!
    try featureCheck(try ScrollStitcher.Raster(result).pixels == ScrollStitcher.Raster(expected).pixels,"Les pixels de l’assemblage correspondent à la page d’origine")
    let unrelated=page.cropping(to:CGRect(x:0,y:1700,width:320,height:480))!
    try featureCheck(try ScrollStitcher.match(frames.last!,unrelated).kind == .unmatched,"Un saut sans recouvrement est refusé")
    try ScrollStitcher.writePNG(result,to:directory.appendingPathComponent("scroll-result.png"))
    try ScrollStitcher.writePNG(page,to:directory.appendingPathComponent("scroll-source.png"))
    let retina=try syntheticPage(width:640,height:3600)
    let r1=retina.cropping(to:CGRect(x:0,y:0,width:640,height:960))!,r2=retina.cropping(to:CGRect(x:0,y:431,width:640,height:960))!
    let precise=try ScrollStitcher.match(r1,r2)
    try featureCheck(precise.kind == .shifted && precise.offset == 431,"Raccord Retina affiné au pixel près")
}

func createVideoFixture(url:URL,rotated:Bool=false) async throws {
    try? FileManager.default.removeItem(at:url)
    let writer=try AVAssetWriter(outputURL:url,fileType:.mov)
    let video=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:320,AVVideoHeightKey:240])
    if rotated {video.transform=CGAffineTransform(a:0,b:1,c:-1,d:0,tx:240,ty:0)}
    let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:video,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:320,kCVPixelBufferHeightKey as String:240])
    let audio=AVAssetWriterInput(mediaType:.audio,outputSettings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:48000,AVNumberOfChannelsKey:1,AVEncoderBitRateKey:64000])
    writer.add(video);writer.add(audio)
    guard writer.startWriting() else{throw writer.error ?? VideoEngine.failure("Création de la vidéo de test impossible.")};writer.startSession(atSourceTime:.zero)
    var asbd=AudioStreamBasicDescription(mSampleRate:48000,mFormatID:kAudioFormatLinearPCM,mFormatFlags:kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,mBytesPerPacket:2,mFramesPerPacket:1,mBytesPerFrame:2,mChannelsPerFrame:1,mBitsPerChannel:16,mReserved:0)
    var format:CMAudioFormatDescription?
    guard CMAudioFormatDescriptionCreate(allocator:kCFAllocatorDefault,asbd:&asbd,layoutSize:0,layout:nil,magicCookieSize:0,magicCookie:nil,extensions:nil,formatDescriptionOut:&format) == noErr else{throw VideoEngine.failure("Format audio de test invalide.")}
    let count=48000*3
    var samples=(0..<count).map{Int16(sin(Double($0)*2*Double.pi*440/48000)*6000)}
    var block:CMBlockBuffer?
    CMBlockBufferCreateWithMemoryBlock(allocator:kCFAllocatorDefault,memoryBlock:nil,blockLength:count*2,blockAllocator:kCFAllocatorDefault,customBlockSource:nil,offsetToData:0,dataLength:count*2,flags:0,blockBufferOut:&block)
    samples.withUnsafeMutableBytes {bytes in _ = CMBlockBufferReplaceDataBytes(with:bytes.baseAddress!,blockBuffer:block!,offsetIntoDestination:0,dataLength:count*2)}
    var timing=CMSampleTimingInfo(duration:CMTime(value:1,timescale:48000),presentationTimeStamp:.zero,decodeTimeStamp:.invalid)
    var sample:CMSampleBuffer?,size=2
    let status=CMSampleBufferCreateReady(allocator:kCFAllocatorDefault,dataBuffer:block,formatDescription:format,sampleCount:count,sampleTimingEntryCount:1,sampleTimingArray:&timing,sampleSizeEntryCount:1,sampleSizeArray:&size,sampleBufferOut:&sample)
    guard status == noErr,let sample else{throw VideoEngine.failure("Buffer audio de test invalide : \(status)")}
    while !audio.isReadyForMoreMediaData {try await Task.sleep(for:.milliseconds(5))}
    guard audio.append(sample) else{throw writer.error ?? VideoEngine.failure("Écriture audio impossible.")};audio.markAsFinished()
    for i in 0..<90 {
        while !video.isReadyForMoreMediaData {if writer.status == .failed {throw writer.error!};try await Task.sleep(for:.milliseconds(5))}
        var pixel:CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault,adaptor.pixelBufferPool!,&pixel)
        guard let pixel else{throw VideoEngine.failure("Buffer vidéo absent.")}
        CVPixelBufferLockBaseAddress(pixel,[])
        let bytes=CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to:UInt8.self),stride=CVPixelBufferGetBytesPerRow(pixel)
        for y in 0..<240 {for x in 0..<320 {let j=y*stride+x*4;bytes[j]=i>=60 ? 220:20;bytes[j+1]=(30..<60).contains(i) ? 220:20;bytes[j+2]=i<30 ? 220:20;bytes[j+3]=255}}
        CVPixelBufferUnlockBaseAddress(pixel,[])
        guard adaptor.append(pixel,withPresentationTime:CMTime(value:Int64(i),timescale:30)) else{throw writer.error ?? VideoEngine.failure("Écriture vidéo impossible.")}
    }
    video.markAsFinished();await writer.finishWriting()
    guard writer.status == .completed else{throw writer.error ?? VideoEngine.failure("Finalisation de la vidéo de test impossible.")}
}
func exportTest(_ plan:VideoRenderPlan,to url:URL) async throws {
    try? FileManager.default.removeItem(at:url)
    let exporter=try VideoEngine.exporter(plan:plan);try await exporter.export(to:url,as:.mp4)
}
func runVideoTests(directory:URL) async throws {
    try featureCheck(VideoEngine.renderSize(crop:CGSize(width:3000,height:3000),quality:.fullHD) == CGSize(width:1080,height:1080),"1080p carré produit 1080 × 1080, sans dépasser la qualité choisie")
    try featureCheck(VideoEngine.renderSize(crop:CGSize(width:2160,height:3840),quality:.fullHD) == CGSize(width:1080,height:1920),"1080p vertical produit 1080 × 1920")
    try featureCheck(VideoEngine.renderSize(crop:CGSize(width:3840,height:2160),quality:.hd) == CGSize(width:1280,height:720),"720p paysage produit 1280 × 720")
    let source=directory.appendingPathComponent("source.mov");try await createVideoFixture(url:source)
    var state=VideoEditState(clips:[VideoSegment(start:2,end:3,speed:2),VideoSegment(start:0,end:1)])
    state.framing = .square;state.quality = .original;state.volume=0.5
    let plan=try await VideoEngine.build(url:source,state:state)
    try featureCheck(abs(plan.duration-1.5)<0.04,"Montage : coupe, ordre des segments et vitesse respectés")
    try featureCheck(plan.size == CGSize(width:240,height:240),"Recadrage carré sans agrandir la source")
    let output=directory.appendingPathComponent("montage.mp4");try await exportTest(plan,to:output)
    let asset=AVURLAsset(url:output)
    let duration=try await asset.load(.duration).seconds
    try featureCheck(abs(duration-1.5)<0.08,"Le MP4 exporté possède la durée attendue")
    try featureCheck(!(try await asset.loadTracks(withMediaType:.audio)).isEmpty,"Le son est conservé après coupe et changement de vitesse")
    let generator=AVAssetImageGenerator(asset:asset);generator.appliesPreferredTrackTransform=true;generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero
    let first=try await generator.image(at:CMTime(seconds:0.15,preferredTimescale:600)).image
    let second=try await generator.image(at:CMTime(seconds:0.9,preferredTimescale:600)).image
    func color(_ image:CGImage)throws->(Int,Int,Int) {let raster=try ScrollStitcher.Raster(image);let i=(raster.height/2*raster.width+raster.width/2)*4;return (Int(raster.pixels[i]),Int(raster.pixels[i+1]),Int(raster.pixels[i+2]))}
    let a=try color(first),b=try color(second)
    try featureCheck(a.2>a.0+100 && b.0>b.2+100,"Les images exportées suivent l’ordre bleu puis rouge du montage")
    state.muted=true
    let muted=try await VideoEngine.build(url:source,state:state),mutedURL=directory.appendingPathComponent("muted.mp4")
    try await exportTest(muted,to:mutedURL)
    try featureCheck((try await AVURLAsset(url:mutedURL).loadTracks(withMediaType:.audio)).isEmpty,"Retirer le son supprime réellement la piste audio du MP4")
    let rotated=directory.appendingPathComponent("rotated.mov");try await createVideoFixture(url:rotated,rotated:true)
    var portrait=VideoEditState(clips:[VideoSegment(start:0,end:1)]);portrait.framing = .portrait;portrait.quality = .original
    let portraitPlan=try await VideoEngine.build(url:rotated,state:portrait)
    try featureCheck(portraitPlan.size == CGSize(width:180,height:320),"L’orientation source est respectée lors du recadrage vertical")
    try await exportTest(portraitPlan,to:directory.appendingPathComponent("portrait.mp4"))
    var invalid=state;invalid.clips=[VideoSegment(start:0,end:100)]
    do {_ = try await VideoEngine.build(url:source,state:invalid);throw VideoEngine.failure("Le montage invalide aurait dû être refusé.")}
    catch let error as NSError {try featureCheck(error.localizedDescription.contains("dépasse"),"Un segment hors de la source est refusé")}
    let originalDuration=try await AVURLAsset(url:source).load(.duration).seconds
    try featureCheck(abs(originalDuration-3)<0.04,"La source vidéo reste intacte après tous les exports")
}
@MainActor func runScrollSessionTests(directory:URL) async throws {
    let page=try syntheticPage(width:320,height:2200)
    let frames=[0,217,217,900,900,300,300].map{page.cropping(to:CGRect(x:0,y:$0,width:320,height:480))!}
    // Keep the unowned production coordinator alive throughout this isolated session.
    let owner=AppDelegate()
    let tested=ScrollingSession(rect:CGRect(x:0,y:0,width:320,height:480),owner:owner)
    var index=0
    tested.snapshotProvider={let image=frames[min(index,frames.count-1)];index+=1;return image}
    tested.outputDirectory=directory
    var exported:URL?
    tested.completed={exported=$0}
    await tested.sample(force:true)
    try featureCheck(tested.count == 1,"Session défilante : première image capturée")
    await tested.sample()
    try featureCheck(tested.count == 1,"La session attend une image stable pendant le défilement")
    await tested.sample()
    try featureCheck(tested.count == 2 && tested.height == 697,"La session ajoute la portion stabilisée")
    await tested.sample();await tested.sample()
    try featureCheck(tested.warning && tested.count == 2,"Le raccord incertain affiche une alerte et conserve l’assemblage")
    await tested.sample(force:true)
    try featureCheck(!tested.warning && tested.count == 3,"La session reprend après correction du défilement")
    await tested.finish()
    try featureCheck(exported != nil && FileManager.default.fileExists(atPath:exported!.path),"Terminer enregistre le PNG et déclenche l’aperçu de résultat")
    let denied=ScrollingSession(rect:CGRect(x:0,y:0,width:320,height:480),owner:owner)
    var attempts=0
    denied.snapshotProvider={attempts+=1;throw NativeScreenCapture.permissionError()}
    denied.begin()
    try await Task.sleep(for:.milliseconds(1800))
    try featureCheck(denied.paused && attempts == 1,"Un refus d’autorisation met la capture défilante en pause sans boucle de nouvelles demandes")
    denied.cancel()
    withExtendedLifetime(owner) {}
}
func runFeatureTests() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("EasyShoot-feature-tests")
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    try runScrollingTests(directory:directory)
    try await runScrollSessionTests(directory:directory)
    try await runVideoTests(directory:directory)
    print("Contrôles capture défilante et montage réussis : \(directory.path)")
}
