import Foundation

/// `AEGIS_SELFTEST=1` ile açılışta çalışan güvenlik doğrulaması.
///
/// Silme kapısı uygulamanın en riskli parçası; bir gerileme sessizce
/// kullanıcı verisi kaybettirebilir. Bu yüzden beklenen kararlar burada
/// açıkça yazılıdır ve tek komutla doğrulanabilir.
enum SafetyGuardSelfTest {

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["AEGIS_SELFTEST"] == "1"
    }

    /// Başarısız durum sayısını döndürür (0 = hepsi geçti).
    @discardableResult
    static func run() -> Int {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // (yol, izin verilmeli mi, açıklama)
        let cases: [(String, Bool, String)] = [
            // --- reddedilmeli ---
            ("\(home)/Documents", false, "Belgeler klasörünün kendisi"),
            ("\(home)/Documents/tez.docx", false, "Belgeler içindeki kullanıcı dosyası"),
            ("\(home)/Desktop/proje", false, "Masaüstü içeriği"),
            ("\(home)/Pictures/Photos Library.photoslibrary", false, "Fotoğraf kitaplığı"),
            ("\(home)/Library/Mobile Documents/com~apple~CloudDocs/x", false, "iCloud Drive"),
            ("\(home)/Library/Keychains/login.keychain-db", false, "Anahtar zinciri"),
            ("\(home)/Library/Mail/V10", false, "Mail verisi"),
            ("\(home)/Library/Messages/chat.db", false, "Mesajlar veritabanı"),
            ("\(home)/Library/Safari/History.db", false, "Safari geçmişi"),
            ("/System/Library/CoreServices", false, "Sistem dizini"),
            ("/usr/bin/top", false, "Sistem ikilisi"),
            ("/", false, "Kök dizin"),
            (home, false, "Ev dizininin kendisi"),
            ("\(home)/Library", false, "Kitaplığın kendisi"),
            ("\(home)/Library/Caches", false, "Önbellek kökünün kendisi"),
            ("\(home)/Library/Caches/../../Documents/gizli", false, "Yol kaçışı ile Belgeler"),
            ("\(home)/Library/Application Support/Notlarim", false,
             "Application Support içinde serbest isimli klasör (kullanıcı verisi olabilir)"),
            ("\(home)/Library/Application Support/com.acme.app/Data/x", false,
             "Kalıntı bölgesinde üst düzey olmayan yol"),
            ("\(home)/Library/Preferences/GlobalPreferences.plist", false,
             "Ters-DNS olmayan tercih dosyası"),
            ("\(home)/Library/Containers/com.acme.app/Data/Documents/rapor.pdf", false,
             "Container içinde önbellek dışı veri"),
            ("\(home)/Library/Containers/com.acme.app/Data/Library/CachesEvil/veri", false,
             "Önbellek adıyla başlayan sahte klasör (segment sınırı)"),
            ("\(home)/Library/Containers/com.acme.app/Data/tmpEvil", false,
             "tmp adıyla başlayan sahte klasör (segment sınırı)"),
            ("\(home)/Library/Containers/Belgelerim", false,
             "Container kökünde serbest isimli klasör"),
            ("\(home)/Library/Containers/com.apple.mail", false,
             "Apple container'ı — kalıntı kuralı Apple kimliklerini kapsamaz"),

            // --- izin verilmeli ---
            ("\(home)/Library/Caches/com.acme.app", true, "Uygulama önbelleği"),
            ("\(home)/Library/Logs/Acme", true, "Uygulama günlüğü"),
            ("\(home)/Library/Developer/Xcode/DerivedData/App-abc", true, "Derleme çıktısı"),
            ("\(home)/Library/Containers/com.acme.app/Data/Library/Caches", true,
             "Sandbox uygulamasının önbelleği"),
            ("\(home)/Library/Containers/com.acme.app/Data/tmp", true,
             "Sandbox uygulamasının tmp klasörü"),
            ("\(home)/Library/Containers/com.dead.app", true,
             "Sahipsiz container'ın kendisi (Kalıntı Avcısı, ters-DNS doğrudan çocuk)"),
            ("\(home)/Library/Group Containers/group.com.dead.app", true,
             "Sahipsiz group container (ters-DNS doğrudan çocuk)"),
            ("\(home)/Library/Application Support/com.acme.app", true,
             "Ters-DNS isimli kalıntı klasörü"),
            ("\(home)/Library/Preferences/com.acme.app.plist", true, "Kalıntı tercih dosyası"),
            ("\(home)/Library/Saved Application State/com.acme.app.savedState", true,
             "Kalıntı pencere durumu"),
            ("\(home)/.Trash/eski-dosya.zip", true, "Çöp kutusundaki öğe"),
            ("\(home)/Downloads/kurulum.dmg", true, "Eski indirme"),
        ]

        var failures = 0
        print("── SafetyGuard öz denetimi ──")
        for (path, shouldAllow, description) in cases {
            let verdict = SafetyGuard.verify(URL(fileURLWithPath: path))
            let allowed = verdict.isAllowed
            let passed = allowed == shouldAllow
            if !passed { failures += 1 }

            let mark = passed ? "✓" : "✗ BAŞARISIZ"
            var reason = ""
            if case let .denied(text) = verdict { reason = " (\(text))" }
            print("\(mark)  \(shouldAllow ? "İZİN" : "RED ") · \(description)\(passed ? "" : " → gerçek: \(allowed ? "izin" : "red")\(reason)")")
        }

        print(failures == 0
              ? "── \(cases.count) durumun tamamı geçti ──"
              : "── \(failures) durum BAŞARISIZ ──")
        return failures
    }
}
