import Foundation
import Darwin
import SSH2

/// Small libssh2 wrapper. NMSSH's CFSocket connection path does not work
/// reliably on current iOS releases, so this uses a normal BSD socket and
/// libssh2 directly. Every operation runs on the same private queue.
final class SSHService {
    private let queue = DispatchQueue(label: "com.catmint.openwrtmonitor.ssh")
    private var session: OpaquePointer?
    private var socketFD: Int32 = -1

    func connect(host: String, port: Int, user: String, password: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.closeLocked()
                libssh2_init(0)

                let fd = socket(AF_INET, SOCK_STREAM, 0)
                guard fd >= 0 else {
                    continuation.resume(throwing: AppError.message("无法创建 TCP socket"))
                    return
                }

                var timeout = timeval(tv_sec: 10, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout,
                           socklen_t(MemoryLayout<timeval>.size))
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout,
                           socklen_t(MemoryLayout<timeval>.size))

                var address = sockaddr_in()
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = in_port_t(UInt16(port).bigEndian)
                let parsed = host.withCString { pointer in
                    inet_pton(AF_INET, pointer, &address.sin_addr)
                }
                guard parsed == 1 else {
                    Darwin.close(fd)
                    continuation.resume(throwing: AppError.message("路由器地址不是有效的 IPv4"))
                    return
                }

                let connectResult = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                guard connectResult == 0 else {
                    let code = errno
                    Darwin.close(fd)
                    continuation.resume(throwing: AppError.message(
                        "TCP 连接失败：\(String(cString: strerror(code)))（errno \(code)）"
                    ))
                    return
                }

                guard let ssh = libssh2_session_init_ex(nil, nil, nil, nil) else {
                    Darwin.close(fd)
                    continuation.resume(throwing: AppError.message("libssh2 初始化失败"))
                    return
                }
                libssh2_session_set_blocking(ssh, 1)

                guard libssh2_session_handshake(ssh, fd) == 0 else {
                    let message = Self.lastError(ssh)
                    libssh2_session_free(ssh)
                    Darwin.close(fd)
                    continuation.resume(throwing: AppError.message("SSH 握手失败：\(message)"))
                    return
                }

                let authResult = user.withCString { userPointer in
                    password.withCString { passwordPointer in
                        libssh2_userauth_password_ex(
                            ssh,
                            userPointer,
                            UInt32(user.utf8.count),
                            passwordPointer,
                            UInt32(password.utf8.count),
                            nil
                        )
                    }
                }
                guard authResult == 0 else {
                    let message = Self.lastError(ssh)
                    "auth failed".withCString { description in
                        "".withCString { language in
                            libssh2_session_disconnect_ex(ssh, 11, description, language)
                        }
                    }
                    libssh2_session_free(ssh)
                    Darwin.close(fd)
                    continuation.resume(throwing: AppError.message("SSH 密码认证失败：\(message)"))
                    return
                }

                self.session = ssh
                self.socketFD = fd
                continuation.resume()
            }
        }
    }

    func execute(_ command: String) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            queue.async {
                guard let session = self.session else {
                    continuation.resume(throwing: AppError.notConnected)
                    return
                }
                guard let channel = "session".withCString({ channelType in
                    libssh2_channel_open_ex(
                        session,
                        channelType,
                        7,
                        2 * 1024 * 1024,
                        32768,
                        nil,
                        0
                    )
                }) else {
                    continuation.resume(throwing: AppError.message(
                        "打开 SSH 通道失败：\(Self.lastError(session))"
                    ))
                    return
                }
                defer {
                    libssh2_channel_free(channel)
                }
                let execResult = command.withCString { pointer in
                    "exec".withCString { request in
                        libssh2_channel_process_startup(
                            channel,
                            request,
                            4,
                            pointer,
                            UInt32(command.utf8.count)
                        )
                    }
                }
                guard execResult == 0 else {
                    continuation.resume(throwing: AppError.message(
                        "执行 SSH 命令失败：\(Self.lastError(session))"
                    ))
                    return
                }

                var output = Data()
                output.reserveCapacity(16 * 1024)
                var buffer = [CChar](repeating: 0, count: 16 * 1024)
                // Blocking mode should never spin, but a socket timeout can surface
                // as EAGAIN. Back off with a sleep and a hard deadline instead of
                // hammering the channel in a tight loop (that used to burn phone
                // CPU and keep the router's shell busy).
                let deadline = Date().addingTimeInterval(30)
                while true {
                    let read = buffer.withUnsafeMutableBufferPointer { pointer in
                        libssh2_channel_read_ex(
                            channel,
                            0,
                            pointer.baseAddress,
                            pointer.count
                        )
                    }
                    if read > 0 {
                        output.append(contentsOf: buffer.prefix(read).map { UInt8(bitPattern: $0) })
                    } else if read == 0 {
                        break
                    } else if read == Int(LIBSSH2_ERROR_EAGAIN) {
                        if Date() > deadline {
                            continuation.resume(throwing: AppError.message("读取 SSH 输出超时"))
                            return
                        }
                        usleep(20_000)
                    } else {
                        continuation.resume(throwing: AppError.message(
                            "读取 SSH 输出失败：\(Self.lastError(session))"
                        ))
                        return
                    }
                }
                continuation.resume(returning: String(decoding: output, as: UTF8.self))
            }
        }
    }

    func disconnect() {
        queue.async {
            self.closeLocked()
        }
    }

    private func closeLocked() {
        if socketFD >= 0 {
            Darwin.shutdown(socketFD, SHUT_RDWR)
        }
        if let session {
            "bye".withCString { description in
                "".withCString { language in
                    libssh2_session_disconnect_ex(session, 11, description, language)
                }
            }
            libssh2_session_free(session)
            self.session = nil
        }
        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }
    }

    private static func lastError(_ session: OpaquePointer) -> String {
        var message: UnsafeMutablePointer<CChar>?
        var length: Int32 = 0
        let code = libssh2_session_last_error(session, &message, &length, 0)
        if let message {
            return String(cString: message)
        }
        return "libssh2 错误 \(code)"
    }
}
