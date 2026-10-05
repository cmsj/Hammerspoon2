//
//  HSFSSupport.swift
//  Hammerspoon 2
//

import Foundation
import Darwin
import JavaScriptCore

/// Helpers shared by `HSFSModule` and `HSFile`.
@_documentation(visibility: private)
enum HSFSSupport {

    // MARK: - Errors

    /// Build a `lastError` object (`{code, message}`) from a POSIX errno value.
    /// The code is the symbolic errno name, e.g. `"ENOENT"`.
    static func errorInfo(errno code: Int32) -> [String: Any] {
        ["code": errnoName(code), "message": unsafe String(cString: strerror(code))]
    }

    /// The symbolic name of a POSIX errno value, e.g. `2` → `"ENOENT"`.
    static func errnoName(_ code: Int32) -> String {
        errnoNames[code] ?? "UNKNOWN"
    }

    /// Darwin errno values and their names. Aliases (e.g. `EWOULDBLOCK` for `EAGAIN`) are omitted;
    /// the canonical name is reported.
    private static let errnoNames: [Int32: String] = [
        EPERM: "EPERM", ENOENT: "ENOENT", ESRCH: "ESRCH", EINTR: "EINTR", EIO: "EIO",
        ENXIO: "ENXIO", E2BIG: "E2BIG", ENOEXEC: "ENOEXEC", EBADF: "EBADF", ECHILD: "ECHILD",
        EDEADLK: "EDEADLK", ENOMEM: "ENOMEM", EACCES: "EACCES", EFAULT: "EFAULT",
        ENOTBLK: "ENOTBLK", EBUSY: "EBUSY", EEXIST: "EEXIST", EXDEV: "EXDEV", ENODEV: "ENODEV",
        ENOTDIR: "ENOTDIR", EISDIR: "EISDIR", EINVAL: "EINVAL", ENFILE: "ENFILE", EMFILE: "EMFILE",
        ENOTTY: "ENOTTY", ETXTBSY: "ETXTBSY", EFBIG: "EFBIG", ENOSPC: "ENOSPC", ESPIPE: "ESPIPE",
        EROFS: "EROFS", EMLINK: "EMLINK", EPIPE: "EPIPE", EDOM: "EDOM", ERANGE: "ERANGE",
        EAGAIN: "EAGAIN", EINPROGRESS: "EINPROGRESS", EALREADY: "EALREADY", ENOTSOCK: "ENOTSOCK",
        EDESTADDRREQ: "EDESTADDRREQ", EMSGSIZE: "EMSGSIZE", EPROTOTYPE: "EPROTOTYPE",
        ENOPROTOOPT: "ENOPROTOOPT", EPROTONOSUPPORT: "EPROTONOSUPPORT",
        ESOCKTNOSUPPORT: "ESOCKTNOSUPPORT", ENOTSUP: "ENOTSUP", EPFNOSUPPORT: "EPFNOSUPPORT",
        EAFNOSUPPORT: "EAFNOSUPPORT", EADDRINUSE: "EADDRINUSE", EADDRNOTAVAIL: "EADDRNOTAVAIL",
        ENETDOWN: "ENETDOWN", ENETUNREACH: "ENETUNREACH", ENETRESET: "ENETRESET",
        ECONNABORTED: "ECONNABORTED", ECONNRESET: "ECONNRESET", ENOBUFS: "ENOBUFS",
        EISCONN: "EISCONN", ENOTCONN: "ENOTCONN", ESHUTDOWN: "ESHUTDOWN",
        ETOOMANYREFS: "ETOOMANYREFS", ETIMEDOUT: "ETIMEDOUT", ECONNREFUSED: "ECONNREFUSED",
        ELOOP: "ELOOP", ENAMETOOLONG: "ENAMETOOLONG", EHOSTDOWN: "EHOSTDOWN",
        EHOSTUNREACH: "EHOSTUNREACH", ENOTEMPTY: "ENOTEMPTY", EPROCLIM: "EPROCLIM",
        EUSERS: "EUSERS", EDQUOT: "EDQUOT", ESTALE: "ESTALE", EREMOTE: "EREMOTE",
        EBADRPC: "EBADRPC", ERPCMISMATCH: "ERPCMISMATCH", EPROGUNAVAIL: "EPROGUNAVAIL",
        EPROGMISMATCH: "EPROGMISMATCH", EPROCUNAVAIL: "EPROCUNAVAIL", ENOLCK: "ENOLCK",
        ENOSYS: "ENOSYS", EFTYPE: "EFTYPE", EAUTH: "EAUTH", ENEEDAUTH: "ENEEDAUTH",
        EPWROFF: "EPWROFF", EDEVERR: "EDEVERR", EOVERFLOW: "EOVERFLOW", EBADEXEC: "EBADEXEC",
        EBADARCH: "EBADARCH", ESHLIBVERS: "ESHLIBVERS", EBADMACHO: "EBADMACHO",
        ECANCELED: "ECANCELED", EIDRM: "EIDRM", ENOMSG: "ENOMSG", EILSEQ: "EILSEQ",
        ENOATTR: "ENOATTR", EBADMSG: "EBADMSG", EMULTIHOP: "EMULTIHOP", ENODATA: "ENODATA",
        ENOLINK: "ENOLINK", ENOSR: "ENOSR", ENOSTR: "ENOSTR", EPROTO: "EPROTO", ETIME: "ETIME",
        EOPNOTSUPP: "EOPNOTSUPP", ENOPOLICY: "ENOPOLICY", ENOTRECOVERABLE: "ENOTRECOVERABLE",
        EOWNERDEAD: "EOWNERDEAD", EQFULL: "EQFULL",
    ]

    /// Build a `lastError` object with an explicit code and message.
    static func errorInfo(code: String, message: String) -> [String: Any] {
        ["code": code, "message": message]
    }

    /// Build a `lastError` object from a Swift/Foundation error, recovering the underlying
    /// POSIX errno where Foundation provides one.
    static func errorInfo(from error: Error) -> [String: Any] {
        let nsError = error as NSError
        let message = nsError.localizedDescription

        if nsError.domain == NSPOSIXErrorDomain {
            return ["code": errnoName(Int32(nsError.code)), "message": message]
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain {
            return ["code": errnoName(Int32(underlying.code)), "message": message]
        }
        if nsError.domain == NSCocoaErrorDomain {
            switch CocoaError.Code(rawValue: nsError.code) {
            case .fileNoSuchFile, .fileReadNoSuchFile:
                return ["code": "ENOENT", "message": message]
            case .fileWriteFileExists:
                return ["code": "EEXIST", "message": message]
            case .fileReadNoPermission, .fileWriteNoPermission:
                return ["code": "EACCES", "message": message]
            case .fileWriteOutOfSpace:
                return ["code": "ENOSPC", "message": message]
            case .fileWriteVolumeReadOnly:
                return ["code": "EROFS", "message": message]
            default:
                break
            }
        }
        return ["code": "UNKNOWN", "message": message]
    }

    // MARK: - Metadata

    /// Map `st_mode` file-type bits to the type names used by `hs.fs.attributes()`.
    static func typeName(forMode mode: mode_t) -> String {
        switch mode & S_IFMT {
        case S_IFREG:  return "file"
        case S_IFDIR:  return "directory"
        case S_IFLNK:  return "symlink"
        case S_IFSOCK: return "socket"
        case S_IFCHR:  return "characterSpecial"
        case S_IFBLK:  return "blockSpecial"
        default:       return "unknown"
        }
    }

    /// Convert a `stat` result into the attributes object returned to JavaScript.
    static func attributes(from st: Darwin.stat) -> [String: Any] {
        let creationDate = Double(st.st_birthtimespec.tv_sec)
                         + Double(st.st_birthtimespec.tv_nsec) / 1_000_000_000
        let modDate = Double(st.st_mtimespec.tv_sec)
                    + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000

        return [
            "size":             Int(st.st_size),
            "type":             typeName(forMode: st.st_mode),
            "permissions":      Int(st.st_mode & 0o7777),
            "ownerID":          Int(st.st_uid),
            "groupID":          Int(st.st_gid),
            "inode":            Int(st.st_ino),
            "creationDate":     creationDate,
            "modificationDate": modDate,
        ]
    }

    // MARK: - Timestamps

    /// Convert a JS timestamp (seconds since the Unix epoch) to a `timespec` for
    /// `utimensat`/`futimens`. `nil` (an omitted argument) maps to `UTIME_NOW`; `0` is a genuine
    /// timestamp (the epoch).
    ///
    /// - Returns: The `timespec`, or `nil` if `seconds` is `NaN`, infinite, or outside the range of `time_t`.
    static func timespec(fromSeconds seconds: Double?) -> Darwin.timespec? {
        guard let seconds else {
            return Darwin.timespec(tv_sec: 0, tv_nsec: Int(UTIME_NOW))
        }
        let whole = seconds.rounded(.down)
        guard seconds.isFinite, let wholeSeconds = Int(exactly: whole) else { return nil }
        let nanoseconds = min(Int((seconds - whole) * 1_000_000_000), 999_999_999)
        return Darwin.timespec(tv_sec: wholeSeconds, tv_nsec: nanoseconds)
    }

    /// Build the `[accessTime, modificationTime]` pair for `utimensat`/`futimens`. Pass `nil` for an
    /// omitted argument. An omitted access time defaults to the modification time, matching
    /// LuaFileSystem's `touch`.
    ///
    /// - Returns: The pair, or `nil` if either timestamp is invalid.
    static func touchTimes(modificationDate: Double?, accessDate: Double?) -> [Darwin.timespec]? {
        guard let modification = timespec(fromSeconds: modificationDate) else { return nil }
        guard let accessDate else { return [modification, modification] }
        guard let access = timespec(fromSeconds: accessDate) else { return nil }
        return [access, modification]
    }

    // MARK: - Arguments

    /// Resolve an optional numeric argument of a JSExport method, distinguishing an omitted argument
    /// (or explicit `undefined`) from an explicit value. Both arrive in Swift as `NaN`, but an explicit
    /// `NaN` is an invalid value that must not silently select a default (e.g. permissive file modes).
    ///
    /// - Parameters:
    ///   - value: The bridged argument value.
    ///   - index: The argument's position in the JS call.
    /// - Returns: `nil` if the argument was omitted, otherwise `value` (which may be `NaN`). When called
    ///   from Swift rather than JS, `NaN` (the Swift default) counts as omitted.
    static func optionalNumberArgument(_ value: Double, at index: Int) -> Double? {
        if let arguments = JSContext.currentArguments() as? [JSValue] {
            return index < arguments.count && !arguments[index].isUndefined ? value : nil
        }
        return value.isNaN ? nil : value
    }

    // MARK: - JS values

    /// Bridge a value to JS, mapping `nil` to an explicit JS `null`.
    ///
    /// JSExport bridges a Swift `nil` return to `undefined`, so APIs documented as returning `null`
    /// (and checked with `=== null`, as the TypeScript types encourage) must return a `JSValue`.
    ///
    /// - Returns: The bridged value, or `nil` (undefined) only if there is no current JS context.
    static func jsValueOrNull(_ value: Any?) -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        guard let value else { return JSValue(nullIn: context) }
        return JSValue(object: value, in: context)
    }

    // MARK: - Permissions

    /// Validate a JS permissions argument: it must be an integer between `0` and `0o7777`.
    ///
    /// `Double` parameters are used for permissions so that an omitted argument (which arrives as
    /// `NaN`) is rejected rather than silently becoming mode `0`.
    ///
    /// Logs a warning for values that look like an octal literal typed in decimal (e.g. `755`
    /// instead of `0o755`), since those silently set the setuid/setgid/sticky bits.
    ///
    /// - Returns: The permission bits, or `nil` if `value` is not a valid permissions value.
    static func permissionBits(_ value: Double, function: String) -> mode_t? {
        guard let bits = Int(exactly: value), (0...0o7777).contains(bits) else { return nil }
        let decimal = String(bits)
        if bits > 0o777, decimal.count == 3, decimal.allSatisfy({ "01234567".contains($0) }) {
            AKWarning("\(function): permissions \(decimal) set special mode bits (0o\(String(bits, radix: 8))); did you mean 0o\(decimal)?")
        }
        return mode_t(bits)
    }
}
