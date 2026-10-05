//
//  HSFSSupport.swift
//  Hammerspoon 2
//

import Foundation
import Darwin

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
    /// `utimensat`/`futimens`. Omitted JS numbers arrive as `NaN` (or `0`), which map to
    /// `UTIME_NOW`.
    static func timespec(fromSeconds seconds: Double) -> Darwin.timespec {
        guard seconds.isFinite, seconds != 0 else {
            return Darwin.timespec(tv_sec: 0, tv_nsec: Int(UTIME_NOW))
        }
        let whole = seconds.rounded(.down)
        return Darwin.timespec(tv_sec: Int(whole), tv_nsec: Int((seconds - whole) * 1_000_000_000))
    }

    /// Build the `[accessTime, modificationTime]` pair for `utimensat`/`futimens`.
    /// The access time defaults to the modification time, matching LuaFileSystem's `touch`.
    static func touchTimes(modificationDate: Double, accessDate: Double) -> [Darwin.timespec] {
        let modification = timespec(fromSeconds: modificationDate)
        let hasAccess = accessDate.isFinite && accessDate != 0
        let access = hasAccess ? timespec(fromSeconds: accessDate) : modification
        return [access, modification]
    }
}
