import SwiftUI
import CoreLocation
import CoreBluetooth
import MapKit

// MARK: - UUID musi presne sedet s ESP32 kodem (BeelinePrototyp_ESP32S3.ino)
let SERVICE_UUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
let CHARACTERISTIC_UUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")

// MARK: - Design tokeny (moto/dashboard styl)
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

enum Moto {
    static let asfalt = Color(hex: "0D0F12")
    static let panel = Color(hex: "1A1D21")
    static let panelHranice = Color(hex: "2A2E33")
    static let redline = Color(hex: "FF4713")
    static let jantar = Color(hex: "FFB800")
    static let signal = Color(hex: "00E676")
    static let textHlavni = Color(hex: "F2F0EB")
    static let textTlumeny = Color(hex: "6B7280")

    static func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(1.8)
            .foregroundColor(Moto.textTlumeny)
    }
}

struct MotoPanel<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(16)
            .background(Moto.panel)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Moto.panelHranice, lineWidth: 1))
            .cornerRadius(14)
    }
}

struct MotoTlacitko: View {
    let titulek: String
    let barva: Color
    let action: () -> Void
    var vypnuto: Bool = false

    var body: some View {
        Button(action: action) {
            Text(titulek.uppercased())
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundColor(vypnuto ? Moto.textTlumeny : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(vypnuto ? Moto.panelHranice : barva)
                .cornerRadius(10)
        }
        .disabled(vypnuto)
    }
}

// MARK: - Kruhovy smerovy ukazatel (stejny princip jako displej na ESP32)
struct SmerovyUkazatel: View {
    var uhel: Int
    var aktivni: Bool
    var pulzuje: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(pulzuje ? Moto.jantar : Moto.panelHranice, lineWidth: 3)
                .frame(width: 200, height: 200)

            ForEach(0..<24) { i in
                Rectangle()
                    .fill(Moto.textTlumeny.opacity(0.5))
                    .frame(width: 2, height: i % 6 == 0 ? 10 : 5)
                    .offset(y: -92)
                    .rotationEffect(.degrees(Double(i) * 15))
            }

            SipkaTvar()
                .fill(pulzuje ? Moto.jantar : (aktivni ? Moto.redline : Moto.textTlumeny))
                .frame(width: 70, height: 110)
                .rotationEffect(.degrees(Double(uhel)))
                .animation(.easeOut(duration: 0.35), value: uhel)
        }
        .frame(width: 200, height: 200)
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

// MARK: - Hlavni logika (poloha + BLE), bezi i na pozadi
class NaviManager: NSObject, ObservableObject, CLLocationManagerDelegate, CBCentralManagerDelegate, CBPeripheralDelegate {

    private var locationManager = CLLocationManager()
    private var centralManager: CBCentralManager!
    private var esp32Peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?

    @Published var stavPripojeni: String = "Odpojeno"
    @Published var poslednaZprava: String = "---"
    @Published var aktivni: Bool = false
    @Published var aktualniPoloha: CLLocationCoordinate2D?

    @Published var aktualniUhel: Int = 0
    @Published var aktualniVzdalenost: String = "---"
    @Published var aktualniCas: String = "---"
    @Published var aktualniPokyn: String = "---"
    @Published var blizkoOdbocky: Bool = false

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

    func nastavCil(lat: Double, lon: Double) {
        cilLat = lat
        cilLon = lon
        cilNastaven = true
    }

    func pripojitESP32() {
        stavPripojeni = "Hledam ESP32..."
        centralManager.scanForPeripherals(withServices: [SERVICE_UUID], options: nil)
    }

    func spustitNavigaci() {
        aktivni = true
        locationManager.startUpdatingLocation()
    }

    func zastavitNavigaci() {
        aktivni = false
        locationManager.stopUpdatingLocation()
    }

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

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
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

    private func vyhodnotPozici(poloha: CLLocation) {
        let myLat = poloha.coordinate.latitude
        let myLon = poloha.coordinate.longitude

        let vzdalenost = spoctiVzdalenost(lat1: myLat, lon1: myLon, lat2: cilLat, lon2: cilLon)
        let azimut = spoctiAzimut(lat1: myLat, lon1: myLon, lat2: cilLat, lon2: cilLon)

        let vzdText = vzdalenost > 1000 ? String(format: "%.1f km", vzdalenost / 1000) : "\(Int(vzdalenost)) m"
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let hodiny = formatter.string(from: Date())
        let blizko = vzdalenost < 60

        let zprava = "\(Int(azimut)),---,\(blizko ? 1 : 0),\(hodiny),\(vzdText),Jed k cili"

        DispatchQueue.main.async {
            self.poslednaZprava = zprava
            self.aktualniUhel = Int(azimut)
            self.aktualniVzdalenost = vzdText
            self.aktualniCas = hodiny
            self.aktualniPokyn = blizko ? "Blízko cíle" : "Jed k cíli"
            self.blizkoOdbocky = blizko
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

func spocitejTrasuNaMape(z start: CLLocationCoordinate2D, do cil: CLLocationCoordinate2D, dokonceni: @escaping ([CLLocationCoordinate2D]) -> Void) {
    let request = MKDirections.Request()
    request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: cil))
    request.transportType = .automobile

    let directions = MKDirections(request: request)
    directions.calculate { response, error in
        guard let route = response?.routes.first else {
            dokonceni([])
            return
        }
        let pocetBodu = route.polyline.pointCount
        var souradnice = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pocetBodu)
        route.polyline.getCoordinates(&souradnice, range: NSRange(location: 0, length: pocetBodu))
        DispatchQueue.main.async {
            dokonceni(souradnice)
        }
    }
}

// MARK: - Mapa v tmavem rezimu, s bezelem jako palubni displej
struct MapaView: UIViewRepresentable {
    var cil: CLLocationCoordinate2D?
    var trasa: [CLLocationCoordinate2D]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = true
        mapView.delegate = context.coordinator
        mapView.userTrackingMode = .follow
        mapView.overrideUserInterfaceStyle = .dark
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
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

// MARK: - UI
struct ContentView: View {
    @StateObject private var navi = NaviManager()
    @StateObject private var hledac = AdresyHledac()

    @State private var hledaniText: String = ""
    @State private var cilSouradnice: CLLocationCoordinate2D?
    @State private var cilNazev: String = ""
    @State private var trasaBody: [CLLocationCoordinate2D] = []
    @State private var zobrazNavrhy = false

    var body: some View {
        ZStack {
            Moto.asfalt.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("BEELINE")
                                .font(.system(size: 26, weight: .black, design: .rounded))
                                .foregroundColor(Moto.textHlavni)
                            Moto.eyebrow("Moto navigace")
                        }
                        Spacer()
                        StavIndikator(stav: navi.stavPripojeni)
                    }
                    .padding(.top, 8)

                    MotoPanel {
                        VStack(spacing: 10) {
                            SmerovyUkazatel(uhel: navi.aktualniUhel, aktivni: navi.aktivni, pulzuje: navi.blizkoOdbocky)

                            HStack {
                                VStack(spacing: 2) {
                                    Moto.eyebrow("Vzdálenost")
                                    Text(navi.aktualniVzdalenost)
                                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                                        .foregroundColor(Moto.textHlavni)
                                }
                                Spacer()
                                VStack(spacing: 2) {
                                    Moto.eyebrow("Čas")
                                    Text(navi.aktualniCas)
                                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                                        .foregroundColor(Moto.textHlavni)
                                }
                                Spacer()
                                VStack(spacing: 2) {
                                    Moto.eyebrow("Pokyn")
                                    Text(navi.aktualniPokyn)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(navi.blizkoOdbocky ? Moto.jantar : Moto.textHlavni)
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                    }

                    MotoPanel {
                        VStack(alignment: .leading, spacing: 8) {
                            Moto.eyebrow("2 · Vyhledat cíl")

                            TextField("Zadej město, ulici...", text: $hledaniText)
                                .font(.system(size: 16, design: .rounded))
                                .foregroundColor(Moto.textHlavni)
                                .padding(10)
                                .background(Moto.asfalt)
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
                                                    .foregroundColor(Moto.textHlavni)
                                                if !navrh.subtitle.isEmpty {
                                                    Text(navrh.subtitle)
                                                        .font(.system(size: 12, design: .rounded))
                                                        .foregroundColor(Moto.textTlumeny)
                                                }
                                            }
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        if navrh != hledac.navrhy.prefix(5).last {
                                            Divider().background(Moto.panelHranice)
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
                                        .foregroundColor(Moto.textTlumeny)
                                }
                            }
                        }
                    }

                    MotoPanel {
                        VStack(alignment: .leading, spacing: 8) {
                            Moto.eyebrow("Mapa")
                            MapaView(cil: cilSouradnice, trasa: trasaBody)
                                .frame(height: 260)
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Moto.panelHranice, lineWidth: 1))
                        }
                    }

                    VStack(spacing: 10) {
                        MotoTlacitko(titulek: "Povolit polohu", barva: Moto.textTlumeny) {
                            navi.pozadejOOpravneni()
                        }
                        MotoTlacitko(titulek: "1 · Připojit ESP32", barva: Moto.jantar) {
                            navi.pripojitESP32()
                        }
                        MotoTlacitko(
                            titulek: navi.aktivni ? "Zastavit navigaci" : "3 · Spustit navigaci",
                            barva: navi.aktivni ? Moto.redline : Moto.signal,
                            action: {
                                if navi.aktivni {
                                    navi.zastavitNavigaci()
                                } else if let cil = cilSouradnice {
                                    navi.nastavCil(lat: cil.latitude, lon: cil.longitude)
                                    navi.spustitNavigaci()
                                }
                            },
                            vypnuto: cilSouradnice == nil && !navi.aktivni
                        )
                    }

                    MotoPanel {
                        VStack(alignment: .leading, spacing: 6) {
                            Moto.eyebrow("Odesláno přes BLE")
                            Text(navi.poslednaZprava)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(Moto.textTlumeny)
                        }
                    }
                }
                .padding(16)
            }
        }
        .onAppear {
            navi.pozadejOOpravneni()
        }
    }

    private func vyberNavrh(_ navrh: MKLocalSearchCompletion) {
        hledac.vyhledejSouradnice(pro: navrh) { souradnice, nazev in
            guard let souradnice = souradnice else { return }
            hledaniText = nazev
            cilNazev = nazev
            zobrazNavrhy = false
            cilSouradnice = souradnice

            if let start = navi.aktualniPoloha {
                spocitejTrasuNaMape(z: start, do: souradnice) { body in
                    trasaBody = body
                }
            }
        }
    }
}

struct StavIndikator: View {
    let stav: String

    var barva: Color {
        switch stav {
        case "SPOJENO": return Moto.signal
        case "Odpojeno": return Moto.textTlumeny
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
        .background(Moto.panel)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Moto.panelHranice, lineWidth: 1))
        .cornerRadius(20)
    }
}

@main
struct BeelineNaviApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
