import AVFoundation
import AppKit

struct VideoSegment:Identifiable,Equatable {
    var id=UUID()
    var start:Double
    var end:Double
    var speed:Double=1
    var duration:Double {(end-start)/speed}
}
enum VideoFraming:String,CaseIterable,Identifiable {
    case original="Original",landscape="16:9",portrait="9:16",square="1:1",classic="4:3"
    var id:String {rawValue}
    var ratio:Double? {switch self {case .original:return nil;case .landscape:return 16/9;case .portrait:return 9/16;case .square:return 1;case .classic:return 4/3}}
}
enum VideoQuality:String,CaseIterable,Identifiable {
    case original="Résolution source",fullHD="1080p",hd="720p"
    var id:String {rawValue}
    var maxSide:Double {switch self {case .original:return .infinity;case .fullHD:return 1920;case .hd:return 1280}}
}
struct VideoEditState:Equatable {
    var clips:[VideoSegment]
    var framing:VideoFraming = .original
    var cropX:Double=0.5
    var cropY:Double=0.5
    var volume:Float=1
    var muted=false
    var quality:VideoQuality = .fullHD
    var duration:Double {clips.reduce(0){$0+$1.duration}}
}
struct VideoRenderPlan {
    let composition:AVMutableComposition
    let videoComposition:AVMutableVideoComposition
    let audioMix:AVMutableAudioMix
    let size:CGSize
    let duration:Double
    func playerItem()->AVPlayerItem {let item=AVPlayerItem(asset:composition);item.videoComposition=videoComposition;item.audioMix=audioMix;item.audioTimePitchAlgorithm = .spectral;return item}
}
enum VideoEngine {
    static func failure(_ message:String)->NSError {NSError(domain:"EasyShoot.Video",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
    static func renderSize(crop:CGSize,quality:VideoQuality)->CGSize {
        let scale:Double
        if quality == .original {scale=1}
        else {
            let short:Double=quality == .hd ? 720:1080
            let long=short*16/9
            let maxWidth=crop.width>=crop.height ? long:short
            let maxHeight=crop.width>=crop.height ? short:long
            scale=min(1,maxWidth/crop.width,maxHeight/crop.height)
        }
        return CGSize(width:max(2,floor(crop.width*scale/2)*2),height:max(2,floor(crop.height*scale/2)*2))
    }
    static func build(url:URL,state:VideoEditState) async throws->VideoRenderPlan {
        let asset=AVURLAsset(url:url)
        let sourceDuration=try await asset.load(.duration).seconds
        guard sourceDuration.isFinite,sourceDuration>0,let source=try await asset.loadTracks(withMediaType:.video).first else{throw failure("Ce fichier ne contient pas de vidéo lisible.")}
        guard !state.clips.isEmpty,state.clips.count<=100 else{throw failure("Le montage doit contenir entre 1 et 100 segments.")}
        for clip in state.clips {
            guard clip.start.isFinite,clip.end.isFinite,clip.speed.isFinite,clip.start>=0,clip.end<=sourceDuration+0.02,clip.end-clip.start>=0.05,(0.25...4).contains(clip.speed) else{throw failure("Un segment dépasse la durée source ou possède une vitesse invalide.")}
        }
        guard state.volume.isFinite,(0...1).contains(state.volume),(0...1).contains(state.cropX),(0...1).contains(state.cropY) else{throw failure("Paramètres audio ou cadrage invalides.")}
        let naturalSize=try await source.load(.naturalSize),preferred=try await source.load(.preferredTransform)
        let oriented=CGRect(origin:.zero,size:naturalSize).applying(preferred)
        let width=abs(oriented.width),height=abs(oriented.height)
        guard width>=2,height>=2 else{throw failure("Les dimensions de la vidéo sont invalides.")}
        let aspect=state.framing.ratio ?? width/height
        let cropWidth=min(width,height*aspect),cropHeight=min(height,width/aspect)
        let cropX=(width-cropWidth)*state.cropX,cropY=(height-cropHeight)*state.cropY
        let output=renderSize(crop:CGSize(width:cropWidth,height:cropHeight),quality:state.quality)
        let scaleX=output.width/cropWidth,scaleY=output.height/cropHeight
        let transform=preferred.concatenating(CGAffineTransform(translationX:-oriented.minX-cropX,y:-oriented.minY-cropY)).concatenating(CGAffineTransform(scaleX:scaleX,y:scaleY))
        let composition=AVMutableComposition()
        guard let picture=composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid) else{throw failure("Impossible de créer la piste vidéo.")}
        let sourceAudio=state.muted ? []:try await asset.loadTracks(withMediaType:.audio)
        var sound:[(AVAssetTrack,AVMutableCompositionTrack)]=[]
        for audio in sourceAudio {if let track=composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid) {sound.append((audio,track))}}
        var cursor=CMTime.zero
        for clip in state.clips {
            try Task.checkCancellation()
            let start=CMTime(seconds:clip.start,preferredTimescale:60000),duration=CMTime(seconds:clip.end-clip.start,preferredTimescale:60000)
            let range=CMTimeRange(start:start,duration:duration)
            try picture.insertTimeRange(range,of:source,at:cursor)
            for (audio,track) in sound {
                let available=try await audio.load(.timeRange)
                let overlap=CMTimeRangeGetIntersection(range,otherRange:available)
                if overlap.duration.seconds>0 {let offset=CMTimeSubtract(overlap.start,start);try track.insertTimeRange(overlap,of:audio,at:CMTimeAdd(cursor,offset))}
            }
            let renderedDuration=CMTime(seconds:clip.duration,preferredTimescale:60000)
            composition.scaleTimeRange(CMTimeRange(start:cursor,duration:duration),toDuration:renderedDuration)
            cursor=CMTimeAdd(cursor,renderedDuration)
        }
        let layer=AVMutableVideoCompositionLayerInstruction(assetTrack:picture);layer.setTransform(transform,at:.zero)
        let instruction=AVMutableVideoCompositionInstruction();instruction.timeRange=CMTimeRange(start:.zero,duration:cursor);instruction.layerInstructions=[layer];instruction.backgroundColor=NSColor.black.cgColor
        let video=AVMutableVideoComposition();video.renderSize=output;video.frameDuration=CMTime(value:1,timescale:30);video.instructions=[instruction]
        let mix=AVMutableAudioMix();mix.inputParameters=sound.map{_,track in let p=AVMutableAudioMixInputParameters(track:track);p.setVolume(state.volume,at:.zero);return p}
        return VideoRenderPlan(composition:composition,videoComposition:video,audioMix:mix,size:output,duration:cursor.seconds)
    }
    static func exporter(plan:VideoRenderPlan)throws->AVAssetExportSession {
        guard let session=AVAssetExportSession(asset:plan.composition,presetName:AVAssetExportPresetHighestQuality) else{throw failure("Impossible de préparer l’export vidéo.")}
        session.timeRange=CMTimeRange(start:.zero,duration:CMTime(seconds:plan.duration,preferredTimescale:60000));session.audioTimePitchAlgorithm = .spectral;session.videoComposition=plan.videoComposition;session.audioMix=plan.audioMix;session.shouldOptimizeForNetworkUse=true
        return session
    }
}
