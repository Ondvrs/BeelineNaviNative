import SwiftUI
import CoreLocation
import CoreBluetooth
import MapKit

// MARK: - UUID musi presne sedet s ESP32 kodem (BeelinePrototyp_ESP32S3.ino)
let SERVICE_UUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
let CHARACTERISTIC_UUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")

// MARK: - Barvy jako hex
extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Paleta (tmava / svetla), akcentove barvy zustavaji stejne v obou rezimech
struct MotoPaleta {
    let asfalt: Color
    let panel: Color
    let panelHranice: Color
    let textHlavni: Color
    let textTlumeny: Color

    static let tmava = MotoPaleta(
        asfalt: Color(hex: "0D0F12"),
        panel: Color(hex: "1A1D21"),
        panelHranice: Color(hex: "2A2E33"),
        textHlavni: Color(hex: "F2F0EB"),
        textTlumeny: Color(hex: "8A8F98")
    )

    static let svetla = MotoPaleta(
        asfalt: Color(hex: "F2F0EB"),
        panel: Color(hex: "FFFFFF"),
        panelHranice: Color(hex: "D8D5CE"),
        textHlavni: Color(hex: "16181C"),
        textTlumeny: Color(hex: "6B7280")
    )
}

enum Moto {
    static let redline = Color(hex: "FF4713")
    static let jantar = Color(hex: "FFB800")
    static let signal = Color(hex: "00E676")

    static func eyebrow(_ text: String, _ paleta: MotoPaleta) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(1.8)
            .foregroundColor(paleta.textTlumeny)
    }

    // Barva podle navigacni zony: 0 normalni, 1 zelena, 2 oranzova, 3 cervena
    static func barvaZony(_ zona: Int, _ paleta: MotoPaleta) -> Color {
        switch zona {
        case 1: return signal
        case 2: return jantar
        case 3: return redline
        default: return paleta.textTlumeny
        }
    }
}

// MARK: - Nastaveni (uklada se do UserDefaults, zadny prekompilovani netreba)
enum BlikaniMod: Int, CaseIterable, Identifiable {
    case zadne = 0
    case sipka = 1
    case pozadi = 2

    var id: Int { rawValue }

    var nazev: String {
        switch self {
        case .zadne: return "Nic"
        case .sipka: return "Šipka"
        case .pozadi: return "Pozadí / kruh"
        }
    }
}

class NastaveniManager: ObservableObject {
    @Published var vzdalenostZelena: Double {
        didSet { UserDefaults.standard.set(vzdalenostZelena, forKey: "vzdalenostZelena") }
    }
    @Published var vzdalenostOranzova: Double {
        didSet { UserDefaults.standard.set(vzdalenostOranzova, forKey: "vzdalenostOranzova") }
    }
    @Published var vzdalenostCervena: Double {
        didSet { UserDefaults.standard.set(vzdalenostCervena, forKey: "vzdalenostCervena") }
    }
    @Published var blikaniMod: BlikaniMod {
        didSet { UserDefaults.standard.set(blikaniMod.rawValue, forKey: "blikaniMod") }
    }
    @Published var tmavyRezim: Bool {
        didSet { UserDefaults.standard.set(tmavyRezim, forKey: "tmavyRezim") }
    }

    var paleta: MotoPaleta { tmavyRezim ? .tmava : .svetla }

    init() {
        let d = UserDefaults.standard
        self.vzdalenostZelena = d.object(forKey: "vzdalenostZelena") as? Double ?? 100
        self.vzdalenostOranzova = d.object(forKey: "vzdalenostOranzova") as? Double ?? 50
        self.vzdalenostCervena = d.object(forKey: "vzdalenostCervena") as? Double ?? 15
        self.blikaniMod = BlikaniMod(rawValue: d.integer(forKey: "blikaniMod")) ?? .zadne
        self.tmavyRezim = d.object(forKey: "tmavyRezim") as? Bool ?? true
    }

    // Vypocita zonu (0-3) podle vzdalenosti v metrech
    func zonaProVzdalenost(_ metry: Double) -> Int {
        if metry <= vzdalenostCervena { return 3 }
        if metry <= vzdalenostOranzova { return 2 }
        if metry <= vzdalenostZelena { return 1 }
        return 0
    }
}

// MARK: - Opakovane pouzivane UI kousky
struct MotoPanel<Content: View>: View {
    let paleta: MotoPaleta
    let content: Content
    init(_ paleta: MotoPaleta, @ViewBuilder content: () -> Content) {
        self.paleta = paleta
        self.content = content()
    }
    var body: some View {
        content
            .padding(16)
            .background(paleta.panel)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(paleta.panelHranice, lineWidth: 1))
            .cornerRadius(14)
    }
}

struct MotoTlacitko: View {
    let titulek: String
    let barva: Color
    let paleta: MotoPaleta
    let action: () -> Void
    var vypnuto: Bool = false

    var body: some View {
        Button(action: action) {
            Text(titulek.uppercased())
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundColor(vypnuto ? paleta.textTlumeny : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(vypnuto ? paleta.panelHranice : barva)
                .cornerRadius(10)
        }
        .disabled(vypnuto)
    }
}

// MARK: - Kruhovy smerovy ukazatel (stejny princip jako displej na ESP32), s blikanim podle nastaveni
struct SmerovyUkazatel: View {
    var uhel: Int
    var zona: Int
    var blikaniMod: BlikaniMod
    var paleta: MotoPaleta

    @State private var blikViditelny = true

    var body: some View {
        let barvaAktivni = Moto.barvaZony(zona, paleta)
        let skrytKvuliBliku = (!blikViditelny) && (zona == 3) && (blikaniMod != .zadne)
        let barvaKruhu = (skrytKvuliBliku && blikaniMod == .pozadi) ? paleta.panelHranice : barvaAktivni
        let barvaSipky = (skrytKvuliBliku && blikaniMod == .sipka) ? paleta.textTlumeny : barvaAktivni

        ZStack {
            Circle()
                .stroke(barvaKruhu, lineWidth: 3)
                .frame(width: 200, height: 200)

            ForEach(0..<24) { i in
                Rectangle()
                    .fill(paleta.textTlumeny.opacity(0.5))
                    .frame(width: 2, height: i % 6 == 0 ? 10 : 5)
                    .offset(y: -92)
                    .rotationEffect(.degrees(Double(i) * 15))
            }

            SipkaTvar()
                .fill(barvaSipky)
                .frame(width: 70, height: 110)
                .rotationEffect(.degrees(Double(uhel)))
                .animation(.easeOut(duration: 0.35), value: uhel)
        }
        .frame(width: 200, height: 200)
        .onReceive(Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()) { _ in
            if zona == 3 && blikaniMod != .zadne {
                blikViditelny.toggle()
            } else {
                blikViditelny = true
            }
        }
    }
}

struct SipkaTvar: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let stred = rect.width / 2
        p.move(to: CGPoint(x: stred, y: 0))
        p.addLine(to: CGPoint(x: rect.width * 0.8, y: rect.height * 0.55))
        p.addLine(to: CGPoint(x: stred, y: rect.height * 0.4))
        p.addLine(to: CGPoint(x: rect.width * 0.2, y: rect.height * 0.55))
        p.closeSubpath()
        return p
    }
}

// MARK: - Tvar pro ikonu kruhoveho objezdu (stejny princip jako SipkaTvar)
// uhelVyjezdu: pozice vyjezdu na kruznici ve stupnich (matematicka konvence)
//   0°   = vpravo  (1. vyjezd)
//   90°  = nahore  (2. vyjezd / rovne)
//   180° = vlevo   (3. vyjezd)
//   270° = dole    (otocka - temer plny kruh zpet)
// Vjezd je vzdy pevne dole (270°), auto "prijizdi" zespodu nahoru do objezdu.
struct KruhovyObjezdTvar: Shape {
    var uhelVyjezdu: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let stred = CGPoint(x: rect.midX, y: rect.midY)
        let polomer = min(rect.width, rect.height) * 0.28

        let vjezdRad: Double = 270 * Double.pi / 180
        let vyjezdRad: Double = uhelVyjezdu * Double.pi / 180

        // Vjezdova usecka - od spodniho okraje ramecku do kruznice
        let vjezdBod = CGPoint(
            x: stred.x + polomer * CGFloat(cos(vjezdRad)),
            y: stred.y - polomer * CGFloat(sin(vjezdRad))
        )
        p.move(to: CGPoint(x: stred.x, y: rect.maxY))
        p.addLine(to: vjezdBod)

        // Oblouk uvnitr objezdu od vjezdu k vyjezdu (proti smeru hod. rucicek = kladny matematicky smer)
        p.addArc(
            center: stred,
            radius: polomer,
            startAngle: .radians(vjezdRad),
            endAngle: .radians(vyjezdRad),
            clockwise: false
        )

        return p
    }

    // Bod a smer (ve stupnich pro rotaci SipkaTvar) na konci vyjezdove usecky - pro pripojeni hrotu sipky
    func vyjezdovyBodASmer(v rect: CGRect) -> (bod: CGPoint, smer: Double) {
        let stred = CGPoint(x: rect.midX, y: rect.midY)
        let polomer = min(rect.width, rect.height) * 0.28
        let vyjezdRad: Double = uhelVyjezdu * Double.pi / 180
        let bod = CGPoint(
            x: stred.x + polomer * CGFloat(cos(vyjezdRad)),
            y: stred.y - polomer * CGFloat(sin(vyjezdRad))
        )
        // Prevod na "kompasovy" uhel pro rotationEffect (0° = nahoru, po smeru hod. rucicek)
        let kompas = (90 - uhelVyjezdu).truncatingRemainder(dividingBy: 360)
        return (bod, kompas)
    }
}

// MARK: - Slozena ikona objezdu (kruh + zvyraznena trasa + hrot sipky), stejny princip jako SmerovyUkazatel
struct ObjezdIkona: View {
    var uhelVyjezdu: Double
    var barvaAktivni: Color
    var barvaPozadi: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(barvaPozadi, lineWidth: 3)
                .frame(width: 44, height: 44)

            KruhovyObjezdTvar(uhelVyjezdu: uhelVyjezdu)
                .stroke(barvaAktivni, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 64, height: 64)

            SipkaTvar()
                .fill(barvaAktivni)
                .frame(width: 14, height: 20)
                .rotationEffect(.degrees(vyjezdSmer))
                .offset(vyjezdOffset)
        }
        .frame(width: 64, height: 64)
    }

    private var vyjezdSmer: Double {
        KruhovyObjezdTvar(uhelVyjezdu: uhelVyjezdu).vyjezdovyBodASmer(v: CGRect(x: 0, y: 0, width: 64, height: 64)).smer
    }

    private var vyjezdOffset: CGSize {
        let bod = KruhovyObjezdTvar(uhelVyjezdu: uhelVyjezdu).vyjezdovyBodASmer(v: CGRect(x: 0, y: 0, width: 64, height: 64)).bod
        return CGSize(width: bod.x - 32, height: bod.y - 32)
    }
}

// MARK: - Pomocna extension pro ziskani "manevrovaciho" bodu z MKRoute.Step
extension MKPolyline {
    var prvniBod: CLLocationCoordinate2D {
        guard pointCount > 0 else { return coordinate }
        return points()[0].coordinate
    }

    var vsechnyBody: [CLLocationCoordinate2D] {
        guard pointCount > 0 else { return [] }
        var body = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&body, range: NSRange(location: 0, length: pointCount))
        return body
    }
}

// MARK: - Hlavni logika (poloha + BLE), bezi i na pozadi
class NaviManager: NSObject, ObservableObject, CLLocationManagerDelegate, CBCentralManagerDelegate, CBPeripheralDelegate {

    private var locationManager = CLLocationManager()
    private var centralManager: CBCentralManager!
    private var esp32Peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?

    // Odkaz na nastaveni - injektuje ContentView pri vytvoreni
    var nastaveni: NastaveniManager?

    @Published var stavPripojeni: String = "Odpojeno"
    @Published var poslednaZprava: String = "---"
    @Published var aktivni: Bool = false
    @Published var aktualniPoloha: CLLocationCoordinate2D?

    @Published var aktualniUhel: Int = 0
    @Published var aktualniVzdalenost: String = "---"
    @Published var aktualniCas: String = "---"
    @Published var aktualniPokyn: String = "---"
    @Published var aktualniZona: Int = 0

    // MARK: Simulacni rezim (testovani bez GPS/ESP32)
    @Published var simulaceAktivni: Bool = false
    @Published var simulujOdchylku: Bool = false

    // MARK: Prepocitavani trasy po odbočení mimo ni
    @Published var prepocitavamTrasu: Bool = false
    var naOdchylkuOdTrasy: (() -> Void)?

    // Turn-by-turn kroky trasy
    private var kroky: [MKRoute.Step] = []
    private var aktualniKrokIndex: Int = 0

    // Vsechny body aktualni trasy (pro detekci odchylky) a pocitadlo mereni mimo trasu
    private var vsechnyBodyTrasy: [CLLocationCoordinate2D] = []
    private var odchylkaPocet: Int = 0
    private let odchylkaLimit: Double = 50       // metru od trasy = povazujeme za "sjeto z trasy"
    private let odchylkaPocetTreba: Int = 3      // po sobe jdouci mereni nad limitem, nez spustime prepocet

    // Filtr GPS sumu - klouzavy kruhovy prumer poslednich azimutu
    private var azimutHistorie: [Double] = []
    private let azimutHistorieMax = 5

    // Simulace
    private var simulaceTimer: Timer?
    private var simulaceBody: [CLLocationCoordinate2D] = []
    private var simulaceIndex: Int = 0

    var cilLat: Double = 0
    var cilLon: Double = 0
    var cilNastaven: Bool = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true

        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func pozadejOOpravneni() {
        locationManager.requestAlwaysAuthorization()
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    // Nastaveni cile bez trasy (fallback - primy smer k cili)
    func nastavCil(lat: Double, lon: Double) {
        cilLat = lat
        cilLon = lon
        cilNastaven = true
        kroky = []
        aktualniKrokIndex = 0
        vsechnyBodyTrasy = []
        odchylkaPocet = 0
        azimutHistorie = []
    }

    // Nastaveni turn-by-turn trasy s kroky z MKDirections
    func nastavTrasu(kroky noveKroky: [MKRoute.Step], cilLat: Double, cilLon: Double) {
        self.kroky = noveKroky.filter { $0.polyline.pointCount > 0 }
        self.aktualniKrokIndex = 0
        self.cilLat = cilLat
        self.cilLon = cilLon
        self.cilNastaven = true
        self.vsechnyBodyTrasy = self.kroky.flatMap { $0.polyline.vsechnyBody }
        self.odchylkaPocet = 0
        self.azimutHistorie = []
    }
private let poslednizesp32Klic = "posledniESP32Identifier"

    func pripojitESP32() {
        stavPripojeni = "Hledam ESP32..."
        zkusChytreConnect()
    }

    private func zkusChytreConnect() {
        if let ulozeneID = UserDefaults.standard.string(forKey: poslednizesp32Klic),
           let uuid = UUID(uuidString: ulozeneID) {
            let znama = centralManager.retrievePeripherals(withIdentifiers: [uuid])
            if let zarizeni = znama.first {
                esp32Peripheral = zarizeni
                esp32Peripheral?.delegate = self
                centralManager.connect(zarizeni, options: nil)
                stavPripojeni = "Pripojuji se (znama zarizeni)..."
                return
            }
        }
        centralManager.scanForPeripherals(withServices: [SERVICE_UUID], options: nil)
    }

    func spustitNavigaci() {
        aktivni = true
        locationManager.startUpdatingLocation()
    }

    func zastavitNavigaci() {
        aktivni = false
        locationManager.stopUpdatingLocation()
        if simulaceAktivni {
            zastavitSimulaci()
        }
    }

// MARK: - Testovaci simulace pohybu (bez GPS, ideal pro ladeni na stole)
    func spustitSimulaci(pocatecniPoloha: CLLocationCoordinate2D?) {
        guard cilNastaven else { return }
        simulaceAktivni = true
        aktivni = true

        if !vsechnyBodyTrasy.isEmpty {
            simulaceBody = simulujOdchylku ? vyboulenaTrasa(vsechnyBodyTrasy) : vsechnyBodyTrasy
        } else {
            let start = pocatecniPoloha ?? CLLocationCoordinate2D(
                latitude: cilLat - 0.01, longitude: cilLon - 0.01
            )
            let primaTrasa = interpolujBody(
                od: start,
                do: CLLocationCoordinate2D(latitude: cilLat, longitude: cilLon),
                pocetKroku: 60
            )
            simulaceBody = simulujOdchylku ? vyboulenaTrasa(primaTrasa) : primaTrasa
        }
        simulaceIndex = 0

        simulaceTimer?.invalidate()
        simulaceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.krokSimulace()
        }
    }

    func zastavitSimulaci() {
        simulaceAktivni = false
        aktivni = false
        simulaceTimer?.invalidate()
        simulaceTimer = nil
    }

    private func krokSimulace() {
        guard simulaceIndex < simulaceBody.count else {
            zastavitSimulaci()
            return
        }
        let bod = simulaceBody[simulaceIndex]
        simulaceIndex += 1

        let sumLat = Double.random(in: -0.00003...0.00003)
        let sumLon = Double.random(in: -0.00003...0.00003)
        let simPoloha = CLLocation(latitude: bod.latitude + sumLat, longitude: bod.longitude + sumLon)

        DispatchQueue.main.async {
            self.aktualniPoloha = simPoloha.coordinate
        }
        vyhodnotPozici(poloha: simPoloha)
    }

    private func interpolujBody(od start: CLLocationCoordinate2D, do cil: CLLocationCoordinate2D, pocetKroku: Int) -> [CLLocationCoordinate2D] {
        guard pocetKroku > 0 else { return [start, cil] }
        var vysledek: [CLLocationCoordinate2D] = []
        for i in 0...pocetKroku {
            let t = Double(i) / Double(pocetKroku)
            let lat = start.latitude + (cil.latitude - start.latitude) * t
            let lon = start.longitude + (cil.longitude - start.longitude) * t
            vysledek.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        return vysledek
    }

    // Vyboulí prostredni tretinu trasy kolmo do strany, aby spolehlive prekrocila odchylkaLimit
    private func vyboulenaTrasa(_ body: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard body.count > 5 else { return body }
        let start = body.count / 3
        let konec = (body.count * 2) / 3
        guard konec > start else { return body }

        var vysledek = body
        let maxVychylkaMetru = 90.0

        for i in start...konec {
            let t = Double(i - start) / Double(konec - start)
            let sila = sin(t * .pi) * maxVychylkaMetru

            let predchozi = body[max(0, i - 1)]
            let dalsi = body[min(body.count - 1, i + 1)]
            let dx = dalsi.longitude - predchozi.longitude
            let dy = dalsi.latitude - predchozi.latitude
            let delka = sqrt(dx * dx + dy * dy)
            guard delka > 0 else { continue }

            let kolmX = -dy / delka
            let kolmY = dx / delka

            let refLat = body[i].latitude * .pi / 180
            let metryNaStupenLat = 111_320.0
            let metryNaStupenLon = 111_320.0 * cos(refLat)

            let posunLat = (kolmY * sila) / metryNaStupenLat
            let posunLon = (kolmX * sila) / metryNaStupenLon

            vysledek[i] = CLLocationCoordinate2D(
                latitude: body[i].latitude + posunLat,
                longitude: body[i].longitude + posunLon
            )
        }
        return vysledek
        }

    // --- CBCentralManagerDelegate ---
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            print("Bluetooth je zapnuty.")
            zkusChytreConnect()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        centralManager.stopScan()
        esp32Peripheral = peripheral
        esp32Peripheral?.delegate = self
        centralManager.connect(peripheral, options: nil)
        stavPripojeni = "Pripojuji se..."
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        stavPripojeni = "Pripojeno, hledam sluzbu..."
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: poslednizesp32Klic)
        peripheral.discoverServices([SERVICE_UUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        stavPripojeni = "Odpojeno"
        writeCharacteristic = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.zkusChytreConnect()
        }
    }

    // --- CBPeripheralDelegate ---
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == SERVICE_UUID {
            peripheral.discoverCharacteristics([CHARACTERISTIC_UUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars where char.uuid == CHARACTERISTIC_UUID {
            writeCharacteristic = char
            stavPripojeni = "SPOJENO"
        }
    }

    // --- CLLocationManagerDelegate ---
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let poloha = locations.last else { return }

        // Pri simulaci ignorujeme realnou GPS polohu, at si navzajem "neskacou"
        guard !simulaceAktivni else { return }

        // Filtr GPS sumu - zahodime fixy s nepresnym nebo zapornym (neplatnym) horizontalAccuracy
        guard poloha.horizontalAccuracy >= 0, poloha.horizontalAccuracy < 65 else { return }

        DispatchQueue.main.async {
            self.aktualniPoloha = poloha.coordinate
        }
        if cilNastaven {
            vyhodnotPozici(poloha: poloha)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Chyba GPS: \(error.localizedDescription)")
    }

    // --- Filtr GPS sumu: klouzavy kruhovy prumer azimutu (zabranuje "klepani" sipky) ---
    private func vyhlazenyAzimut(_ novyAzimut: Double) -> Double {
        azimutHistorie.append(novyAzimut)
        if azimutHistorie.count > azimutHistorieMax {
            azimutHistorie.removeFirst()
        }
        var sumSin = 0.0
        var sumCos = 0.0
        for uhel in azimutHistorie {
            let rad = uhel * .pi / 180
            sumSin += sin(rad)
            sumCos += cos(rad)
        }
        var prumer = atan2(sumSin, sumCos) * 180 / .pi
        if prumer < 0 { prumer += 360 }
        return prumer
    }

    // --- Detekce odchylky od planovane trasy (vzdalenost bodu od nejblizsi usecky trasy) ---
    private func vzdalenostOdTrasy(bod: CLLocationCoordinate2D) -> Double {
        guard vsechnyBodyTrasy.count > 1 else { return 0 }
        var minVzdalenost = Double.greatestFiniteMagnitude
        for i in 0..<(vsechnyBodyTrasy.count - 1) {
            let d = vzdalenostOdUsecky(bod: bod, a: vsechnyBodyTrasy[i], b: vsechnyBodyTrasy[i + 1])
            if d < minVzdalenost { minVzdalenost = d }
        }
        return minVzdalenost
    }

    private func vzdalenostOdUsecky(bod p: CLLocationCoordinate2D, a: CLLocationCoordinate2D, b: CLLocationCoordinate2D) -> Double {
        // Jednoducha rovinna aproximace v metrech - dostatecne presna na kratke useky trasy
        let refLat = a.latitude * .pi / 180
        let metryNaStupenLat = 111_320.0
        let metryNaStupenLon = 111_320.0 * cos(refLat)

        let bx = (b.longitude - a.longitude) * metryNaStupenLon
        let by = (b.latitude - a.latitude) * metryNaStupenLat
        let px = (p.longitude - a.longitude) * metryNaStupenLon
        let py = (p.latitude - a.latitude) * metryNaStupenLat

        let delkaCtverec = bx * bx + by * by
        var t = delkaCtverec > 0 ? (px * bx + py * by) / delkaCtverec : 0
        t = max(0, min(1, t))

        let projX = t * bx
        let projY = t * by
        let dx = px - projX
        let dy = py - projY
        return sqrt(dx * dx + dy * dy)
    }

    // --- Vypocet, postup po krocich trasy a odeslani ---
    private func vyhodnotPozici(poloha: CLLocation) {
        let myLat = poloha.coordinate.latitude
        let myLon = poloha.coordinate.longitude

        let cilovyBod: CLLocationCoordinate2D
        var textPokynu: String
        var jePosledniKrok = true

        if !kroky.isEmpty, aktualniKrokIndex < kroky.count {
            let krok = kroky[aktualniKrokIndex]
            cilovyBod = krok.polyline.prvniBod
            textPokynu = krok.instructions.isEmpty ? "Pokracujte rovne" : krok.instructions
            jePosledniKrok = (aktualniKrokIndex >= kroky.count - 1)
        } else {
            cilovyBod = CLLocationCoordinate2D(latitude: cilLat, longitude: cilLon)
            textPokynu = "Jed k cíli"
        }

        let vzdalenost = spoctiVzdalenost(lat1: myLat, lon1: myLon, lat2: cilovyBod.latitude, lon2: cilovyBod.longitude)
        let surovyAzimut = spoctiAzimut(lat1: myLat, lon1: myLon, lat2: cilovyBod.latitude, lon2: cilovyBod.longitude)
        let azimut = vyhlazenyAzimut(surovyAzimut)

        // Postup na dalsi krok trasy, kdyz jsme dost blizko a jeste neni posledni krok
        if !kroky.isEmpty, !jePosledniKrok, vzdalenost < 20 {
            aktualniKrokIndex += 1
        }

        // Kontrola odchylky od planovane trasy -> po par mereni mimo trasu spustime prepocet
        if !vsechnyBodyTrasy.isEmpty {
            let odchylka = vzdalenostOdTrasy(bod: poloha.coordinate)
            if odchylka > odchylkaLimit {
                odchylkaPocet += 1
                if odchylkaPocet >= odchylkaPocetTreba {
                    odchylkaPocet = 0
                    vsechnyBodyTrasy = []   // zabrani opakovanemu spusteni, dokud neprijde nova trasa
                    DispatchQueue.main.async {
                        self.prepocitavamTrasu = true
                    }
                    naOdchylkuOdTrasy?()
                }
            } else {
                odchylkaPocet = 0
            }
        }

        let prahy = nastaveni ?? NastaveniManager()
        let zona = prahy.zonaProVzdalenost(vzdalenost)

        let vzdText = vzdalenost > 1000 ? String(format: "%.1f km", vzdalenost / 1000) : "\(Int(vzdalenost)) m"
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let hodiny = formatter.string(from: Date())

        // Carky v pokynu by rozbily CSV parsovani na ESP32, nahradime strednikem
        let bezpecnyPokyn = textPokynu.replacingOccurrences(of: ",", with: ";")

        let zprava = "\(Int(azimut)),---,\(zona),\(hodiny),\(vzdText),\(bezpecnyPokyn),\(prahy.blikaniMod.rawValue)"

        DispatchQueue.main.async {
            self.poslednaZprava = zprava
            self.aktualniUhel = Int(azimut)
            self.aktualniVzdalenost = vzdText
            self.aktualniCas = hodiny
            self.aktualniPokyn = textPokynu
            self.aktualniZona = zona
        }
        posliDoBLE(zprava)
    }

    private func posliDoBLE(_ text: String) {
        guard let peripheral = esp32Peripheral, let char = writeCharacteristic else { return }
        guard let data = text.data(using: .utf8) else { return }
        peripheral.writeValue(data, for: char, type: .withoutResponse)
    }

    private func spoctiVzdalenost(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371000.0
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let dPhi = (lat2 - lat1) * .pi / 180
        let dLambda = (lon2 - lon1) * .pi / 180
        let a = sin(dPhi/2) * sin(dPhi/2) + cos(phi1) * cos(phi2) * sin(dLambda/2) * sin(dLambda/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        return R * c
    }

    private func spoctiAzimut(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let dLambda = (lon2 - lon1) * .pi / 180
        let y = sin(dLambda) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLambda)
        var brng = atan2(y, x) * 180 / .pi
        brng = (brng + 360).truncatingRemainder(dividingBy: 360)
        return brng
    }

}

// MARK: - Vyhledavani adres (MapKit nasepta jako Google Maps)
class AdresyHledac: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    @Published var navrhy: [MKLocalSearchCompletion] = []

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func hledej(_ text: String) {
        if text.isEmpty {
            navrhy = []
            return
        }
        completer.queryFragment = text
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.navrhy = completer.results
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Chyba naseptavace: \(error.localizedDescription)")
    }

    func vyhledejSouradnice(pro navrh: MKLocalSearchCompletion, dokonceni: @escaping (CLLocationCoordinate2D?, String) -> Void) {
        let request = MKLocalSearch.Request(completion: navrh)
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            guard let item = response?.mapItems.first else {
                dokonceni(nil, navrh.title)
                return
            }
            dokonceni(item.placemark.coordinate, navrh.title)
        }
    }
}

// Vraci celou trasu (MKRoute), abychom meli k dispozici jak polyline pro mapu, tak kroky pro turn-by-turn
func spocitejTrasu(z start: CLLocationCoordinate2D, do cil: CLLocationCoordinate2D, dokonceni: @escaping (MKRoute?) -> Void) {
    let request = MKDirections.Request()
    request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: cil))
    request.transportType = .automobile
    request.requestsAlternateRoutes = false

    let directions = MKDirections(request: request)
    directions.calculate { response, error in
        DispatchQueue.main.async {
            dokonceni(response?.routes.first)
        }
    }
}

// MARK: - Mapa, s bezelem jako palubni displej
struct MapaView: UIViewRepresentable {
    var cil: CLLocationCoordinate2D?
    var trasa: [CLLocationCoordinate2D]
    var tmavyRezim: Bool

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = true
        mapView.delegate = context.coordinator
        mapView.userTrackingMode = .follow
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.overrideUserInterfaceStyle = tmavyRezim ? .dark : .light

        let stareAnotace = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(stareAnotace)
        mapView.removeOverlays(mapView.overlays)

        if let cil = cil {
            let pin = MKPointAnnotation()
            pin.coordinate = cil
            pin.title = "Cíl"
            mapView.addAnnotation(pin)
        }

        if trasa.count > 1 {
            let polyline = MKPolyline(coordinates: trasa, count: trasa.count)
            mapView.addOverlay(polyline)
            mapView.setVisibleMapRect(
                polyline.boundingMapRect,
                edgePadding: UIEdgeInsets(top: 50, left: 40, bottom: 50, right: 40),
                animated: true
            )
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(Moto.redline)
                renderer.lineWidth = 5
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Nastaveni obrazovka
struct NastaveniView: View {
    @ObservedObject var nastaveni: NastaveniManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let paleta = nastaveni.paleta
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Zelená zóna (daleko od odbočky)")
                        Slider(value: $nastaveni.vzdalenostZelena, in: 30...400, step: 5)
                        Text("\(Int(nastaveni.vzdalenostZelena)) m")
                            .foregroundColor(paleta.textTlumeny)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Oranžová zóna")
                        Slider(value: $nastaveni.vzdalenostOranzova, in: 10...200, step: 5)
                        Text("\(Int(nastaveni.vzdalenostOranzova)) m")
                            .foregroundColor(paleta.textTlumeny)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Červená zóna (těsně před odbočkou)")
                        Slider(value: $nastaveni.vzdalenostCervena, in: 3...60, step: 1)
                        Text("\(Int(nastaveni.vzdalenostCervena)) m")
                            .foregroundColor(paleta.textTlumeny)
                    }
                } header: {
                    Text("Prahy vzdálenosti pro barvy")
                }

                Section {
                    Picker("Co bliká v červené zóně", selection: $nastaveni.blikaniMod) {
                        ForEach(BlikaniMod.allCases) { mod in
                            Text(mod.nazev).tag(mod)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Blikání na displeji ESP32")
                }

                Section {
                    Toggle("Tmavý režim", isOn: $nastaveni.tmavyRezim)
                } header: {
                    Text("Vzhled appky")
                }
            }
            .navigationTitle("Nastavení")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { dismiss() }
                }
            }
        }
    }
}

// MARK: - UI
struct ContentView: View {
    @StateObject private var navi = NaviManager()
    @StateObject private var hledac = AdresyHledac()
    @StateObject private var nastaveni = NastaveniManager()

    @State private var hledaniText: String = ""
    @State private var cilSouradnice: CLLocationCoordinate2D?
    @State private var cilNazev: String = ""
    @State private var trasaBody: [CLLocationCoordinate2D] = []
    @State private var zobrazNavrhy = false
    @State private var zobrazNastaveni = false

    var body: some View {
        let paleta = nastaveni.paleta

        ZStack {
            paleta.asfalt.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("BEELINE")
                                .font(.system(size: 26, weight: .black, design: .rounded))
                                .foregroundColor(paleta.textHlavni)
                            Moto.eyebrow("Moto navigace", paleta)
                        }
                        Spacer()
                        if navi.simulaceAktivni {
                            Text("SIMULACE")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .tracking(0.5)
                                .foregroundColor(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Moto.jantar)
                                .cornerRadius(20)
                        }
                        StavIndikator(stav: navi.stavPripojeni, paleta: paleta)
                        Button {
                            zobrazNastaveni = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18))
                                .foregroundColor(paleta.textTlumeny)
                                .padding(8)
                                .background(paleta.panel)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.top, 8)

                    MotoPanel(paleta) {
                        VStack(spacing: 10) {
                            SmerovyUkazatel(
                                uhel: navi.aktualniUhel,
                                zona: navi.aktualniZona,
                                blikaniMod: nastaveni.blikaniMod,
                                paleta: paleta
                            )

                            HStack {
                                VStack(spacing: 2) {
                                    Moto.eyebrow("Vzdálenost", paleta)
                                    Text(navi.aktualniVzdalenost)
                                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                                        .foregroundColor(paleta.textHlavni)
                                }
                                Spacer()
                                VStack(spacing: 2) {
                                    Moto.eyebrow("Čas", paleta)
                                    Text(navi.aktualniCas)
                                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                                        .foregroundColor(paleta.textHlavni)
                                }
                                Spacer()
                                VStack(spacing: 2) {
                                    Moto.eyebrow("Pokyn", paleta)
                                    Text(navi.aktualniPokyn)
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(Moto.barvaZony(navi.aktualniZona, paleta))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .padding(.horizontal, 8)

                            if navi.prepocitavamTrasu {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Přepočítávám trasu…")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(paleta.textTlumeny)
                                }
                            }
                        }
                    }

                    MotoPanel(paleta) {
                        VStack(alignment: .leading, spacing: 8) {
                            Moto.eyebrow("2 · Vyhledat cíl", paleta)

                            TextField("Zadej město, ulici...", text: $hledaniText)
                                .font(.system(size: 16, design: .rounded))
                                .foregroundColor(paleta.textHlavni)
                                .padding(10)
                                .background(paleta.asfalt)
                                .cornerRadius(8)
                                .onChange(of: hledaniText) { novyText in
                                    hledac.hledej(novyText)
                                    zobrazNavrhy = !novyText.isEmpty
                                }

                            if zobrazNavrhy && !hledac.navrhy.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(hledac.navrhy.prefix(5), id: \.self) { navrh in
                                        Button { vyberNavrh(navrh) } label: {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(navrh.title)
                                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                    .foregroundColor(paleta.textHlavni)
                                                if !navrh.subtitle.isEmpty {
                                                    Text(navrh.subtitle)
                                                        .font(.system(size: 12, design: .rounded))
                                                        .foregroundColor(paleta.textTlumeny)
                                                }
                                            }
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        if navrh != hledac.navrhy.prefix(5).last {
                                            Divider().background(paleta.panelHranice)
                                        }
                                    }
                                }
                                .padding(.horizontal, 4)
                            }

                            if !cilNazev.isEmpty {
                                HStack(spacing: 6) {
                                    Circle().fill(Moto.signal).frame(width: 8, height: 8)
                                    Text("Cíl: \(cilNazev)")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(paleta.textTlumeny)
                                }
                            }
                        }
                    }

                    MotoPanel(paleta) {
                        VStack(alignment: .leading, spacing: 8) {
                            Moto.eyebrow("Mapa", paleta)
                            MapaView(cil: cilSouradnice, trasa: trasaBody, tmavyRezim: nastaveni.tmavyRezim)
                                .frame(height: 260)
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(paleta.panelHranice, lineWidth: 1))
                        }
                    }

                    VStack(spacing: 10) {
                        MotoTlacitko(titulek: "Povolit polohu", barva: paleta.textTlumeny, paleta: paleta) {
                            navi.pozadejOOpravneni()
                        }
                        MotoTlacitko(titulek: "1 · Připojit ESP32", barva: Moto.jantar, paleta: paleta) {
                            navi.pripojitESP32()
                        }
                        MotoTlacitko(
                            titulek: navi.aktivni ? "Zastavit navigaci" : "3 · Spustit navigaci",
                            barva: navi.aktivni ? Moto.redline : Moto.signal,
                            paleta: paleta,
                            action: {
                                if navi.aktivni {
                                    navi.zastavitNavigaci()
                                } else if cilSouradnice != nil {
                                    navi.spustitNavigaci()
                                }
                            },
                            vypnuto: cilSouradnice == nil && !navi.aktivni
                        )
                        MotoTlacitko(
                            titulek: navi.simulaceAktivni ? "Zastavit simulaci" : "Testovací simulace",
                            barva: navi.simulaceAktivni ? Moto.redline : paleta.textTlumeny,
                            paleta: paleta,
                            action: {
                                if navi.simulaceAktivni {
                                    navi.zastavitSimulaci()
                                } else if cilSouradnice != nil {
                                    navi.spustitSimulaci(pocatecniPoloha: navi.aktualniPoloha)
                                }
                            },
                            vypnuto: cilSouradnice == nil && !navi.simulaceAktivni
                        )
                        Toggle(isOn: Binding(
                            get: { navi.simulujOdchylku },
                            set: { navi.simulujOdchylku = $0 }
                        )) {
                            Text("Simulovat sjetí z trasy")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(paleta.textHlavni)
                        }
                        .tint(Moto.jantar)
                        .padding(.horizontal, 4)
                    }

                    MotoPanel(paleta) {
                        VStack(alignment: .leading, spacing: 6) {
                            Moto.eyebrow("Odesláno přes BLE", paleta)
                            Text(navi.poslednaZprava)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(paleta.textTlumeny)
                        }
                    }
                }
                .padding(16)
            }
        }
        .preferredColorScheme(nastaveni.tmavyRezim ? .dark : .light)
        .onAppear {
            navi.nastaveni = nastaveni
            navi.pozadejOOpravneni()

            // Callback z NaviManageru - kdyz zjisti odchylku od trasy, prepocitame ji tady
            // (potrebujeme UI vrstvu kvuli spocitejTrasu a aktualizaci trasaBody pro mapu)
            navi.naOdchylkuOdTrasy = {
                guard let start = navi.aktualniPoloha else {
                    DispatchQueue.main.async { navi.prepocitavamTrasu = false }
                    return
                }
                let cil = CLLocationCoordinate2D(latitude: navi.cilLat, longitude: navi.cilLon)
                spocitejTrasu(z: start, do: cil) { route in
                    navi.prepocitavamTrasu = false
                    guard let route = route else { return }

                    let pocetBodu = route.polyline.pointCount
                    var body = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pocetBodu)
                    route.polyline.getCoordinates(&body, range: NSRange(location: 0, length: pocetBodu))
                    trasaBody = body

                    navi.nastavTrasu(kroky: route.steps, cilLat: cil.latitude, cilLon: cil.longitude)
                }
            }
        }
        .sheet(isPresented: $zobrazNastaveni) {
            NastaveniView(nastaveni: nastaveni)
        }
    }

    private func vyberNavrh(_ navrh: MKLocalSearchCompletion) {
        hledac.vyhledejSouradnice(pro: navrh) { souradnice, nazev in
            guard let souradnice = souradnice else { return }
            hledaniText = nazev
            cilNazev = nazev
            zobrazNavrhy = false
            cilSouradnice = souradnice

            // Fallback - primy smer k cili, kdyby se trasa nepodarila spocitat
            navi.nastavCil(lat: souradnice.latitude, lon: souradnice.longitude)

            guard let start = navi.aktualniPoloha else { return }
            spocitejTrasu(z: start, do: souradnice) { route in
                guard let route = route else { return }

                let pocetBodu = route.polyline.pointCount
                var body = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pocetBodu)
                route.polyline.getCoordinates(&body, range: NSRange(location: 0, length: pocetBodu))
                trasaBody = body

                navi.nastavTrasu(kroky: route.steps, cilLat: souradnice.latitude, cilLon: souradnice.longitude)
            }
        }
    }
}

struct StavIndikator: View {
    let stav: String
    let paleta: MotoPaleta

    var barva: Color {
        switch stav {
        case "SPOJENO": return Moto.signal
        case "Odpojeno": return paleta.textTlumeny
        default: return Moto.jantar
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(barva).frame(width: 9, height: 9)
            Text(stav.uppercased())
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(0.5)
                .foregroundColor(barva)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(paleta.panel)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(paleta.panelHranice, lineWidth: 1))
        .cornerRadius(20)
    }
}

@main
struct BeelineNaviApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
