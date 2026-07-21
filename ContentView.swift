import SwiftUI
import CoreLocation
import CoreBluetooth
import MapKit

// MARK: - UUID musí přesně sedět s ESP32 kódem
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

// MARK: - Paleta (tmavá / světlá)
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

    static func barvaZony(_ zona: Int, _ paleta: MotoPaleta) -> Color {
        switch zona {
        case 1: return signal
        case 2: return jantar
        case 3: return redline
        default: return paleta.textTlumeny
        }
    }
}

// MARK: - Nastavení
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
    @Published var odesilaciInterval: Double {
        didSet { UserDefaults.standard.set(odesilaciInterval, forKey: "odesilaciInterval") }
    }
    @Published var debugSimulace: Bool {
        didSet { UserDefaults.standard.set(debugSimulace, forKey: "debugSimulace") }
    }
    @Published var debugRychlostKmh: Double {
        didSet { UserDefaults.standard.set(debugRychlostKmh, forKey: "debugRychlostKmh") }
    }

    var paleta: MotoPaleta { tmavyRezim ? .tmava : .svetla }

    init() {
        let d = UserDefaults.standard
        self.vzdalenostZelena = d.object(forKey: "vzdalenostZelena") as? Double ?? 100
        self.vzdalenostOranzova = d.object(forKey: "vzdalenostOranzova") as? Double ?? 50
        self.vzdalenostCervena = d.object(forKey: "vzdalenostCervena") as? Double ?? 15
        self.blikaniMod = BlikaniMod(rawValue: d.integer(forKey: "blikaniMod")) ?? .zadne
        self.tmavyRezim = d.object(forKey: "tmavyRezim") as? Bool ?? true
        self.odesilaciInterval = d.object(forKey: "odesilaciInterval") as? Double ?? 0.2
        self.debugSimulace = d.object(forKey: "debugSimulace") as? Bool ?? false
        self.debugRychlostKmh = d.object(forKey: "debugRychlostKmh") as? Double ?? 40
    }

    func zonaProVzdalenost(_ metry: Double) -> Int {
        if metry <= vzdalenostCervena { return 3 }
        if metry <= vzdalenostOranzova { return 2 }
        if metry <= vzdalenostZelena { return 1 }
        return 0
    }
}

// MARK: - Opakovaně používané UI prvky
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
    var vypnuto: Bool = false
    let action: () -> Void // 'action' posunut na konec pro správnou funkci trailing closure

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

// MARK: - Směrový ukazatel
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

// MARK: - Extension pro zisk prvniho bodu z MKPolyline
extension MKPolyline {
    var prvniBod: CLLocationCoordinate2D {
        guard pointCount > 0 else { return coordinate }
        return points()[0].coordinate
    }
}

// MARK: - Hlavni logika (poloha + BLE)
class NaviManager: NSObject, ObservableObject, CLLocationManagerDelegate, CBCentralManagerDelegate, CBPeripheralDelegate {

    private var locationManager = CLLocationManager()
    private var centralManager: CBCentralManager!
    private var esp32Peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?

    var nastaveni: NastaveniManager? {
        didSet {
            spustOdesilaciTimer()
        }
    }

    @Published var stavPripojeni: String = "Odpojeno"
    @Published var poslednaZprava: String = "---"
    @Published var aktivni: Bool = false
    @Published var aktualniPoloha: CLLocationCoordinate2D?

    @Published var aktualniUhel: Int = 0
    @Published var aktualniVzdalenost: String = "---"
    @Published var aktualniCas: String = "---"
    @Published var aktualniPokyn: String = "---"
    @Published var aktualniZona: Int = 0

    private var kroky: [MKRoute.Step] = []
    private var aktualniKrokIndex: Int = 0
    private var posledniKompasHeading: Double?

    private var debugTimer: Timer?
    private var debugPoloha: CLLocationCoordinate2D?

    private var sendTimer: Timer?
    private var posledniInterval: Double = -1.0

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

        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
    }

    func nastavCil(lat: Double, lon: Double) {
        cilLat = lat
        cilLon = lon
        cilNastaven = true
        kroky = []
        aktualniKrokIndex = 0
    }

    func nastavTrasu(kroky noveKroky: [MKRoute.Step], cilLat: Double, cilLon: Double) {
        self.kroky = noveKroky.filter { $0.polyline.pointCount > 0 }
        self.aktualniKrokIndex = 0
        self.cilLat = cilLat
        self.cilLon = cilLon
        self.cilNastaven = true
    }

    func pripojitESP32() {
        stavPripojeni = "Hledam ESP32..."
        centralManager.scanForPeripherals(withServices: [SERVICE_UUID], options: nil)
    }

    func spustitNavigaci() {
        aktivni = true
        spustOdesilaciTimer()
        if nastaveni?.debugSimulace == true {
            locationManager.stopUpdatingLocation()
            spustitDebugSimulaci()
        } else {
            locationManager.startUpdatingLocation()
        }
    }

    func zastavitNavigaci() {
        aktivni = false
        zastavOdesilaciTimer()
        locationManager.stopUpdatingLocation()
        zastavitDebugSimulaci()
    }

    func spustOdesilaciTimer() {
        guard let nastaveni = nastaveni else { return }
        
        if sendTimer != nil && posledniInterval == nastaveni.odesilaciInterval {
            return
        }

        zastavOdesilaciTimer()
        posledniInterval = nastaveni.odesilaciInterval

        sendTimer = Timer.scheduledTimer(withTimeInterval: nastaveni.odesilaciInterval, repeats: true) { [weak self] _ in
            self?.odesliAktualniStavDoBLE()
        }
    }

    func zastavOdesilaciTimer() {
        sendTimer?.invalidate()
        sendTimer = nil
    }

    private func odesliAktualniStavDoBLE() {
        guard aktivni, cilNastaven else { return }
        let zprava = poslednaZprava
        guard zprava != "---" && !zprava.isEmpty else { return }
        posliDoBLE(zprava)
    }

    // --- CBCentralManagerDelegate ---
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            print("Bluetooth je zapnuty.")
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
        peripheral.discoverServices([SERVICE_UUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        stavPripojeni = "Odpojeno"
        writeCharacteristic = nil
        centralManager.scanForPeripherals(withServices: [SERVICE_UUID], options: nil)
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
        guard nastaveni?.debugSimulace != true else { return }
        guard let poloha = locations.last else { return }
        
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

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if newHeading.headingAccuracy >= 0 {
            self.posledniKompasHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        }
    }

    private func ziskejAktualniCilovyBod() -> (bod: CLLocationCoordinate2D, pokyn: String, posledni: Bool) {
        if !kroky.isEmpty, aktualniKrokIndex < kroky.count {
            let krok = kroky[aktualniKrokIndex]
            let bod = krok.polyline.prvniBod
            let pokyn = krok.instructions.isEmpty ? "Pokracujte rovne" : krok.instructions
            let posledni = (aktualniKrokIndex >= kroky.count - 1)
            return (bod, pokyn, posledni)
        } else {
            return (CLLocationCoordinate2D(latitude: cilLat, longitude: cilLon), "Jed k cíli", true)
        }
    }

    private func vyhodnotPozici(poloha: CLLocation) {
        if let currentInterval = nastaveni?.odesilaciInterval, currentInterval != posledniInterval {
            spustOdesilaciTimer()
        }

        let myLat = poloha.coordinate.latitude
        let myLon = poloha.coordinate.longitude

        let (cilovyBod, textPokynu, jePosledniKrok) = ziskejAktualniCilovyBod()

        let vzdalenost = spoctiVzdalenost(lat1: myLat, lon1: myLon, lat2: cilovyBod.latitude, lon2: cilovyBod.longitude)
        let azimutKCili = spoctiAzimut(lat1: myLat, lon1: myLon, lat2: cilovyBod.latitude, lon2: cilovyBod.longitude)

        let heading: Double
        if poloha.course >= 0 && poloha.speed > 1.0 {
            heading = poloha.course
        } else if let kompas = posledniKompasHeading {
            heading = kompas
        } else {
            heading = 0
        }

        let relativniUhel = (azimutKCili - heading + 360).truncatingRemainder(dividingBy: 360)

        if !kroky.isEmpty, !jePosledniKrok, vzdalenost < 20 {
            aktualniKrokIndex += 1
        }

        let prahy = nastaveni ?? NastaveniManager()
        let zona = prahy.zonaProVzdalenost(vzdalenost)

        let vzdText = vzdalenost > 1000 ? String(format: "%.1f km", vzdalenost / 1000) : "\(Int(vzdalenost)) m"
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let hodiny = formatter.string(from: Date())

        let bezpecnyPokyn = textPokynu.replacingOccurrences(of: ",", with: ";")

        let zprava = "\(Int(relativniUhel)),---,\(zona),\(hodiny),\(vzdText),\(bezpecnyPokyn),\(prahy.blikaniMod.rawValue)"

        DispatchQueue.main.async {
            self.poslednaZprava = zprava
            self.aktualniUhel = Int(relativniUhel)
            self.aktualniVzdalenost = vzdText
            self.aktualniCas = hodiny
            self.aktualniPokyn = textPokynu
            self.aktualniZona = zona
        }
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

    // --- DEBUG / SIMULACE GPS ---
    private func spustitDebugSimulaci() {
        let start: CLLocationCoordinate2D
        if let znama = aktualniPoloha {
            start = znama
        } else {
            let nahodnyAzimut = Double.random(in: 0..<360)
            start = bodVeSmeru(
                z: CLLocationCoordinate2D(latitude: cilLat, longitude: cilLon),
                azimut: nahodnyAzimut,
                vzdalenostM: 800
            )
        }
        debugPoloha = start
        DispatchQueue.main.async { self.aktualniPoloha = start }

        debugTimer?.invalidate()
        debugTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.debugKrok()
        }
    }

    private func zastavitDebugSimulaci() {
        debugTimer?.invalidate()
        debugTimer = nil
    }

    private func debugKrok() {
        guard let soucasna = debugPoloha else { return }

        let finalniCil = CLLocationCoordinate2D(latitude: cilLat, longitude: cilLon)
        let vzdalenostKFinalnimuCili = spoctiVzdalenost(
            lat1: soucasna.latitude, lon1: soucasna.longitude,
            lat2: finalniCil.latitude, lon2: finalniCil.longitude
        )

        if vzdalenostKFinalnimuCili < 8 {
            zastavitDebugSimulaci()
            return
        }

        let (smerovyBod, _, _) = ziskejAktualniCilovyBod()
        let rychlostMS = (nastaveni?.debugRychlostKmh ?? 40) / 3.6
        let krokM = rychlostMS * 0.2

        var azimut = spoctiAzimut(
            lat1: soucasna.latitude, lon1: soucasna.longitude,
            lat2: smerovyBod.latitude, lon2: smerovyBod.longitude
        )
        azimut += Double.random(in: -3...3)

        let novaPoloha = bodVeSmeru(z: soucasna, azimut: azimut, vzdalenostM: krokM)
        debugPoloha = novaPoloha

        let simulovanaPoloha = CLLocation(
            coordinate: novaPoloha,
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: azimut,
            speed: rychlostMS,
            timestamp: Date()
        )

        DispatchQueue.main.async { self.aktualniPoloha = novaPoloha }
        vyhodnotPozici(poloha: simulovanaPoloha)
    }

    private func bodVeSmeru(z bod: CLLocationCoordinate2D, azimut stupne: Double, vzdalenostM: Double) -> CLLocationCoordinate2D {
        let R = 6371000.0
        let brng = stupne * .pi / 180
        let lat1 = bod.latitude * .pi / 180
        let lon1 = bod.longitude * .pi / 180

        let lat2 = asin(sin(lat1) * cos(vzdalenostM / R) + cos(lat1) * sin(vzdalenostM / R) * cos(brng))
        let lon2 = lon1 + atan2(sin(brng) * sin(vzdalenostM / R) * cos(lat1), cos(vzdalenostM / R) - sin(lat1) * sin(lat2))

        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
}

// MARK: - Vyhledávání adres
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

// MARK: - Mapa
struct MapaView: UIViewRepresentable {
    var cil: CLLocationCoordinate2D?
    var trasa: [CLLocationCoordinate2D]
    var tmavyRezim: Bool
    var simulovanaPoloha: CLLocationCoordinate2D? = nil

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = true
        mapView.delegate = context.coordinator
        mapView.userTrackingMode = .follow
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.overrideUserInterfaceStyle = tmavyRezim ? .dark : .light
        mapView.showsUserLocation = (simulovanaPoloha == nil)

        let stareAnotace = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(stareAnotace)
        mapView.removeOverlays(mapView.overlays)

        if let cil = cil {
            let pin = MKPointAnnotation()
            pin.coordinate = cil
            pin.title = "Cíl"
            mapView.addAnnotation(pin)
        }

        if let simPoloha = simulovanaPoloha {
            let simPin = MKPointAnnotation()
            simPin.coordinate = simPoloha
            simPin.title = "SIMULACE"
            mapView.addAnnotation(simPin)
            mapView.setCenter(simPoloha, animated: true)
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

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation.title == "SIMULACE" else { return nil }
            let identifier = "simulace_pin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.markerTintColor = UIColor(Moto.jantar)
            view.glyphText = "S"
            return view
        }
    }
}

// MARK: - Nastavení obrazovka
struct NastaveniView: View {
    @ObservedObject var nastaveni: NastaveniManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let paleta = nastaveni.paleta
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Interval odesílání dat do ESP32")
                        Slider(value: $nastaveni.odesilaciInterval, in: 0.01...2.0, step: 0.01)
                        HStack {
                            Text("\(String(format: "%.2f", nastaveni.odesilaciInterval)) s")
                                .bold()
                            Spacer()
                            Text("\(Int(1.0 / nastaveni.odesilaciInterval)) Hz")
                                .foregroundColor(paleta.textTlumeny)
                        }
                    }
                } header: {
                    Text("Časovač odesílání (Timer)")
                } footer: {
                    Text("Určuje, jak často se posílají nová data přes BLE nezávisle na GPS updatech.")
                }

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

                Section {
                    Toggle("Simulovat pohyb k cíli", isOn: $nastaveni.debugSimulace)

                    if nastaveni.debugSimulace {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Rychlost simulace")
                            Slider(value: $nastaveni.debugRychlostKmh, in: 5...120, step: 5)
                            Text("\(Int(nastaveni.debugRychlostKmh)) km/h")
                                .foregroundColor(paleta.textTlumeny)
                        }
                    }
                } header: {
                    Text("Debug / testování")
                } footer: {
                    if nastaveni.debugSimulace {
                        Text("Zapnuto: poloha se bude automaticky pohybovat směrem k cíli přes zvolenou trasu místo reálného GPS.")
                    } else {
                        Text("Zapni pro otestování displeje ESP32 bez nutnosti reálně jet.")
                    }
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

// MARK: - Hlavní UI
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

            VStack(spacing: 12) {
                // Horní lišta
                HStack {
                    VStack(alignment: .leading) {
                        Text("MOTO NAVI")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(paleta.textHlavni)
                        Text(navi.stavPripojeni)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(navi.stavPripojeni == "SPOJENO" ? Moto.signal : Moto.redline)
                    }

                    Spacer()

                    Button(action: { navi.pripojitESP32() }) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .padding(10)
                            .background(paleta.panel)
                            .cornerRadius(8)
                            .foregroundColor(paleta.textHlavni)
                    }

                    Button(action: { zobrazNastaveni = true }) {
                        Image(systemName: "gearshape.fill")
                            .padding(10)
                            .background(paleta.panel)
                            .cornerRadius(8)
                            .foregroundColor(paleta.textHlavni)
                    }
                }
                .padding(.horizontal)

                // Vyhledávací pole
                VStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(paleta.textTlumeny)
                        TextField("Kam chcete jet?", text: $hledaniText)
                            .foregroundColor(paleta.textHlavni)
                            .onChange(of: hledaniText) { novyText in // Opraveno na iOS 16.0+ syntaxi
                                hledac.hledej(novyText)
                                zobrazNavrhy = !novyText.isEmpty
                            }
                        if !hledaniText.isEmpty {
                            Button(action: {
                                hledaniText = ""
                                zobrazNavrhy = false
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(paleta.textTlumeny)
                            }
                        }
                    }
                    .padding(12)
                    .background(paleta.panel)
                    .cornerRadius(10)

                    if zobrazNavrhy && !hledac.navrhy.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(hledac.navrhy, id: \.self) { navrh in
                                    Button(action: {
                                        hledac.vyhledejSouradnice(pro: navrh) { coords, název in
                                            if let coords = coords {
                                                cilSouradnice = coords
                                                cilNazev = název
                                                hledaniText = název
                                                zobrazNavrhy = false
                                                
                                                if let start = navi.aktualniPoloha {
                                                    spocitejTrasu(z: start, do: coords) { route in
                                                        if let route = route {
                                                            let points = route.polyline.points()
                                                            let count = route.polyline.pointCount
                                                            var coordsList: [CLLocationCoordinate2D] = []
                                                            for i in 0..<count {
                                                                coordsList.append(points[i].coordinate)
                                                            }
                                                            trasaBody = coordsList
                                                            navi.nastavTrasu(kroky: route.steps, cilLat: coords.latitude, cilLon: coords.longitude)
                                                        } else {
                                                            navi.nastavCil(lat: coords.latitude, lon: coords.longitude)
                                                        }
                                                    }
                                                } else {
                                                    navi.nastavCil(lat: coords.latitude, lon: coords.longitude)
                                                }
                                            }
                                        }
                                    }) {
                                        VStack(alignment: .leading) {
                                            Text(navrh.title)
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(paleta.textHlavni)
                                            Text(navrh.subtitle)
                                                .font(.system(size: 12))
                                                .foregroundColor(paleta.textTlumeny)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    Divider().background(paleta.panelHranice)
                                }
                            }
                            .padding()
                        }
                        .background(paleta.panel)
                        .cornerRadius(10)
                        .frame(maxHeight: 200)
                    }
                }
                .padding(.horizontal)

                // Náhled kompasu / mapy
                if navi.aktivni {
                    VStack(spacing: 16) {
                        SmerovyUkazatel(
                            uhel: navi.aktualniUhel,
                            zona: navi.aktualniZona,
                            blikaniMod: nastaveni.blikaniMod,
                            paleta: paleta
                        )

                        VStack(spacing: 4) {
                            Text(navi.aktualniVzdalenost)
                                .font(.system(size: 36, weight: .black, design: .rounded))
                                .foregroundColor(Moto.barvaZony(navi.aktualniZona, paleta))
                            Text(navi.aktualniPokyn)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(paleta.textHlavni)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    MapaView(
                        cil: cilSouradnice,
                        trasa: trasaBody,
                        tmavyRezim: nastaveni.tmavyRezim,
                        simulovanaPoloha: nastaveni.debugSimulace ? navi.aktualniPoloha : nil
                    )
                    .cornerRadius(16)
                    .padding(.horizontal)
                    .frame(maxHeight: .infinity)
                }

                // Tlačítko Start / Stop
                VStack {
                    if navi.aktivni {
                        MotoTlacitko(
                            titulek: "Zastavit navigaci",
                            barva: Moto.redline,
                            paleta: paleta
                        ) {
                            navi.zastavitNavigaci()
                        }
                    } else {
                        MotoTlacitko(
                            titulek: "Spustit navigaci",
                            barva: Moto.signal,
                            paleta: paleta,
                            vypnuto: !navi.cilNastaven
                        ) {
                            navi.spustitNavigaci()
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            navi.nastaveni = nastaveni
            navi.pozadejOOpravneni()
        }
        .sheet(isPresented: $zobrazNastaveni) {
            NastaveniView(nastaveni: nastaveni)
        }
    }
}
