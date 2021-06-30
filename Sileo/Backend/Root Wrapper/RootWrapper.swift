import Foundation

#if targetEnvironment(macCatalyst)
class MacRootWrapper {
    static let shared = MacRootWrapper()
    
    var wrapperClass: LaunchAsRoot.Type
    
    init() {
        guard let bundleURL = Bundle.main.builtInPlugInsURL?.appendingPathComponent("SileoRootWrapper.bundle"),
              let bundle = Bundle(url: bundleURL),
              bundle.load(),
              let klass = objc_getClass("LaunchAsRoot") as? LaunchAsRoot.Type
        else {
            fatalError("Unable to initialize ability to spawn a process as root")
        }
        
        self.wrapperClass = klass
        _ = klass.shared
    }
    
    public func spawn(args: [String]) -> (Int, String) {
        guard !args.isEmpty,
              let launchPath = args.first
        else {
            fatalError("Found invalid args when spawning a process as root")
        }
        
        var arguments = args
        arguments.removeFirst()
        
        let stdoutString = self.wrapperClass.shared.spawn(withPath: launchPath, args: arguments)
        
        let status = stdoutString == nil ? -1 : 0
        let outputString = stdoutString ?? ""
        return (status, outputString)
    }
}
#endif

@discardableResult func spawn(command: String, args: [String]) -> (Int, String, String) {
    var pipestdout: [Int32] = [0, 0]
    var pipestderr: [Int32] = [0, 0]
    
    let bufsiz = Int(BUFSIZ)
    
    pipe(&pipestdout)
    pipe(&pipestderr)
    
    guard fcntl(pipestdout[0], F_SETFL, O_NONBLOCK) != -1 else {
        return (-1, "", "")
    }
    guard fcntl(pipestderr[0], F_SETFL, O_NONBLOCK) != -1 else {
        return (-1, "", "")
    }
    
    var fileActions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&fileActions)
    posix_spawn_file_actions_addclose(&fileActions, pipestdout[0])
    posix_spawn_file_actions_addclose(&fileActions, pipestderr[0])
    posix_spawn_file_actions_adddup2(&fileActions, pipestdout[1], STDOUT_FILENO)
    posix_spawn_file_actions_adddup2(&fileActions, pipestderr[1], STDERR_FILENO)
    posix_spawn_file_actions_addclose(&fileActions, pipestdout[1])
    posix_spawn_file_actions_addclose(&fileActions, pipestderr[1])
    
    let argv: [UnsafeMutablePointer<CChar>?] = args.map { $0.withCString(strdup) }
    defer { for case let arg? in argv { free(arg) } }
    
    var pid: pid_t = 0
    
    #if targetEnvironment(macCatalyst)
    let env = [ "PATH=/opt/procursus/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin" ]
    let proenv: [UnsafeMutablePointer<CChar>?] = env.map { $0.withCString(strdup) }
    defer { for case let pro? in proenv { free(pro) } }
    let spawnStatus = posix_spawn(&pid, command, &fileActions, nil, argv + [nil], proenv + [nil])
    #else
    let spawnStatus = posix_spawn(&pid, command, &fileActions, nil, argv + [nil], environ)
    #endif
    if spawnStatus != 0 {
        return (-1, "", "")
    }
    
    close(pipestdout[1])
    close(pipestderr[1])
    
    var stdoutStr = ""
    var stderrStr = ""
    
    let mutex = DispatchSemaphore(value: 0)
    
    let readQueue = DispatchQueue(label: "org.coolstar.sileo.command",
                                  qos: .userInitiated,
                                  attributes: .concurrent,
                                  autoreleaseFrequency: .inherit,
                                  target: nil)
    
    let stdoutSource = DispatchSource.makeReadSource(fileDescriptor: pipestdout[0], queue: readQueue)
    let stderrSource = DispatchSource.makeReadSource(fileDescriptor: pipestderr[0], queue: readQueue)
    
    stdoutSource.setCancelHandler {
        close(pipestdout[0])
        mutex.signal()
    }
    stderrSource.setCancelHandler {
        close(pipestderr[0])
        mutex.signal()
    }
    
    stdoutSource.setEventHandler {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufsiz)
        defer { buffer.deallocate() }
        
        let bytesRead = read(pipestdout[0], buffer, bufsiz)
        guard bytesRead > 0 else {
            if bytesRead == -1 && errno == EAGAIN {
                return
            }
            
            stdoutSource.cancel()
            return
        }
        
        let array = Array(UnsafeBufferPointer(start: buffer, count: bytesRead)) + [UInt8(0)]
        array.withUnsafeBufferPointer { ptr in
            let str = String(cString: unsafeBitCast(ptr.baseAddress, to: UnsafePointer<CChar>.self))
            stdoutStr += str
        }
    }
    stderrSource.setEventHandler {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufsiz)
        defer { buffer.deallocate() }
        
        let bytesRead = read(pipestderr[0], buffer, bufsiz)
        guard bytesRead > 0 else {
            if bytesRead == -1 && errno == EAGAIN {
                return
            }
            
            stderrSource.cancel()
            return
        }
        
        let array = Array(UnsafeBufferPointer(start: buffer, count: bytesRead)) + [UInt8(0)]
        array.withUnsafeBufferPointer { ptr in
            let str = String(cString: unsafeBitCast(ptr.baseAddress, to: UnsafePointer<CChar>.self))
            stderrStr += str
        }
    }
    
    stdoutSource.resume()
    stderrSource.resume()
    
    mutex.wait()
    mutex.wait()
    var status: Int32 = 0
    waitpid(pid, &status, 0)
    
    return (Int(status), stdoutStr, stderrStr)
}

@discardableResult func spawnAsRoot(args: [String]) -> (Int, String, String) {
    #if targetEnvironment(simulator) || TARGET_SANDBOX
    fatalError("Commands should not be run in sandbox")
    #elseif targetEnvironment(macCatalyst)
    let (status, output) = MacRootWrapper.shared.spawn(args: args)
    return (status, output, "")
    #else
    guard let giveMeRootPath = Bundle.main.path(forAuxiliaryExecutable: "giveMeRoot") else {
        return (-1, "", "")
    }
    return spawn(command: giveMeRootPath, args: ["giveMeRoot"] + args)
    #endif
}

func deleteFileAsRoot(_ url: URL) {
    #if targetEnvironment(simulator) || TARGET_SANDBOX
    try? FileManager.default.removeItem(at: url)
    #else
    spawnAsRoot(args: [CommandPath.rm, "-f", "\(url.path)"])
    #endif
}

func hardLinkAsRoot(from: URL, to: URL) {
    deleteFileAsRoot(to)
    
    #if targetEnvironment(simulator) || TARGET_SANDBOX
    try? FileManager.default.createSymbolicLink(at: to, withDestinationURL: from)
    #else
    spawnAsRoot(args: [CommandPath.ln, "\(from.path)", "\(to.path)"])
    spawnAsRoot(args: [CommandPath.chown, "0:0", "\(to.path)"])
    spawnAsRoot(args: [CommandPath.chmod, "0644", "\(to.path)"])
    #endif
}

func moveFileAsRoot(from: URL, to: URL) {
    deleteFileAsRoot(to)
    
    #if targetEnvironment(simulator) || TARGET_SANDBOX
    try? FileManager.default.moveItem(at: from, to: to)
    #else
    spawnAsRoot(args: [CommandPath.mv, "\(from.path)", "\(to.path)"])
    spawnAsRoot(args: [CommandPath.chown, "0:0", "\(to.path)"])
    spawnAsRoot(args: [CommandPath.chmod, "0644", "\(to.path)"])
    #endif
}

public class CommandPath {
    // swiftlint:disable identifier_name
    static var mv: String {
        #if targetEnvironment(macCatalyst)
        return "/bin/mv"
        #else
        return "/usr/bin/mv"
        #endif
    }
    
    static var chown: String {
        #if targetEnvironment(macCatalyst)
        return "/usr/sbin/chown"
        #else
        return "/usr/bin/chown"
        #endif
    }
    
    static var chmod: String {
        #if targetEnvironment(macCatalyst)
        return "/bin/chmod"
        #else
        return "/usr/bin/chmod"
        #endif
    }
    // swiftlint:disable identifier_name
    static var ln: String {
        #if targetEnvironment(macCatalyst)
        return "/bin/ln"
        #else
        return "/usr/bin/ln"
        #endif
    }
    // swiftlint:disable identifier_name
    static var rm: String {
        #if targetEnvironment(macCatalyst)
        return "/bin/rm"
        #else
        return "/usr/bin/rm"
        #endif
    }
    
    static var mkdir: String {
        #if targetEnvironment(macCatalyst)
        return "/bin/mkdir"
        #else
        return "/usr/bin/mkdir"
        #endif
    }
    // swiftlint:disable identifier_name
    static var cp: String {
        #if targetEnvironment(macCatalyst)
        return "/bin/cp"
        #else
        return "/usr/bin/cp"
        #endif
    }
    
    static var aptmark: String {
        #if targetEnvironment(macCatalyst)
        return "/opt/procursus/bin/apt-mark"
        #else
        return "/usr/bin/apt-mark"
        #endif
    }
    
    static var dpkgdeb: String {
        #if targetEnvironment(macCatalyst)
        return "/opt/procursus/bin/dpkg-deb"
        #else
        return "/usr/bin/dpkg-deb"
        #endif
    }
    
    static var dpkg: String {
        #if targetEnvironment(macCatalyst)
        return "/opt/procursus/bin/dpkg"
        #else
        return "/usr/bin/dpkg"
        #endif
    }
    
    static var aptget: String {
        #if targetEnvironment(macCatalyst)
        return "/opt/procursus/bin/apt-get"
        #else
        return "/usr/bin/apt-get"
        #endif
    }
    
    static var aptkey: String {
        #if targetEnvironment(macCatalyst)
        return "/opt/procursus/bin/apt-key"
        #else
        return "/usr/bin/apt-key"
        #endif
    }
    // swiftlint:disable identifier_name
    static var sh: String {
        "/bin/sh"
    }
    
    static var sileolists: String {
        #if targetEnvironment(macCatalyst)
        return "/opt/procursus/var/lib/apt/sileolists"
        #else
        return "/var/lib/apt/sileolists"
        #endif
    }
    
    static var lists: String {
        #if targetEnvironment(macCatalyst)
        return "/opt/procursus/var/lib/apt/lists"
        #else
        return "/var/lib/apt/lists"
        #endif
    }
    
    static var whoami: String {
        "/usr/bin/whoami"
    }
    
    static var uicache: String {
        "/usr/bin/uicache"
    }
    
    static var dpkgDir: URL {
        #if targetEnvironment(macCatalyst)
        return URL(fileURLWithPath: "/opt/procursus/Library/dpkg")
        #elseif targetEnvironment(simulator) || TARGET_SANDBOX
        return Bundle.main.bundleURL
        #else
        return URL(fileURLWithPath: "/Library/dpkg")
        #endif
    }
    
    static var sourcesListD: String {
        #if targetEnvironment(macCatalyst)
        return "/opt/procursus/etc/apt/sources.list.d"
        #else
        return "/etc/apt/sources.list.d"
        #endif
    }
    
    static var RepoIcon: String {
        #if targetEnvironment(macCatalyst)
        return "RepoIcon"
        #else
        return "CydiaIcon"
        #endif
    }
    
    static var lazyPrefix: String {
        #if targetEnvironment(macCatalyst)
        return "/opt/procursus"
        #else
        return ""
        #endif
    }
    
    static var group: String {
        #if targetEnvironment(macCatalyst)
        return "\(NSUserName()):staff"
        #else
        return "mobile:mobile"
        #endif
    }
}
