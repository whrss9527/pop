import Foundation

/// Wi-Fi 二维码：`WIFI:T:WPA;S:网络名;P:密码;;`（反斜杠转义 ; , : \）
enum WiFiCode {
    struct Network: Equatable {
        var ssid: String
        var password: String?
        /// WPA、WEP……；开放网络为 nil
        var security: String?
        var hidden: Bool
    }

    static func parse(_ text: String) -> Network? {
        guard text.uppercased().hasPrefix("WIFI:") else { return nil }
        var fields: [String: String] = [:]
        var key: String?
        var current = ""
        var escaping = false
        for character in text.dropFirst(5) {
            if escaping {
                current.append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == ":", key == nil {
                key = current.uppercased()
                current = ""
            } else if character == ";" {
                if let key {
                    fields[key] = current
                }
                key = nil
                current = ""
            } else {
                current.append(character)
            }
        }
        // 最后一项漏了分号也认
        if let key, !current.isEmpty {
            fields[key] = current
        }
        guard let ssid = fields["S"], !ssid.isEmpty else { return nil }
        let security = fields["T"].flatMap { $0.isEmpty || $0.lowercased() == "nopass" ? nil : $0 }
        let password = fields["P"].flatMap { $0.isEmpty ? nil : $0 }
        return Network(ssid: ssid, password: password, security: security, hidden: fields["H"]?.lowercased() == "true")
    }
}
