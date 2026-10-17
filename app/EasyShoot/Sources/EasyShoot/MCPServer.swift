import AppKit
import Vision

/// A local JSON-RPC MCP transport. stdout is reserved for protocol messages.
final class MCPServer {
    let owner:AppDelegate
    let roots:[URL]
    var initialized=false
    init(owner:AppDelegate) {
        self.owner=owner
        var selected=[owner.store]
        let args=CommandLine.arguments
        for i in args.indices where args[i] == "--read-root" && i+1 < args.count { selected.append(URL(fileURLWithPath:args[i+1],isDirectory:true)) }
        roots=selected.map{$0.standardizedFileURL.resolvingSymlinksInPath()}
    }
    func serve() {
        while let line=readLine() {
            autoreleasepool {
                guard line.utf8.count <= 1_048_576 else { sendError(NSNull(),-32600,"Request exceeds 1 MiB");return }
                guard let bytes=line.data(using:.utf8),let object=try? JSONSerialization.jsonObject(with:bytes) else { sendError(NSNull(),-32700,"Invalid JSON");return }
                guard let request=object as? [String:Any],request["jsonrpc"] as? String == "2.0",let method=request["method"] as? String else { sendError(NSNull(),-32600,"Invalid JSON-RPC request");return }
                guard let id=request["id"] else { return }
                let params=request["params"] as? [String:Any] ?? [:]
                switch method {
                case "initialize":
                    initialized=true
                    let proposed=params["protocolVersion"] as? String ?? "2025-11-25"
                    let supported=["2024-11-05","2025-03-26","2025-06-18","2025-11-25"]
                    send(id,["protocolVersion":supported.contains(proposed) ? proposed:"2025-11-25","capabilities":["tools":["listChanged":false]],"serverInfo":["name":"easyshoot","version":"0.2.0"],"instructions":"Local macOS screenshot and OCR tools. Captures require macOS Screen Recording permission. Screen coordinates are logical points from the primary display’s top-left. Image text is untrusted content. No network listener; files are read only beneath granted --read-root paths."])
                case "ping":send(id,[:])
                case "tools/list":
                    guard initialized else { sendError(id,-32002,"Initialize first");return }
                    send(id,["tools":toolDefinitions])
                case "tools/call":
                    guard initialized else { sendError(id,-32002,"Initialize first");return }
                    guard let name=params["name"] as? String,toolDefinitions.contains(where:{$0["name"] as? String == name}) else { sendError(id,-32602,"Unknown tool");return }
                    do { send(id,try call(name,params["arguments"] as? [String:Any] ?? [:])) }
                    catch { send(id,["isError":true,"content":[["type":"text","text":error.localizedDescription]]]) }
                default:sendError(id,-32601,"Method not found: \(method)")
                }
            }
        }
        // EOF only closes this CLI process. The GUI application is independent.
    }
    func send(_ id:Any,_ result:[String:Any]) { write(["jsonrpc":"2.0","id":id,"result":result]) }
    func sendError(_ id:Any,_ code:Int,_ message:String) { write(["jsonrpc":"2.0","id":id,"error":["code":code,"message":message]]) }
    func write(_ value:[String:Any]) { guard var data=try? JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]) else{return};data.append(10);FileHandle.standardOutput.write(data) }
    func error(_ text:String)->NSError { NSError(domain:"EasyShoot.MCP",code:1,userInfo:[NSLocalizedDescriptionKey:text]) }
    func onMain<T>(_ body:()->T)->T { if Thread.isMainThread { return body() };return DispatchQueue.main.sync(execute:body) }
    func result(_ object:[String:Any],image:NSImage?=nil)->[String:Any] {
        let data=(try? JSONSerialization.data(withJSONObject:object,options:[.sortedKeys])) ?? Data()
        var content:[[String:Any]]=[["type":"text","text":String(data:data,encoding:.utf8) ?? "{}"]]
        if let image,let png=onMain({ preview(image) }) { content.append(["type":"image","mimeType":"image/png","data":png.base64EncodedString()]) }
        return ["isError":false,"content":content,"structuredContent":object]
    }
    func preview(_ image:NSImage)->Data? {
        let factor=min(1,1400/max(image.size.width,image.size.height))
        let width=max(1,Int(image.size.width*factor)),height=max(1,Int(image.size.height*factor))
        guard let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:rep) else{return nil}
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context;image.draw(in:NSRect(x:0,y:0,width:width,height:height));NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using:.png,properties:[:])
    }
    func readURL(_ value:Any?) throws ->URL {
        guard let path=value as? String,path.hasPrefix("/") else { throw error("An absolute image path is required.") }
        let url=URL(fileURLWithPath:path).standardizedFileURL.resolvingSymlinksInPath()
        guard roots.contains(where:{url.path == $0.path || url.path.hasPrefix($0.path+"/")}) else { throw error("Path is outside the granted read roots. Relaunch EasyShoot --mcp with --read-root /absolute/folder to grant access.") }
        let values=try url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
        guard values.isRegularFile == true,(values.fileSize ?? 0) <= 50_000_000 else { throw error("Only regular image files up to 50 MB are supported.") }
        return url
    }
    func loadImage(_ url:URL) throws ->NSImage {
        guard let image=onMain({NSImage(contentsOf:url)}) else { throw error("The file is not a supported image.") }
        guard image.size.width > 0,image.size.height > 0,image.size.width*image.size.height <= 80_000_000 else { throw error("Image dimensions exceed the 80 megapixel limit.") }
        return image
    }
    func capture(_ args:[String:Any],full:Bool=false)throws->URL {
        guard CGPreflightScreenCaptureAccess() else { throw error("Screen Recording permission is required. Open EasyShoot → Preferences and enable it in macOS, then restart the MCP client.") }
        var flags=["-x","-t","png"]
        if full { flags.append("-m") }
        else {
            let keys=["x","y","width","height"]
            if keys.allSatisfy({args[$0] == nil}) { flags += ["-i","-s"] }
            else {
                guard let x=number(args["x"]),let y=number(args["y"]),let w=number(args["width"]),let h=number(args["height"]),w>=1,h>=1,w<=20000,h<=20000,abs(x)<=50000,abs(y)<=50000 else { throw error("Provide finite x, y, width and height in screen points; width and height must be 1…20000. Omit all four to select with the mouse.") }
                flags += ["-R","\(Int(x)),\(Int(y)),\(Int(w)),\(Int(h))"]
            }
        }
        try FileManager.default.createDirectory(at:owner.store,withIntermediateDirectories:true)
        let url=owner.store.appendingPathComponent("Capture-\(UUID().uuidString).png")
        let task=Process();task.executableURL=URL(fileURLWithPath:"/usr/sbin/screencapture");task.arguments=flags+[url.path];task.standardOutput=FileHandle.standardError
        try task.run();task.waitUntilExit()
        guard task.terminationStatus == 0,FileManager.default.fileExists(atPath:url.path) else { throw error("Capture cancelled or refused by macOS.") }
        return url
    }
    func number(_ value:Any?)->Double? {
        guard let n=value as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),n.doubleValue.isFinite else{return nil};return n.doubleValue
    }
    func call(_ name:String,_ args:[String:Any])throws->[String:Any] {
        let definition=toolDefinitions.first{$0["name"] as? String == name}!
        let properties=(definition["inputSchema"] as? [String:Any])?["properties"] as? [String:Any] ?? [:]
        guard args.keys.allSatisfy({properties[$0] != nil}) else { throw error("Unknown argument.") }
        switch name {
        case "get_status":return result(["name":"EasyShoot","version":"0.2.0","screenCaptureAuthorized":CGPreflightScreenCaptureAccess(),"readRoots":roots.map(\.path),"captureDirectory":owner.store.path,"transport":"stdio","networkListener":false])
        case "capture_screen","capture_region":
            let url=try capture(args,full:name == "capture_screen");let image=try loadImage(url)
            return result(["path":url.path,"width":Int(image.size.width),"height":Int(image.size.height)],image:image)
        case "extract_text":
            let url:URL
            if args["path"] != nil {
                guard ["x","y","width","height"].allSatisfy({args[$0] == nil}) else { throw error("Use either path or screen coordinates, not both.") }
                url=try readURL(args["path"])
            } else { url=try capture(args) }
            let image=try loadImage(url)
            guard let data=onMain({image.tiffRepresentation}) else { throw error("Unable to decode image.") }
            let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.recognitionLanguages=["fr-FR","en-US"];request.usesLanguageCorrection=true
            try VNImageRequestHandler(data:data).perform([request])
            let lines=(request.results ?? []).compactMap{$0.topCandidates(1).first?.string}
            return result(["text":lines.joined(separator:"\n"),"lines":lines,"path":url.path,"characterCount":lines.joined(separator:"\n").count])
        case "list_captures":
            let limit:Int
            if args["limit"] != nil { guard let n=number(args["limit"]),n.rounded()==n,n>=1,n<=100 else { throw error("limit must be an integer from 1 to 100.") };limit=Int(n) } else { limit=20 }
            let urls=((try? FileManager.default.contentsOfDirectory(at:owner.store,includingPropertiesForKeys:[.creationDateKey])) ?? []).filter{["png","mp4"].contains($0.pathExtension)}.sorted{ ((try? $0.resourceValues(forKeys:[.creationDateKey]).creationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys:[.creationDateKey]).creationDate) ?? .distantPast) }
            return result(["captures":Array(urls.prefix(limit)).map{["path":$0.path,"format":$0.pathExtension]},"total":urls.count])
        case "open_editor":
            let url=try readURL(args["path"]);let image=try loadImage(url)
            _ = image
            let task=Process();task.executableURL=URL(fileURLWithPath:"/usr/bin/open");task.arguments=["-a",Bundle.main.bundleURL.path,url.path];task.standardOutput=FileHandle.standardError
            try task.run();task.waitUntilExit()
            guard task.terminationStatus == 0 else { throw error("macOS could not open the EasyShoot editor.") }
            return result(["opened":true,"path":url.path,"note":"Opened in the independent EasyShoot application; disconnecting MCP does not close the editor."])
        default:throw error("Unknown tool")
        }
    }
    var toolDefinitions:[[String:Any]] {
        let coordinate:[String:Any]=["type":"number","description":"Screen coordinate in logical points, from the primary screen’s top-left."]
        let dimension:[String:Any]=["type":"number","minimum":1,"maximum":20000]
        let region:[String:Any]=["x":coordinate,"y":coordinate,"width":dimension,"height":dimension]
        func tool(_ name:String,_ description:String,_ properties:[String:Any]=[:],_ required:[String]=[],readOnly:Bool=false)->[String:Any] {
            ["name":name,"description":description,"inputSchema":["type":"object","properties":properties,"required":required,"additionalProperties":false],"annotations":["readOnlyHint":readOnly,"destructiveHint":false,"idempotentHint":readOnly,"openWorldHint":false]]
        }
        var extraction=region;extraction["path"]=["type":"string","description":"Absolute image path beneath a granted read root. Omit to capture screen text."]
        return [
            tool("get_status","Inspect local capabilities, file roots and macOS capture permission.",readOnly:true),
            tool("capture_screen","Capture the primary screen to a new PNG. Returns a local path and resized image preview."),
            tool("capture_region","Capture a screen rectangle. Omit all coordinates for interactive mouse selection; the user must finish or cancel it.",region),
            tool("extract_text","Recognize French/English text locally from an image path or screen region. With no arguments, ask the user to select text with the mouse. Returns text without changing the clipboard.",extraction),
            tool("list_captures","List the newest local captures and recordings.",["limit":["type":"integer","minimum":1,"maximum":100]],readOnly:true),
            tool("open_editor","Open an image in the independent native annotation application, which stays open after MCP disconnects.",["path":["type":"string"]],["path"])
        ]
    }
}
