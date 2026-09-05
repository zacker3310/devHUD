import Darwin
import Foundation

struct ProcessResourceSample {
    let rssBytes: UInt64
    let cpuSeconds: TimeInterval
}

enum ProcessInspector {
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(info.denom))
    }()

    static func cwd(pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        // Bounded to the array: never scan past MAXPATHLEN for a NUL.
        return withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static func startTime(pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
    }

    static func resources(pid: pid_t) -> ProcessResourceSample? {
        var usage = rusage_info_v4()
        // The C signature takes `rusage_info_t *`, but the kernel writes the
        // struct at that address. Pass the struct's own storage, not a pointer to
        // a pointer, or 296 bytes land on the stack.
        let status = withUnsafeMutablePointer(to: &usage) { ptr -> Int32 in
            UnsafeMutableRawPointer(ptr).withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard status == 0 else { return nil }
        let ticks = usage.ri_user_time &+ usage.ri_system_time
        let nanos = ticks &* timebase.numer / timebase.denom
        return ProcessResourceSample(rssBytes: usage.ri_resident_size, cpuSeconds: Double(nanos) / 1_000_000_000)
    }

    // Exact argv of a process, NUL-separated from the kernel, so a restart can
    // quote every token instead of trusting a shell-formatted string.
    static func arguments(pid: pid_t) -> ProcArgs? {
        guard pid > 0 else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return ProcArgs.parse(Data(buffer.prefix(size)))
    }

    static func projectName(cwd: String?) -> String? {
        guard let cwd else { return nil }
        let pkg = (cwd as NSString).appendingPathComponent("package.json")
        let data = FileManager.default.contents(atPath: pkg)
        return ProjectName.infer(cwd: cwd, packageJSON: data, home: NSHomeDirectory())
    }
}

// Layout of KERN_PROCARGS2: Int32 argc, the executable path, NUL padding,
// then argc NUL-terminated arguments, then the environment (ignored). The
// executable path is kept: a restart runs that binary, not a PATH lookup of
// whatever argv[0] claims to be.
struct ProcArgs: Equatable {
    let executable: String
    let arguments: [String]

    static func parse(_ data: Data) -> ProcArgs? {
        guard data.count > 4 else { return nil }
        let argc = Int(data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        guard argc > 0 else { return nil }
        let bytes = [UInt8](data)
        var index = 4
        var end = index
        while end < bytes.count, bytes[end] != 0 { end += 1 }
        let executable = String(decoding: bytes[index..<end], as: UTF8.self)
        guard executable.hasPrefix("/") else { return nil }
        index = end
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        var args: [String] = []
        while args.count < argc, index < bytes.count {
            var stop = index
            while stop < bytes.count, bytes[stop] != 0 { stop += 1 }
            args.append(String(decoding: bytes[index..<stop], as: UTF8.self))
            index = stop + 1
        }
        return args.count == argc ? ProcArgs(executable: executable, arguments: args) : nil
    }
}
