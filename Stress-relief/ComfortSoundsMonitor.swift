import Cocoa

// MARK: - 3. Danh mục 16 Background Sounds & Cấu hình Lưới Chuẩn Retina (@2x)
enum SoundTheme: String, CaseIterable {
    case balancedNoise, brightNoise, darkNoise
    case ocean, rain, stream, night, fire
    case babble, steam
    case airplane, boat, bus, train
    case rainOnRoof, quietNight

    var gridConfig: (blockSize: CGFloat, gap: CGFloat, softGrid: Bool) {
        switch self {
        case .balancedNoise, .brightNoise, .darkNoise:
            return (2.5, 0.5, false) // 12 hàng x 402 cột
        case .fire, .night, .rain, .quietNight, .babble:
            return (2.0, 0.5, false) // 15 hàng x 502 cột
        case .steam, .rainOnRoof, .stream, .ocean, .boat, .bus, .airplane, .train:
            return (1.5, 0.5, true)  // 20 hàng x 670 cột
        }
    }

    static func detect(from rawString: String) -> SoundTheme? {
        let s = rawString.lowercased()
        if s.contains("rainonroof") || s.contains("rain_on_roof") || s.contains("roof") { return .rainOnRoof }
        if s.contains("quietnight") || s.contains("quiet_night") || s.contains("quiet") { return .quietNight }
        if s.contains("balanced") || s.contains("whitenoise") || s.contains("white_noise") { return .balancedNoise }
        if s.contains("bright") || s.contains("pinknoise") || s.contains("pink_noise") { return .brightNoise }
        if s.contains("dark") || s.contains("brownnoise") || s.contains("brown_noise") { return .darkNoise }
        if s.contains("train") || s.contains("rail") { return .train }
        if s.contains("airplane") || s.contains("plane") || s.contains("cabin") || s.contains("flight") { return .airplane }
        if s.contains("stream") || s.contains("creek") || s.contains("brook") { return .stream }
        if s.contains("ocean") || s.contains("beach") || s.contains("waves") { return .ocean }
        if s.contains("boat") || s.contains("ferry") || s.contains("ship") || s.contains("sail") { return .boat }
        if s.contains("bus") || s.contains("coach") { return .bus }
        if s.contains("babble") || s.contains("crowd") || s.contains("chatter") || s.contains("cafe") { return .babble }
        if s.contains("steam") || s.contains("kettle") || s.contains("vapor") { return .steam }
        if s.contains("fire") || s.contains("camp") || s.contains("hearth") { return .fire }
        if s.contains("night") { return .night }
        if s.contains("rain") { return .rain }
        return nil
    }
}

// MARK: - 4. Bộ theo dõi Hearing (Background Sounds) của macOS
final class ComfortSoundsMonitor {
    private let domain = "com.apple.ComfortSounds" as CFString
    private let enabledKey = "comfortSoundsEnabled" as CFString
    private let volumeKey = "relativeVolume" as CFString
    private let possibleSoundKeys: [CFString] = [
        "ComfortSoundsSelectedSound" as CFString,
        "selectedSound" as CFString,
        "comfortSound" as CFString
    ]

    private(set) var currentTheme: SoundTheme = .stream
    private(set) var currentVolume: Double = 0.4
    private(set) var isEnabled: Bool = false

    private var lastSoundData: Data?
    private var lastSoundString: String?

    func pollSystemPreferences() {
        if let enabledVal = CFPreferencesCopyAppValue(enabledKey, domain) as? Bool {
            self.isEnabled = enabledVal
        } else if let enabledNum = CFPreferencesCopyAppValue(enabledKey, domain) as? NSNumber {
            self.isEnabled = enabledNum.boolValue
        } else {
            self.isEnabled = false
        }

        if let volNum = CFPreferencesCopyAppValue(volumeKey, domain) as? NSNumber {
            self.currentVolume = max(0.05, min(1.0, volNum.doubleValue))
        }

        for key in possibleSoundKeys {
            guard let rawVal = CFPreferencesCopyAppValue(key, domain) else { continue }
            if let str = rawVal as? String {
                if str == lastSoundString { break }
                if let detected = SoundTheme.detect(from: str) {
                    lastSoundString = str
                    self.currentTheme = detected
                    break
                }
            } else if let data = rawVal as? Data {
                if data == lastSoundData { break }
                if let detected = extractTheme(from: data) {
                    lastSoundData = data
                    self.currentTheme = detected
                    break
                }
            }
        }
    }

    private func extractTheme(from data: Data) -> SoundTheme? {
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            if let dict = plist as? [String: Any], let objects = dict["$objects"] as? [Any] {
                for obj in objects.reversed() {
                    if let str = obj as? String, !str.hasPrefix("$"), str != "HUComfortSound", str != "AXAsset",
                       let detected = SoundTheme.detect(from: str) {
                        return detected
                    }
                }
            }
            if let detected = SoundTheme.detect(from: String(describing: plist)) { return detected }
        }
        return SoundTheme.detect(from: String(decoding: data, as: UTF8.self))
    }
}
