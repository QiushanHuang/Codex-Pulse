import Foundation
import Darwin

@MainActor final class SnapshotObserver {
    private var source:DispatchSourceFileSystemObject?
    private var pending:DispatchWorkItem?
    private var lastSignature:String?
    private let url:URL
    private let changed:()->Void
    init(directory:URL,changed:@escaping ()->Void) {
        self.url=directory.appendingPathComponent("snapshot.json");self.changed=changed
        let fd=Darwin.open(directory.path,O_EVTONLY)
        guard fd>=0 else{return}
        let source=DispatchSource.makeFileSystemObjectSource(fileDescriptor:fd,eventMask:.write,queue:.main)
        source.setCancelHandler{Darwin.close(fd)}
        source.setEventHandler{[weak self] in MainActor.assumeIsolated {self?.schedule()}}
        self.source=source;source.resume()
    }
    private func schedule() {
        var fresh=url;fresh.removeAllCachedResourceValues()
        guard let values=try? fresh.resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey,.fileResourceIdentifierKey]) else{return}
        let signature="\(values.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values.fileSize ?? 0):\(String(describing:values.fileResourceIdentifier))"
        guard signature != lastSignature else{return}
        lastSignature=signature;pending?.cancel()
        let item=DispatchWorkItem{[weak self] in MainActor.assumeIsolated {self?.changed()}}
        pending=item;DispatchQueue.main.asyncAfter(deadline:.now()+0.12,execute:item)
    }
    deinit {pending?.cancel();source?.cancel()}
}
