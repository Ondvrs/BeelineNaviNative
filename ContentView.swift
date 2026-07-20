import SwiftUI
import CoreLocation
import CoreBluetooth
import MapKit
import ActivityKit // Potřebné pro Dynamic Island / Live Activities

// MARK: - UUID musi presne sedet s ESP32 kodem
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

// MARK: - Paleta (tmava / svetla)
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

// MARK: - Live Activity Attributes
struct ManevrAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var vzdalenost: String
        var pokyn: String
        var uhel: Int
        var zona: Int
    }
    var cilMisto: String
}

// MARK: - Model pro Oblibene cíle
struct OblibeneMisto: Codable, Identifiable, Equatable {
    var id = UUID()
    let nazev: String
    let latitude: Double
    let longitude: Double
}

// MARK: - Správa oblíbených míst
class OblibeneManager: ObservableObject {
    @Published var sekceOblibene: [OblibeneMisto] = []
    
    init() {
        nactiOblibene()
    }
    
    func pridejMisto(nazev: String, lat: Double, lon: Double) {
        if sekceOblibene.contains(where: { $0.latitude == lat && $0.longitude == lon }) { return }
        let nove = OblibeneMisto(nazev: nazev, latitude: lat, longitude: lon)
        sekceOblibene.append(nove)
        ulozOblibene()
    }
    
    func smazMisto(at offsets: IndexSet) {
        sekceOblibene.remove(atOffsets: offsets)
        ulozOblibene()
    }
    
    private func ulozOblibene() {
        if let data = try? JSONEncoder().encode(sekceOblibene) {
            UserDefaults.standard.set(data, forKey: "oblibeneMistaTrasy")
        }
    }
    
    private func nactiOblibene() {
        if let data = UserDefaults.standard.data(forKey: "oblibeneMistaTrasy"),
           let nacteno = try? JSONDecoder().decode([OblibeneMisto].self, from: data) {
            self.sekceOblibene = nacteno
        } else {
            // Prednastavena testovaci motorkarska mista
            self.sekceOblibene = [
                OblibeneMisto(nazev: "Karlštejn vyhlídka", latitude: 49.9392, longitude: 14.1839),
                OblibeneMisto(nazev: "Moto Azyl (Dubá)", latitude: 50.5401, longitude: 14.5398)
            ]
        }
    }
}

// MARK: - Nastaveni (UserDefaults)
enum BlikaniMod: Int, CaseIterable, Identifiable {
    case zadne = 0
    case sipka = 1
    case pozadi = 2

    var id: Int { rawValue }
    var nazev: String {
        switch self {
        case .zadne: return "Nic"
        case .sipka: return "Šipka"
        case .pozadi: return "Pozadí"
        }
    }
}

class NastaveniManager: ObservableObject {
    @Published var vzdalenostZelena: Double { didSet { UserDefaults.standard.set(vzdalenostZelena, forKey: "vzdalenostZelena") } }
    @Published var vzdalenostOranzova: Double { didSet { UserDefaults.standard.set(vzdalenostOranzova, forKey: "vzdalenostOranzova") } }
    @Published var vzdalenostCervena: Double { didSet { UserDefaults.standard.set(vzdalenostCervena, forKey: "vzdalenostCervena") } }
    @Published var blikaniMod: BlikaniMod { didSet { UserDefaults.standard.set(blikaniMod.rawValue, forKey: "blikaniMod") } }
    @Published var tmavyRezim: Bool { didSet { UserDefaults.standard.set(tmavyRezim, forKey: "tmavyRezim") } }

    var paleta: MotoPaleta { tmavyRezim ? .tmava : .svetla }

    init() {
        let d = UserDefaults.standard
        self.vzdalenostZelena = d.object(forKey: "vzdalenostZelena") as? Double ?? 100
        self.vzdalenostOranzova = d.object(forKey: "vzdalenostOranzova") as? Double ?? 50
        self.vzdalenostCervena = d.object(forKey: "vzdalenostCervena") as? Double ?? 15
        self.blikaniMod = BlikaniMod(rawValue: d.integer(forKey: "blikaniMod")) ?? .zadne
        self.tmavyRezim = d.object(forKey: "tmavyRezim") as? Bool ?? true
    }

    func zonaProVzdalenost(_ metry: Double) -> Int {
        if metry <= vzdalenostCervena { return 3 }
        if metry <= vzdalenostOranzova { return 2 }
        if metry <= vzdalenostZelena { return 1 }
        return 0
    }
}

// MARK: - Hlavni logika (Poloha + BLE + Recalculation + Live Activities)
class NaviManager: NSObject, ObservableObject, CLLocationManagerDelegate, CBCentralManagerDelegate, CBPeripheralDelegate {

    private var locationManager = CLLocationManager()
    private var centralManager: CBCentralManager!
    private var esp32Peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var liveActivity: Activity<ManevrAttributes>?

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

    // Turn-by-turn kroky a ochrana proti zacykleni prepoctu
    private var kroky: [MKRoute.Step] = []
    private var aktualniKrokIndex: Int = 0
    private var probihaRecalculace = false

    var cilLat: Double = 0
    var cilLon: Double = 0
    var cilMistoNazev: String = "Cíl trasy"
    var cilNastaven: Bool = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true

        // Inicializace BLE s podporou behu na pozadi
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: "BeelineRestorationKey"])
    }

    func pozadejOOpravneni() {
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
    }

    func nastavTrasu(kroky noveKroky: [MKRoute.Step], cilLat: Double, cilLon: Double, nazevMista: String) {
        self.kroky = noveKroky.filter { $0.polyline.pointCount > 0 }
        self.aktualniKrokIndex = 0
        self.cilLat = cilLat
        self.cilLon = cilLon
        self.cilMistoNazev = nazevMista
        self.cilNastaven = true
        
        // Nastartujeme Live Activity na zamknutou obrazovku telefonu
        spustLiveActivity()
    }

    func pripojitESP32() {
        if centralManager.state == .poweredOn {
            stavPripojeni = "Hledám budík..."
            centralManager.scanForPeripherals(withServices: [SERVICE_UUID], options: nil)
        }
    }

    func spustitNavigaci() {
        aktivni = true
        locationManager.startUpdatingLocation()
    }

    func zastavitNavigaci() {
        aktivni = false
        locationManager.stopUpdatingLocation()
        ukonciLiveActivity()
    }

    // Nativni iOS sdileni aktualni polohy přes SMS, Messenger atd.
    func sdilejPolohu() {
        guard let pos = aktualniPoloha else { return }
        let textSdilenir = "Moje aktualni moto-poloha: https://maps.apple.com/?ll=\(pos.latitude),\(pos.longitude)"
        let av = UIActivityViewController(activityItems: [textSdilenir], applicationActivities: nil)
        if let rootVC = UIApplication.shared.windows.first?.rootViewController {
            rootVC.present(av, animated: true, completion: nil)
        }
    }

    // --- CBCentralManagerDelegate & AUTO-RECONNECT ---
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            print("Bluetooth aktivní. Startuji auto-scan.")
            pripojitESP32() // Automatický scan ihned po zapnutí appky
        } else {
            stavPripojeni = "BT Vypnutý"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        centralManager.stopScan()
        esp32Peripheral = peripheral
        esp32Peripheral?.delegate = self
        centralManager.connect(peripheral, options: nil)
        stavPripojeni = "Připojování..."
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        stavPripojeni = "Čtení HUD..."
        peripheral.discoverServices([SERVICE_UUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("BLE Spojeni ztraceno! Spoustim auto-reconnect smyčku...")
        stavPripojeni = "Ztraceno - Hledám..."
        writeCharacteristic = nil
        // Agresivni auto-reconnect bez nutnosti uzivatelskeho kliknuti
        centralManager.scanForPeripherals(withServices: [SERVICE_UUID], options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        // Obnova BLE stavu ze strany OS, pokud byla aplikace uspana na pozadi
        if let peripherals = dict[CBCentralManagerRestoredPeripheralsKey] as? [CBPeripheral], let prvni = peripherals.first {
            self.esp32Peripheral = prvni
            self.esp32Peripheral?.delegate = self
            stavPripojeni = "Obnoveno"
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
            stavPripojeni = "ONLINE"
        }
    }

    // --- CLLocationManagerDelegate & AUTOMATICKÝ PŘEPOČET ---
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let poloha = locations.last else { return }
        DispatchQueue.main.async {
            self.aktualniPoloha = poloha.coordinate
        }
        if cilNastaven {
            vyhodnotPozici(poloha: poloha)
        }
    }

    private func vyhodnotPozici(poloha: CLLocation) {
        let myLat = poloha.coordinate.latitude
        let myLon = poloha.coordinate.longitude

        let cilovyBod: CLLocationCoordinate2D
        var textPokynu: String
        var jePosledniKrok = true

        if !kroky.isEmpty, aktualniKrokIndex < kroky.count {
            let krok = kroky[aktualniKrokIndex]
            cilovyBod = krok.polyline.prvniBod
            textPokynu = krok.instructions.isEmpty ? "Pokračujte rovně" : krok.instructions
            jePosledniKrok = (aktualniKrokIndex == kroky.count - 1)
            
            // --- LOGIKA AUTOMATICKÉHO PŘEPOČTU (RECALCULATION) ---
            // Zjistime realnou kolmou vzdálenost od aktuálního segmentu cesty
            let vzdalenostOdKroku = spoctiVzdalenost(lat1: myLat, lon1: myLon, lat2: cilovyBod.latitude, lon2: cilovyBod.longitude)
            
            // Pokud jsme od manévru dál než 85 metrů a nejedná se o dálniční úsek, spustíme re-routing
            if vzdalenostOdKroku > 85.0 && !probihaRecalculace && vzdalenostOdKroku < 5000 {
                vynutPrepocetTrasy(z: poloha.coordinate)
                return
            }
        } else {
            cilovyBod = CLLocationCoordinate2D(latitude: cilLat, longitude: cilLon)
            textPokynu = "Jed k cíli"
        }

        let vzdalenost = spoctiVzdalenost(lat1: myLat, lon1: myLon, lat2: cilovyBod.latitude, lon2: cilovyBod.longitude)
        let azimut = spoctiAzimut(lat1: myLat, lon1: myLon, lat2: cilovyBod.latitude, lon2: cilovyBod.longitude)

        // Odbočka úspěšně projeta -> skok na další krok navigace
        if !kroky.isEmpty, !jePosledniKrok, vzdalenost < 22 {
            aktualniKrokIndex += 1
        }

        let prahy = nastaveni ?? NastaveniManager()
        let zona = prahy.zonaProVzdalenost(vzdalenost)
        let vzdText = vzdalenost > 1000 ? String(format: "%.1f km", vzdalenost / 1000) : "\(Int(vzdalenost)) m"
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let hodiny = formatter.string(from: Date())
        let bezpecnyPokyn = textPokynu.replacingOccurrences(of: ",", with: ";")

        let zprava = "\(Int(azimut)),---,\(zona),\(hodiny),\(vzdText),\(bezpecnyPokyn),\(prahy.blikaniMod.rawValue)"

        DispatchQueue.main.async {
            self.poslednaZprava = zprava
            self.aktualniUhel = Int(azimut)
            self.aktualniVzdalenost = vzdText
            self.aktualniCas = hodiny
            self.aktualniPokyn = textPokynu
            self.aktualniZona = zona
            
            // Aktualizace Live Activity na displeji iPhonu
            self.aktualizujLiveActivity(vzd: vzdText, pok: textPokynu, uh: Int(azimut), zn: zona)
        }
        posliDoBLE(zprava)
    }

    private func vynutPrepocetTrasy(z aktualniSouradnice: CLLocationCoordinate2D) {
        guard !probihaRecalculace else { return }
        probihaRecalculace = true
        
        print("Sjetí z trasy detekováno! Přepočítávám...")
        
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: aktualniSouradnice))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: cilLat, longitude: cilLon)))
        request.transportType = .automobile
        
        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, error in
            guard let self = self else { return }
            self.probihaRecalculace = false
            
            if let novaTrasa = response?.routes.first {
                DispatchQueue.main.mainAsyncIfNeeded {
                    self.kroky = novaTrasa.steps.filter { $0.polyline.pointCount > 0 }
                    self.aktualniKrokIndex = 0
                    print("Trasa úspěšně přepočítána na pozadí.")
                }
            }
        }
    }

    // --- Live Activities Engine ---
    private func spustLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ManevrAttributes(cilMisto: cilMistoNazev)
        let state = ManevrAttributes.ContentState(vzdalenost: "---", pokyn: "Spouštím...", uhel: 0, zona: 0)
        
        do {
            liveActivity = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
        } catch {
            print("Chyba spuštění Live Activity: \(error.localizedDescription)")
        }
    }

    private func aktualizujLiveActivity(vzd: String, pok: String, uh: Int, zn: Int) {
        Task {
            let upravenyStav = ManevrAttributes.ContentState(vzdalenost: vzd, pokyn: pok, uhel: uh, zona: zn)
            await liveActivity?.update(using: upravenyStav)
        }
    }

    private func ukonciLiveActivity() {
        Task {
            await liveActivity?.end(dismissPolicy: .immediate)
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
}

// Bezpečné asynchronní odesílání na hlavní vlákno
extension DispatchQueue {
    static func mainAsyncIfNeeded(execute work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { main.async(execute: work) }
    }
}

// MARK: - Znovupoužitelné komponenty UI
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
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundColor(vypnuto ? paleta.textTlumeny : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(vypnuto ? paleta.panelHranice : barva)
                .cornerRadius(10)
        }
        .disabled(vypnuto)
    }
}

struct StavIndikator: View {
    let stav: String
    let paleta: MotoPaleta
    var body: some View {
        Text(stav.uppercased())
            .font(.system(size: 11, weight: .black, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundColor(stav == "ONLINE" ? .black : paleta.textHlavni)
            .background(stav == "ONLINE" ? Moto.signal : paleta.panel)
            .cornerRadius(6)
    }
}

// MARK: - Kruhovy ukazatel smyslu jízdy
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
                .frame(width: 180, height: 180)

            ForEach(0..<24) { i in
                Rectangle()
                    .fill(paleta.textTlumeny.opacity(0.4))
                    .frame(width: 2, height: i % 6 == 0 ? 10 : 5)
                    .offset(y: -82)
                    .rotationEffect(.degrees(Double(i) * 15))
            }

            SipkaTvar()
                .fill(barvaSipky)
                .frame(width: 60, height: 95)
                .rotationEffect(.degrees(Double(uhel)))
                .animation(.easeOut(duration: 0.3), value: uhel)
        }
        .frame(width: 180, height: 180)
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

// MARK: - Adresy Hledac & Naseptavac
class AdresyHledac: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    @Published var navrhy: [MKLocalSearchCompletion] = []

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func hledej(_ text: String) {
        completer.queryFragment = text
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async { self.navrhy = completer.results }
    }
}

func spocitejTrasu(z start: CLLocationCoordinate2D, do cil: CLLocationCoordinate2D, dokonceni: @escaping (MKRoute?) -> Void) {
    let request = MKDirections.Request()
    request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: cil))
    request.transportType = .automobile

    let directions = MKDirections(request: request)
    directions.calculate { response, _ in
        DispatchQueue.main.async { dokonceni(response?.routes.first) }
    }
}

// MARK: - Mapa View Bridge
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
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
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
            mapView.setVisibleMapRect(polyline.boundingMapRect, edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40), animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: polyline)
                r.strokeColor = UIColor(Moto.redline)
                r.lineWidth = 5
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Obrazovka Nastavení
struct NastaveniView: View {
    @ObservedObject var nastaveni: NastaveniManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let paleta = nastaveni.paleta
        NavigationView {
            Form {
                Section(header: Text("Prahy zón pro změnu barev")) {
                    VStack(alignment: .leading) {
                        Text("Zelená zóna: \(Int(nastaveni.vzdalenostZelena)) m")
                        Slider(value: $nastaveni.vzdalenostZelena, in: 30...400, step: 5)
                    }
                    VStack(alignment: .leading) {
                        Text("Oranžová zóna: \(Int(nastaveni.vzdalenostOranzova)) m")
                        Slider(value: $nastaveni.vzdalenostOranzova, in: 10...200, step: 5)
                    }
                    VStack(alignment: .leading) {
                        Text("Červená zóna (kritická): \(Int(nastaveni.vzdalenostCervena)) m")
                        Slider(value: $nastaveni.vzdalenostCervena, in: 3...60, step: 1)
                    }
                }
                Section(header: Text("Efekty a styl")) {
                    Picker("Styl blikání", selection: $nastaveni.blikaniMod) {
                        ForEach(BlikaniMod.allCases) { m in Text(m.nazev).tag(m) }
                    }.pickerStyle(.segmented)
                    Toggle("Tmavý kokpit režim", isOn: $nastaveni.tmavyRezim)
                }
            }
            .navigationTitle("Konfigurace HUD")
            .toolbar { Button("Uložit") { dismiss() } }
        }
    }
}

// MARK: - HLAVNÍ KOKPIT APLIKACE (UI)
struct ContentView: View {
    @StateObject private var navi = NaviManager()
    @StateObject private var hledac = AdresyHledac()
    @StateObject private var nastaveni = NastaveniManager()
    @StateObject private var oblibene = OblibeneManager()

    @State private var hledaniText: String = ""
    @State private var cilSouradnice: CLLocationCoordinate2D?
    @State private var cilNazev: String = ""
    @State private var trasaBody: [CLLocationCoordinate2D] = []
    
    @State private var zobrazNavrhy = false
    @State private var zobrazNastaveni = false

    init() {
        // Správné navázání managerů při startu aplikace
        let nav = NaviManager()
        let nast = NastaveniManager()
        nav.nastaveni = nast
        _navi = StateObject(wrappedValue: nav)
        _nastaveni = StateObject(wrappedValue: nast)
    }

    var body: some View {
        let paleta = nastaveni.paleta

        ZStack {
            paleta.asfalt.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    // Záhlaví a status
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("BEELINE")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundColor(paleta.textHlavni)
                            Moto.eyebrow("Moto Telemetry System", paleta)
                        }
                        Spacer()
                        StavIndikator(stav: navi.stavPripojeni, paleta: paleta)
                        
                        Button { zobrazNastaveni = true } label: {
                            Image(systemName: "slider.horizontal.3")
                                .padding(10)
                                .background(paleta.panel)
                                .foregroundColor(paleta.textHlavni)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.top, 6)

                    // Budík & Telemetrické hodnoty
                    MotoPanel(paleta) {
                        VStack(spacing: 12) {
                            SmerovyUkazatel(uhel: navi.aktualniUhel, zona: navi.aktualniZona, blikaniMod: nastaveni.blikaniMod, paleta: paleta)

                            HStack {
                                VStack {
                                    Moto.eyebrow("Vzdálenost", paleta)
                                    Text(navi.aktualniVzdalenost).font(.system(size: 20, weight: .bold, design: .monospaced))
                                }
                                Spacer()
                                VStack {
                                    Moto.eyebrow("GPS Čas", paleta)
                                    Text(navi.aktualniCas).font(.system(size: 20, weight: .bold, design: .monospaced))
                                }
                                Spacer()
                                VStack {
                                    Moto.eyebrow("Aktivní Pokyn", paleta)
                                    Text(navi.aktualniPokyn)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(Moto.barvaZony(navi.aktualniZona, paleta))
                                        .lineLimit(2).multilineTextAlignment(.center)
                                }
                            }
                        }
                    }

                    // Sekce 2: Hledání a Správa Trasy
                    MotoPanel(paleta) {
                        VStack(alignment: .leading, spacing: 10) {
                            Moto.eyebrow("Cíl cesty & Vyhledávání", paleta)

                            HStack {
                                TextField("Zadejte adresu trasy...", text: $hledaniText)
                                    .padding(10)
                                    .background(paleta.asfalt)
                                    .foregroundColor(paleta.textHlavni)
                                    .cornerRadius(8)
                                    .onChange(of: hledaniText) { nv in
                                        hledac.hledej(nv)
                                        zobrazNavrhy = !nv.isEmpty
                                    }
                            }

                            // Našeptávač výsledků z Apple MapKit
                            if zobrazNavrhy && !hledac.navrhy.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(hledac.navrhy.prefix(4), id: \.self) { navrh in
                                        Button {
                                            vyberAadresu(navrh)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(navrh.title).font(.system(size: 13, weight: .bold)).foregroundColor(paleta.textHlavni)
                                                if !navrh.subtitle.isEmpty {
                                                    Text(navrh.subtitle).font(.system(size: 11)).foregroundColor(paleta.textTlumeny)
                                                }
                                            }
                                            .padding(.vertical, 6)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        Divider()
                                    }
                                }
                            }

                            // OBLÍBENÉ CÍLE (Quick-Select z paměti telefonu)
                            if !oblibene.sekceOblibene.isEmpty && hledaniText.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("OBLÍBENÉ / HISTORIE").font(.system(size: 9, weight: .heavy)).foregroundColor(paleta.textTlumeny)
                                    
                                    ForEach(oblibene.sekceOblibene) { misto in
                                        Button {
                                            aktivujOblibeneMisto(misto)
                                        } label: {
                                            HStack {
                                                Image(systemName: "star.fill").foregroundColor(Moto.jantar).font(.system(size: 11))
                                                Text(misto.nazev).font(.system(size: 13, weight: .medium)).foregroundColor(paleta.textHlavni)
                                                Spacer()
                                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundColor(paleta.textTlumeny)
                                            }
                                            .padding(8)
                                            .background(paleta.asfalt)
                                            .cornerRadius(6)
                                        }
                                    }
                                }
                                .padding(.top, 4)
                            }

                            if !cilNazev.isEmpty {
                                Text("Vybráno: \(cilNazev)").font(.system(size: 13, weight: .bold)).foregroundColor(Moto.signal)
                                
                                HStack(spacing: 10) {
                                    MotoTlacitko(titulek: "Start Navigace", barva: Moto.signal, paleta: paleta, action: {
                                        navi.spustitNavigaci()
                                    })
                                    
                                    MotoTlacitko(titulek: "Stop", barva: Moto.redline, paleta: paleta, action: {
                                        navi.zastavitNavigaci()
                                        trasaBody = []
                                        cilNazev = ""
                                    })
                                }
                                
                                // Rychlé sdílení GPS koordinátů za jízdy kamarádům
                                Button(action: { navi.sdilejPolohu() }) {
                                    HStack {
                                        Image(systemName: "square.and.arrow.up")
                                        Text("SDÍLET MOJI AKTUÁLNÍ POLOHU")
                                    }
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(paleta.textHlavni)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(paleta.panelHranice)
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }

                    // Sekce 3: Živá kontrolní mapa trasy
                    MotoPanel(paleta) {
                        VStack(alignment: .leading, spacing: 8) {
                            Moto.eyebrow("3 · Kontrolní live-mapa", paleta)
                            MapaView(cil: cilSouradnice, trasa: trasaBody, tmavyRezim: nastaveni.tmavyRezim)
                                .frame(height: 200)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            navi.pozadejOOpravneni()
        }
        .sheet(isPresented: $zobrazNastaveni) {
            String(describing: NastaveniView(nastaveni: nastaveni))
        }
    }

    private func vyberAadresu(_ navrh: MKLocalSearchCompletion) {
        zobrazNavrhy = false
        hledaniText = ""
        
        let request = MKLocalSearch.Request(completion: navrh)
        MKLocalSearch(request: request).start { response, _ in
            guard let item = response?.mapItems.first, let aktualniGPS = navi.aktualniPoloha else { return }
            
            let coord = item.placemark.coordinate
            self.cilSouradnice = coord
            self.cilNazev = item.name ?? navrh.title
            
            // Uložíme do historie/oblíbených automaticky
            self.oblibene.pridejMisto(nazev: self.cilNazev, lat: coord.latitude, lon: coord.longitude)
            
            spocitejTrasu(z: aktualniGPS, do: coord) { route in
                if let r = route {
                    self.trasaBody = r.polyline.points().map { $0.coordinate }
                    self.navi.nastavTrasu(kroky: r.steps, cilLat: coord.latitude, cilLon: coord.longitude, nazevMista: self.cilNazev)
                }
            }
        }
    }
    
    private func aktivujOblibeneMisto(_ misto: OblibeneMisto) {
        guard let aktualniGPS = navi.aktualniPoloha else { return }
        let coord = CLLocationCoordinate2D(latitude: misto.latitude, longitude: misto.longitude)
        self.cilSouradnice = coord
        self.cilNazev = misto.nazev
        
        spocitejTrasu(z: aktualniGPS, do: coord) { route in
            if let r = route {
                self.trasaBody = r.polyline.points().map { $0.coordinate }
                self.navi.nastavTrasu(kroky: r.steps, cilLat: coord.latitude, cilLon: coord.longitude, nazevMista: self.cilNazev)
            }
        }
    }
}

// Rozšíření pro bezpečné renderování polyline koordinátů
extension MKPolyline {
    var prvniBod: CLLocationCoordinate2D {
        guard pointCount > 0 else { return coordinate }
        return points()[0].coordinate
    }
}
