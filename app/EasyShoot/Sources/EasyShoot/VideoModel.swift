import AppKit
import AVKit
import SwiftUI

final class VideoEditorModel:ObservableObject {
    let url:URL
    unowned let owner:AppDelegate
    let player=AVPlayer()
    @Published var state=VideoEditState(clips:[])
    @Published var selected:UUID?
    @Published var sourceDuration=0.0
    @Published var sourceSize=CGSize.zero
    @Published var time=0.0
    @Published var playing=false
    @Published var loading=true
    @Published var previewUpdating=false
    @Published var errorMessage:String?
    @Published var thumbnails:[NSImage]=[]
    @Published var trimStart=0.0
    @Published var trimEnd=0.0
    @Published var exporting=false
    @Published var exportProgress:Float=0
    @Published var exportNotice=""
    @Published var hasAudio=false
    @Published var undoCount=0
    private var history:[VideoEditState]=[]
    private var rebuild:Task<Void,Never>?
    private var thumbnailTask:Task<Void,Never>?
    private var closed=false
    private var exportedState:VideoEditState?
    private var exportTask:Task<Void,Never>?
    private var exporter:AVAssetExportSession?
    private var observer:Any?
    private var plan:VideoRenderPlan?
    private var gestureBefore:VideoEditState?
    var selectedClip:VideoSegment? {state.clips.first{$0.id == selected}}
    var duration:Double {state.duration}
    var selectedIndex:Int? {state.clips.firstIndex{$0.id == selected}}
    var canMoveEarlier:Bool {(selectedIndex ?? 0)>0}
    var canMoveLater:Bool {guard let selectedIndex else{return false};return selectedIndex<state.clips.count-1}
    var canSplit:Bool {var cursor=0.0;for clip in state.clips {if time>cursor+0.05 && time<cursor+clip.duration-0.05 {return true};cursor+=clip.duration};return false}
    var canPanX:Bool {guard let aspect=state.framing.ratio,sourceSize.height>0 else{return false};return sourceSize.width/sourceSize.height>aspect+0.001}
    var canPanY:Bool {guard let aspect=state.framing.ratio,sourceSize.height>0 else{return false};return sourceSize.width/sourceSize.height<aspect-0.001}
    var outputSize:CGSize {plan?.size ?? .zero}
    init(url:URL,owner:AppDelegate) {
        self.url=url;self.owner=owner
        observer=player.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.05,preferredTimescale:600),queue:.main) { [weak self] t in
            guard let self,!self.previewUpdating else{return}
            if t.seconds.isFinite {self.time=t.seconds}
            if self.time>=self.duration-0.04 && self.playing {self.player.pause();self.playing=false}
        }
    }
    @MainActor func load() async {
        do {
            let asset=AVURLAsset(url:url)
            guard let track=try await asset.loadTracks(withMediaType:.video).first else{throw VideoEngine.failure("Aucune piste vidéo dans ce fichier.")}
            sourceDuration=try await asset.load(.duration).seconds
            guard sourceDuration.isFinite,sourceDuration>=0.05 else{throw VideoEngine.failure("La vidéo est trop courte ou illisible.")}
            let rect=CGRect(origin:.zero,size:try await track.load(.naturalSize)).applying(try await track.load(.preferredTransform));sourceSize=CGSize(width:abs(rect.width),height:abs(rect.height))
            hasAudio = !(try await asset.loadTracks(withMediaType:.audio)).isEmpty
            state.clips=[VideoSegment(start:0,end:sourceDuration)];selected=state.clips[0].id;syncTrim()
            try await buildPreview()
            loading=false
        } catch is CancellationError {} catch {errorMessage=error.localizedDescription;loading=false}
    }
    func select(_ id:UUID) {selected=id;syncTrim()}
    func syncTrim() {if let clip=selectedClip {trimStart=clip.start;trimEnd=clip.end}}
    func remember(_ previous:VideoEditState) {history.append(previous);if history.count>40 {history.removeFirst()};undoCount=history.count}
    func change(_ mutation:(inout VideoEditState)->Void) {
        guard !exporting,!loading else{return}
        let previous=state;mutation(&state)
        guard state != previous else{return}
        if gestureBefore == nil {remember(previous)}
        syncTrim();schedulePreview()
    }
    func gesture(_ active:Bool) {if active {gestureBefore=state} else if let before=gestureBefore {gestureBefore=nil;if before != state {remember(before)}}}
    func schedulePreview() {rebuild?.cancel();rebuild=Task { @MainActor in try? await Task.sleep(for:.milliseconds(180));guard !Task.isCancelled else{return};do {try await buildPreview()} catch is CancellationError {} catch {errorMessage=error.localizedDescription}}}
    @MainActor func buildPreview() async throws {
        guard !closed else{throw CancellationError()}
        previewUpdating=true;defer {previewUpdating=false}
        let snapshot=state,savedTime=min(time,max(0,snapshot.duration-0.05)),wasPlaying=playing
        let newPlan=try await VideoEngine.build(url:url,state:snapshot)
        try Task.checkCancellation()
        guard snapshot == state else{return}
        plan=newPlan;player.pause();player.replaceCurrentItem(with:newPlan.playerItem());await player.seek(to:CMTime(seconds:savedTime,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero);time=savedTime
        if wasPlaying {player.play()}
        thumbnailTask?.cancel()
        thumbnailTask=Task { @MainActor [weak self] in
            let generator=AVAssetImageGenerator(asset:newPlan.composition);generator.videoComposition=newPlan.videoComposition;generator.maximumSize=CGSize(width:240,height:140)
            var images=[NSImage]()
            for i in 0..<10 {
                guard !Task.isCancelled else{return}
                let t=CMTime(seconds:max(0,newPlan.duration*Double(i)/10),preferredTimescale:600)
                if let frame=try? await generator.image(at:t) {images.append(NSImage(cgImage:frame.image,size:.zero))}
            }
            guard let self,!Task.isCancelled,!self.closed,self.state == snapshot else{return}
            self.thumbnails=images
        }
    }
    func playPause() {guard !loading,!exporting,!previewUpdating else{return};if playing {player.pause();playing=false} else {if time>=duration-0.08 {seek(0)};player.play();playing=true}}
    func seek(_ seconds:Double) {if playing {player.pause();playing=false};let target=min(max(0,seconds),max(0,duration-0.01));time=target;player.seek(to:CMTime(seconds:target,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero)}
    func applyTrim() {
        guard let id=selected,let clip=selectedClip,trimStart>=0,trimEnd<=sourceDuration,trimEnd-trimStart>=0.05 else{errorMessage="Garde au moins 0,05 seconde et reste dans la durée source.";return}
        let a=trimStart,b=trimEnd;change {s in if let i=s.clips.firstIndex(where:{$0.id == id}) {s.clips[i]=VideoSegment(id:clip.id,start:a,end:b,speed:clip.speed)}}
    }
    func split() {
        var cursor=0.0
        for (index,clip) in state.clips.enumerated() {
            if time>cursor+0.05 && time<cursor+clip.duration-0.05 {
                let sourcePoint=clip.start+(time-cursor)*clip.speed
                let first=VideoSegment(id:clip.id,start:clip.start,end:sourcePoint,speed:clip.speed),second=VideoSegment(start:sourcePoint,end:clip.end,speed:clip.speed)
                change {$0.clips.replaceSubrange(index...index,with:[first,second])};select(second.id);return
            }
            cursor+=clip.duration
        }
        errorMessage="Place la tête de lecture à l’intérieur d’un segment pour le diviser."
    }
    func removeSelected() {guard state.clips.count>1,let id=selected else{return};change {$0.clips.removeAll{$0.id == id}};selected=state.clips.first?.id;syncTrim()}
    func moveSelected(_ offset:Int) {guard let id=selected,let i=state.clips.firstIndex(where:{$0.id == id}),state.clips.indices.contains(i+offset) else{return};change {$0.clips.swapAt(i,i+offset)}}
    func undo() {guard !exporting,let previous=history.popLast() else{return};state=previous;undoCount=history.count;if !state.clips.contains(where:{$0.id == selected}) {selected=state.clips.first?.id};syncTrim();schedulePreview()}
    func reset() {change {$0=VideoEditState(clips:[VideoSegment(start:0,end:sourceDuration)])};select(state.clips[0].id)}
    func export() {
        guard !exporting,!loading,!state.clips.isEmpty else{return}
        player.pause();playing=false;exporting=true;exportProgress=0;errorMessage=nil
        let snapshot=state,output=owner.store.appendingPathComponent("Montage-\(UUID().uuidString).mp4")
        exportTask=Task { @MainActor in
            var progressTask:Task<Void,Never>?
            do {
                try FileManager.default.createDirectory(at:owner.store,withIntermediateDirectories:true)
                let render=try await VideoEngine.build(url:url,state:snapshot);try Task.checkCancellation()
                let session=try VideoEngine.exporter(plan:render);exporter=session
                progressTask=Task { @MainActor in while !Task.isCancelled {exportProgress=session.progress;try? await Task.sleep(for:.milliseconds(150))}}
                try await withTaskCancellationHandler {try await session.export(to:output,as:.mp4)} onCancel: {session.cancelExport()}
                try Task.checkCancellation();progressTask?.cancel();exportProgress=1;exporter=nil;exporting=false;exportedState=snapshot;exportNotice="Montage exporté · l’original est conservé";owner.showQuickCapture(output)
            } catch {progressTask?.cancel();exporter=nil;exporting=false;try? FileManager.default.removeItem(at:output);if !Task.isCancelled && !(error is CancellationError) && (error as NSError).code != NSUserCancelledError {errorMessage=error.localizedDescription}}
        }
    }
    func cancelExport() {exportTask?.cancel();exporter?.cancelExport()}
    var hasUnexportedChanges:Bool {undoCount>0 && state != exportedState}
    func close() {closed=true;thumbnailTask?.cancel();rebuild?.cancel();player.pause();playing=false;if let observer {player.removeTimeObserver(observer);self.observer=nil}}
    static func clock(_ value:Double)->String {let safe=value.isFinite ? max(0,value):0;return String(format:"%02d:%02d.%02d",Int(safe)/60,Int(safe)%60,Int(safe*100)%100)}
}
