import SwiftUI
import CoreLocation
import CoreBluetooth

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
        guard let poloha = locations.last, cilNastaven else { return }
        vyhodnotPozici(poloha: poloha)
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

// MARK: - UI
struct ContentView: View {
    @StateObject private var navi = NaviManager()
    @State private var latText: String = ""
    @State private var lonText: String = ""

    var body: some View {
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

            TextField("Cilova sirka (lat)", text: $latText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            TextField("Cilova delka (lon)", text: $lonText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)

            Button(navi.aktivni ? "Zastavit navigaci" : "2. Spustit navigaci") {
                if navi.aktivni {
                    navi.zastavitNavigaci()
                } else {
                    if let lat = Double(latText), let lon = Double(lonText) {
                        navi.nastavCil(lat: lat, lon: lon)
                        navi.spustitNavigaci()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(navi.aktivni ? .red : .green)

            Divider()

            Text("Posledni odeslana data:")
                .font(.caption)
                .foregroundColor(.gray)
            Text(navi.poslednaZprava)
                .font(.system(.body, design: .monospaced))
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)

            Spacer()
        }
        .padding()
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
