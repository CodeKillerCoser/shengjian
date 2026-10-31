import Foundation
import Security
import CryptoKit

// Export exactly the existing identity selected by its public certificate hash.
// The caller passes the password through a private file, never command-line text.
guard CommandLine.arguments.count == 4 else { fatalError("Usage: exporter <sha1> <password-file> <p12-file>") }
let fingerprint = CommandLine.arguments[1].uppercased()
let password = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
let query: [String: Any] = [kSecClass as String: kSecClassIdentity, kSecReturnRef as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
var result: CFTypeRef?
let status = SecItemCopyMatching(query as CFDictionary, &result)
guard status == errSecSuccess, let identities = result as? [SecIdentity] else { fatalError("Signing identity lookup failed: \(status)") }
for identity in identities {
    var certificate: SecCertificate?
    guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { continue }
    let hash = Insecure.SHA1.hash(data: SecCertificateCopyData(certificate) as Data).map { String(format: "%02X", $0) }.joined()
    guard hash == fingerprint else { continue }
    var parameters = SecItemImportExportKeyParameters()
    parameters.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
    let passwordCF = password as CFString
    parameters.passphrase = Unmanaged.passUnretained(passwordCF)
    var data: CFData?
    let exported = withExtendedLifetime(passwordCF) { SecItemExport(identity, .formatPKCS12, [], &parameters, &data) }
    guard exported == errSecSuccess, let data else { fatalError("Identity export failed: \(exported)") }
    let url = URL(fileURLWithPath: CommandLine.arguments[3])
    try (data as Data).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    print("Selected identity exported for encrypted Secrets upload")
    exit(0)
}
fatalError("Expected signing certificate was not found")
