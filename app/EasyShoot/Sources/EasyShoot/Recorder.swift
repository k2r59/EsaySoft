import AppKit
import ScreenCaptureKit
import AVFoundation

final class Recorder: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var url: URL?
    private var changed: (() -> Void)?
    private var completed: ((URL) -> Void)?
    private(set) var isRecording=false
    @MainActor func start(url:URL, completed:@escaping(URL)->Void, changed:@escaping () -> Void) async throws {
        let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
        guard let display=content.displays.first(where:{$0.displayID == CGMainDisplayID()}) else { throw NSError(domain:"EasyShoot",code:1,userInfo:[NSLocalizedDescriptionKey:"Aucun écran disponible."]) }
        let own=content.applications.filter{$0.processID == ProcessInfo.processInfo.processIdentifier}
        let filter=SCContentFilter(display:display,excludingApplications:own,exceptingWindows:[])
        let config=SCStreamConfiguration();config.width=display.width;config.height=display.height;config.minimumFrameInterval=CMTime(value:1,timescale:30);config.showsCursor=true;config.capturesAudio=true;config.excludesCurrentProcessAudio=true
        let rec=SCRecordingOutputConfiguration();rec.outputURL=url;rec.outputFileType = .mp4;rec.videoCodecType = .h264
        let output=SCRecordingOutput(configuration:rec,delegate:self)
        let stream=SCStream(filter:filter,configuration:config,delegate:self)
        try stream.addRecordingOutput(output)
        self.stream=stream;self.output=output;self.url=url;self.changed=changed;self.completed=completed
        do { try await stream.startCapture();isRecording=true } catch { self.stream=nil;self.output=nil;throw error }
    }
    @MainActor func stop() async throws { try await stream?.stopCapture();isRecording=false }
    func recordingOutputDidFinishRecording(_ recordingOutput:SCRecordingOutput) {
        DispatchQueue.main.async { self.isRecording=false;self.stream=nil;self.output=nil;self.changed?();if let url=self.url { self.completed?(url) } }
    }
    func recordingOutput(_ recordingOutput:SCRecordingOutput,didFailWithError error:Error) { finished(error) }
    func stream(_ stream:SCStream,didStopWithError error:Error) { finished(error) }
    private func finished(_ error:Error) { DispatchQueue.main.async { self.isRecording=false;self.stream=nil;self.output=nil;self.changed?();let a=NSAlert(error:error);a.runModal() } }
}
