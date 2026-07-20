import SwiftUI
import CoreLocation
import CoreBluetooth
import MapKit

// MARK: - UUID musi presne sedet s ESP32 kodem (BeelinePrototyp_ESP32S3.ino)
let SERVICE_UUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
let CHARACTERISTIC_UUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")

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
        // Pro zobrazeni modre tecky na mape staci "when in use", vyzadame hned na startu
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
        // Zkusit znovu najit a pripojit
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

    // --- Vypocet a odeslani ---
    private func vyhodnotPozici(poloha: CLLocation) {
        let myLat = poloha.coordinate.latitude
        let myLon = poloha.coordinate.longitude

        let vzdalenost = spoctiVzdalenost(lat1: myLat, lon1: myLon, lat2: cilLat, lon2: cilLon)
        let azimut = spoctiAzimut(lat1: myLat, lon1: myLon, lat2: cilLat, lon2: cilLon)

        let vzdText = vzdalenost > 1000 ? String(format: "%.1f km", vzdalenost / 1000) : "\(Int(vzdalenost)) m"
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let hodiny = formatter.string(from: Date())

        // Stejny format jako webova appka: uhel,cas,flag,HH:MM,vzdalenost,pokyn
        let zprava = "\(Int(azimut)),---,0,\(hodiny),\(vzdText),Jed k cili"

        DispatchQueue.main.async {
            self.poslednaZprava = zprava
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

// MARK: - Vypocet trasy pro vykresleni na mape (MKDirections)
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

// MARK: - Mapa (UIViewRepresentable, obaluje nativni MKMapView)
struct MapaView: UIViewRepresentable {
    var cil: CLLocationCoordinate2D?
    var trasa: [CLLocationCoordinate2D]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = true
        mapView.delegate = context.coordinator
        mapView.userTrackingMode = .follow
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
                renderer.strokeColor = .systemBlue
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
    @State private var trasaBody: [CLLocationCoordinate2D] = []
    @State private var zobrazNavrhy = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Beeline Navi (nativni)")
                    .font(.title2).bold()

                Text("Stav: \(navi.stavPripojeni)")
                    .foregroundColor(navi.stavPripojeni == "SPOJENO" ? .green : .orange)

                Button("Pozadat o opravneni polohy") {
                    navi.pozadejOOpravneni()
                }
                .buttonStyle(.bordered)

                Button("1. Pripojit ESP32") {
                    navi.pripojitESP32()
                }
                .buttonStyle(.borderedProminent)

                // --- Vyhledavani adresy s naseptavacem ---
                VStack(alignment: .leading, spacing: 0) {
                    TextField("Zadej město, ulici...", text: $hledaniText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: hledaniText) { novyText in
                            hledac.hledej(novyText)
                            zobrazNavrhy = !novyText.isEmpty
                        }

                    if zobrazNavrhy && !hledac.navrhy.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(hledac.navrhy.prefix(5), id: \.self) { navrh in
                                Button {
                                    vyberNavrh(navrh)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(navrh.title).foregroundColor(.primary)
                                        if !navrh.subtitle.isEmpty {
                                            Text(navrh.subtitle).font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Divider()
                            }
                        }
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                }

                // --- Mapa ---
                MapaView(cil: cilSouradnice, trasa: trasaBody)
                    .frame(height: 320)
                    .cornerRadius(12)

                Button(navi.aktivni ? "Zastavit navigaci" : "2. Spustit navigaci") {
                    if navi.aktivni {
                        navi.zastavitNavigaci()
                    } else if let cil = cilSouradnice {
                        navi.nastavCil(lat: cil.latitude, lon: cil.longitude)
                        navi.spustitNavigaci()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(navi.aktivni ? .red : .green)
                .disabled(cilSouradnice == nil && !navi.aktivni)

                Divider()

                Text("Posledni odeslana data:")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(navi.poslednaZprava)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding()
        }
        .onAppear {
            navi.pozadejOOpravneni()
        }
    }

    private func vyberNavrh(_ navrh: MKLocalSearchCompletion) {
        hledac.vyhledejSouradnice(pro: navrh) { souradnice, nazev in
            guard let souradnice = souradnice else { return }
            hledaniText = nazev
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

@main
struct BeelineNaviApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
