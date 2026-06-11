import 'dart:io';
import 'package:usb_serial/usb_serial.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';
import 'ble_menu_screen.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BezpecnyChatApp());
}

class BezpecnyChatApp extends StatelessWidget {
  const BezpecnyChatApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: const ObravovkaKontaktov(),
    );
  }
}

// ============ LOGGER ============
final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 3,
    lineLength: 50,
    colors: true,
    printEmojis: true,
  ),
);

// ============ HARDWARE CONFIG ============
class HardwareConfig {
  static const String DEVICE_NAME = "XIAO-S3";
  static const String DEVICE_MODEL = "ESP32S3";
  static const String LORA_CHIP = "SX1262";
  static const int BAUD_RATE = 115200;
  static const String USB_MANUFACTURER = "Seeed";
}

// ============ ŠIFROVACIA SLUŽBA ============
class SifrovaciaSluzba {
  static const String _defaultKluc = "tajnyKlucPre256bitovuSifruAES!?!";

  static String sifrovajAES(String text, [String? kluc]) {
    try {
      final key = encrypt.Key.fromUtf8(kluc ?? _defaultKluc);
      final iv = encrypt.IV.fromSecureRandom(16);
      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );

      final encrypted = encrypter.encrypt(text, iv: iv);
      final kombinovane = iv.base64 + ':' + encrypted.base64;
      return base64Encode(utf8.encode(kombinovane));
    } catch (e) {
      logger.e("Chyba pri šifrovaní: $e");
      return "CHYBA_SIFRVANIA: $e";
    }
  }

  static String desifrovajAES(String sifrovanyText, [String? kluc]) {
    try {
      final dekodovane = utf8.decode(base64Decode(sifrovanyText));
      final casti = dekodovane.split(':');
      if (casti.length != 2) return "CHYBA_DESIFRVANIA";

      final iv = encrypt.IV.fromBase64(casti[0]);
      final encrypted = encrypt.Encrypted.fromBase64(casti[1]);
      final key = encrypt.Key.fromUtf8(kluc ?? _defaultKluc);
      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );
      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      logger.e("Chyba pri dešifrovaní: $e");
      return "CHYBA_DESIFRVANIA: $e";
    }
  }

  static String generujHash(String text) {
    int hash = 0;
    for (int i = 0; i < text.length; i++) {
      hash = ((hash << 5) - hash) + text.codeUnitAt(i);
      hash = hash & hash;
    }
    return hash.abs().toRadixString(16);
  }
}

// ============ SPRÁVA - ZÁZNAM ============
class SpravaZaznam {
  final String id;
  final String sifrovanyObsah;
  final String sifrovanaPoloha;
  final String typ;
  final String smer;
  final int casovy_razitko;
  final String hash;
  final String? kontakt;
  double? lat;
  double? lon;
  int? rssi;
  int? snr;
  int? channelRssi;

  SpravaZaznam({
    required this.id,
    required this.sifrovanyObsah,
    required this.sifrovanaPoloha,
    required this.typ,
    required this.smer,
    required this.casovy_razitko,
    required this.hash,
    this.kontakt,
    this.lat,
    this.lon,
    this.rssi,
    this.snr,
    this.channelRssi,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'obsah': sifrovanyObsah,
        'poloha': sifrovanaPoloha,
        'typ': typ,
        'smer': smer,
        'cas': casovy_razitko,
        'hash': hash,
        'kontakt': kontakt,
        'lat': lat,
        'lon': lon,
        'rssi': rssi,
        'snr': snr,
        'channelRssi': channelRssi,
      };

  static SpravaZaznam fromJson(Map<String, dynamic> json) {
    return SpravaZaznam(
      id: json['id'],
      sifrovanyObsah: json['obsah'],
      sifrovanaPoloha: json['poloha'],
      typ: json['typ'],
      smer: json['smer'],
      casovy_razitko: json['cas'],
      hash: json['hash'],
      kontakt: json['kontakt'],
      lat: json['lat'],
      lon: json['lon'],
      rssi: json['rssi'],
      snr: json['snr'],
      channelRssi: json['channelRssi'],
    );
  }
}

// ============ POLOHA BODU NA MAPE ============
class PolohaBodu {
  final String nazov;
  final double lat;
  final double lon;
  final int casovy_razitko;
  final String typ;
  final Color farba;
  final String? meno;
  final int? rssi;

  PolohaBodu({
    required this.nazov,
    required this.lat,
    required this.lon,
    required this.casovy_razitko,
    required this.typ,
    required this.farba,
    this.meno,
    this.rssi,
  });
}

// ============ HISTÓRIA KONTAKTOV ============
class HistoriaKontaktov {
  static final Map<String, Map<String, List<dynamic>>> _historiaMap = {};

  static List<SpravaZaznam> getSifrovanaHistoria(String kontakt) {
    _historiaMap.putIfAbsent(
      kontakt,
      () => {
        'sifrovana': <SpravaZaznam>[],
        'zobrazovane': <Map<String, dynamic>>[],
      },
    );
    return List<SpravaZaznam>.from(
      _historiaMap[kontakt]!['sifrovana'] as List<SpravaZaznam>,
    );
  }

  static List<Map<String, dynamic>> getZobrazovaneSpravy(String kontakt) {
    _historiaMap.putIfAbsent(
      kontakt,
      () => {
        'sifrovana': <SpravaZaznam>[],
        'zobrazovane': <Map<String, dynamic>>[],
      },
    );
    return List<Map<String, dynamic>>.from(
      _historiaMap[kontakt]!['zobrazovane'] as List<Map<String, dynamic>>,
    );
  }

  static void addSifrovanaSprava(String kontakt, SpravaZaznam sprava) {
    _historiaMap.putIfAbsent(
      kontakt,
      () => {
        'sifrovana': <SpravaZaznam>[],
        'zobrazovane': <Map<String, dynamic>>[],
      },
    );
    (_historiaMap[kontakt]!['sifrovana'] as List<SpravaZaznam>).add(sprava);
  }

  static void addZobrazovanaSprava(
    String kontakt,
    Map<String, dynamic> sprava,
  ) {
    _historiaMap.putIfAbsent(
      kontakt,
      () => {
        'sifrovana': <SpravaZaznam>[],
        'zobrazovane': <Map<String, dynamic>>[],
      },
    );
    (_historiaMap[kontakt]!['zobrazovane'] as List<Map<String, dynamic>>).add(
      sprava,
    );
  }

  static void clearSifrovanaHistoria(String kontakt) {
    if (_historiaMap.containsKey(kontakt)) {
      (_historiaMap[kontakt]!['sifrovana'] as List<SpravaZaznam>).clear();
    }
  }

  static void clearZobrazovaneSpravy(String kontakt) {
    if (_historiaMap.containsKey(kontakt)) {
      (_historiaMap[kontakt]!['zobrazovane'] as List<Map<String, dynamic>>)
          .clear();
    }
  }

  static void removeWhereFromSifrovana(
    String kontakt,
    bool Function(SpravaZaznam) test,
  ) {
    if (_historiaMap.containsKey(kontakt)) {
      (_historiaMap[kontakt]!['sifrovana'] as List<SpravaZaznam>).removeWhere(
        test,
      );
    }
  }

  static void removeWhereFromZobrazovane(
    String kontakt,
    bool Function(Map<String, dynamic>) test,
  ) {
    if (_historiaMap.containsKey(kontakt)) {
      (_historiaMap[kontakt]!['zobrazovane'] as List<Map<String, dynamic>>)
          .removeWhere(test);
    }
  }
}

// ============ MESH NODE ============
class MeshNode {
  final int nodeNum;
  final String longName;
  final String shortName;
  final bool hasPositionData;
  final double latitude;
  final double longitude;
  DateTime? lastHeard;
  final int rssi;
  final double snr;

  MeshNode({
    required this.nodeNum,
    required this.longName,
    required this.shortName,
    required this.hasPositionData,
    required this.latitude,
    required this.longitude,
    required this.lastHeard,
    required this.rssi,
    required this.snr,
  });

  bool get isOnline {
    if (lastHeard == null) return false;
    final diff = DateTime.now().difference(lastHeard!);
    return diff.inMinutes < 30;
  }
}

// ============ USB SÉRIOVÁ KOMUNIKÁCIA ============
class USBSerialConnection {
  UsbPort? _port;
  bool _isConnected = false;
  Timer? _readTimer;
  Function(String)? onStatusChanged;
  Function(Uint8List)? onDataReceived;

  USBSerialConnection({this.onStatusChanged, this.onDataReceived});

  bool get isConnected => _isConnected;

  Future<bool> connectUSB() async {
    try {
      logger.i("Hľadám hardvér...");

      if (Platform.isAndroid) {
        logger.i("Spúšťam USB pripojenie pre Android...");
        onStatusChanged?.call("Android USB pripojenie");
        return false;
      }

      // Pripojíme sa cez usb_serial
      List<UsbDevice> devices = await UsbSerial.listDevices();
      if (devices.isEmpty) {
        onStatusChanged?.call("Nenašlo sa žiadne USB zariadenie");
        return false;
      }

      UsbDevice device = devices.first;
      _port = await device.create();

      if (_port == null || !await _port!.open()) {
        onStatusChanged?.call("Nie je možné otvoriť USB port");
        logger.e("Chyba: Nie je možné otvoriť port");
        return false;
      }

      try {
        await _port!.setPortParameters(115200, UsbPort.DATABITS_8,
            UsbPort.PARITY_NONE, UsbPort.STOPBITS_1);
        // usb_serial má bity, stopbity a paritu nastavené na 8-1-none automaticky
      } catch (e) {
        logger.e("Chyba konfigurácie: $e");
      }

      _isConnected = true;

      // Zachováme tvoje pôvodné čítanie, akurát ho prispôsobíme novej knižnici
      _port!.inputStream?.listen((Uint8List data) {
        onDataReceived?.call(data);
      });

      onStatusChanged?.call("USB pripojený: ${device.productName}");
      return true;
    } catch (e) {
      logger.e("Chyba pri pripájaní USB: $e");
      onStatusChanged?.call("Chyba USB: $e");
      return false;
    }
  }

  /*void _startReading() {
    if (_port == null) return;
    _readTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      try {
        if (_port == null || !_isConnected) return;
        final available = _port!.bytesAvailable;
        if (available > 0) {
          final data = _port!.read(available);
          onDataReceived?.call(data);
        }
        if (available < 0) {
          logger.w("Port vrátil chybu, hardvér bol pravdepodobne odpojený.");
          disconnect();
          return;
        }
      } catch (e) {
        logger.e("Chyba pri čítaní: $e");
        disconnect();
      }
    });
  }*/

  Future<void> sendData(Uint8List data) async {
    try {
      if (_port == null || !_isConnected) {
        logger.w("Žiadne pripojenie na posielanie");
        return;
      }
      _port!.write(data);
      logger.d("USB Data poslané: ${String.fromCharCodes(data)}");
    } catch (e) {
      logger.e("Chyba pri posielaní: $e");
    }
  }

  Future<void> disconnect() async {
    try {
      _readTimer?.cancel();
      _readTimer = null;
      if (_port != null) {
        _port!.close();
        _port = null;
      }
      _isConnected = false;
      onStatusChanged?.call("USB odpojené");
      logger.i("Odpojené");
    } catch (e) {
      logger.e("Chyba pri odpojení: $e");
    }
  }
}

// ============ MESHTASTIC SLUŽBA - HARDVÉR ============
class MeshtasticSluzba {
  static final MeshtasticSluzba _instance = MeshtasticSluzba._internal();

  late StreamController<String> _connectionController;
  late StreamController<List<MeshNode>> _nodesController;
  late StreamController<dynamic> _messageController;
  late USBSerialConnection _usbConnection;

  Function(String)? onConnectionChanged;
  Function(List<MeshNode>)? onNodesUpdated;
  Function(dynamic)? onMessageReceived;

  List<MeshNode> _nodes = [];
  MeshNode? _myNode;
  bool _isInitialized = false;
  Timer? _syncTimer;

  factory MeshtasticSluzba() {
    return _instance;
  }

  MeshtasticSluzba._internal() {
    _connectionController = StreamController<String>();
    _nodesController = StreamController<List<MeshNode>>();
    _messageController = StreamController<dynamic>();
    _usbConnection = USBSerialConnection();
    _setupUSBConnection();
  }

  void _setupUSBConnection() {
    _usbConnection.onStatusChanged = (status) {
      onConnectionChanged?.call(status);
      logger.i("USB Status: $status");
    };

    _usbConnection.onDataReceived = (data) {
      _processReceivedData(data);
    };
  }

  void _processReceivedData(List<int> data) {
    try {
      String receivedStr = String.fromCharCodes(data);
      logger.d("Meshtastic prijatá správa: $receivedStr");
      onMessageReceived?.call(receivedStr);
    } catch (e) {
      logger.e("Chyba pri spracovaní Meshtastic dát: $e");
    }
  }

  void initialize() {
    // Prvý pokus hneď pri štarte aplikácie
    _skusAutomatickePripojenie();

    // Každých 5 sekúnd skontroluje stav. Ak sme odpojení, skúsi reconnect.
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!_usbConnection.isConnected) {
        _skusAutomatickePripojenie();
      }
    });
  }

  void _skusAutomatickePripojenie() async {
    bool usbConnected = await _usbConnection.connectUSB();
    if (!usbConnected) {
      onConnectionChanged?.call("Meshtastic hardvér nedostupný");
      logger.w("USB nie je dostupné");
      _isInitialized = false;
      return;
    }

    _isInitialized = true;
    onConnectionChanged?.call("Pripojené: XIAO-S3");
    _initMyNode();

    // Odošleme prázdny zoznam uzlov, aby sa UI prebudilo
    _initNetworkNodes();
    onNodesUpdated?.call(_nodes);
  }

  void _initMyNode() {
    _myNode = MeshNode(
      nodeNum: 1000,
      longName: HardwareConfig.DEVICE_NAME,
      shortName: "XS3",
      hasPositionData: true,
      latitude: 48.8566,
      longitude: 2.3522,
      lastHeard: DateTime.now(),
      rssi: -95,
      snr: 8.5,
    );
    logger.i("Môj Meshtastic uzol: ${_myNode?.longName}");
  }

  void _initNetworkNodes() {
    _nodes = [
      MeshNode(
        nodeNum: 1001,
        longName: "Kamarát 1 (ALFA)",
        shortName: "ALFA",
        hasPositionData: true,
        latitude: 48.8944,
        longitude: 2.3912,
        lastHeard: DateTime.now(),
        rssi: -108,
        snr: 5.0,
      ),
      MeshNode(
        nodeNum: 1002,
        longName: "Kamarát 2 (BETA)",
        shortName: "BETA",
        hasPositionData: true,
        latitude: 48.8700,
        longitude: 2.3550,
        lastHeard: DateTime.now().subtract(const Duration(minutes: 45)),
        rssi: -120,
        snr: 0.0,
      ),
    ];
    logger.i("Sieť inicializovaná: ${_nodes.length} uzlov");
  }

  void _startNodeSync() {
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isInitialized) {
        for (var node in _nodes) {
          if (node.lastHeard != null) {
            final random = Random();
            if (random.nextBool()) {
              node.lastHeard = DateTime.now();
            }
          }
        }
        onNodesUpdated?.call(_nodes);
        logger.d("Meshtastic uzly synchronizované");
      }
    });
  }

  Future<void> sendMessage(String text, int toAddress) async {
    try {
      logger.i("Posielam správu cez Meshtastic na $toAddress: $text");

      // Formát Meshtastic správy
      String message = "!${toAddress.toRadixString(16)}^$text";
      Uint8List data = Uint8List.fromList(utf8.encode(message));

      await _usbConnection.sendData(data);
      logger.i("Meshtastic správa odoslaná");
    } catch (e) {
      logger.e("Chyba pri odosielaní Meshtastic správy: $e");
    }
  }

  Future<void> sendPosition(
    double latitude,
    double longitude,
    int toAddress,
  ) async {
    try {
      logger.i(
          "Posielam GPS pozíciu cez Meshtastic: $latitude, $longitude na $toAddress");

      // Format pre Meshtastic pozíciu
      String positionData =
          "!${toAddress.toRadixString(16)}&${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}";
      Uint8List data = Uint8List.fromList(utf8.encode(positionData));

      await _usbConnection.sendData(data);
      logger.i("GPS pozícia odoslaná cez Meshtastic");
    } catch (e) {
      logger.e("Chyba pri odosielaní GPS cez Meshtastic: $e");
    }
  }

  List<MeshNode> getNodes() => _nodes;
  MeshNode? getMyNode() => _myNode;
  bool get isInitialized => _isInitialized;

  void dispose() {
    _syncTimer?.cancel();
    _connectionController.close();
    _nodesController.close();
    _messageController.close();
    _usbConnection.disconnect();
    logger.i("Meshtastic služba ukončená");
  }
}

// ============ SLUŽBA POLOHY ============
class SluzbaPolohy {
  static Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await _requestLocationPermission();
      if (!hasPermission) return null;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      logger.i("Poloha: ${position.latitude}, ${position.longitude}");
      return position;
    } catch (e) {
      logger.e("Chyba pri získavaní polohy: $e");
      return null;
    }
  }

  static Future<bool> _requestLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final result = await Geolocator.requestPermission();
      return result == LocationPermission.whileInUse ||
          result == LocationPermission.always;
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const p = 0.017453292519943295;
    final c = cos;
    final a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }
}

// ============ OBRAZOVKA - HLAVNÁ ============
class ObravovkaKontaktov extends StatefulWidget {
  const ObravovkaKontaktov({super.key});
  @override
  State<ObravovkaKontaktov> createState() => _ObravovkaKontaktovState();
}

class _ObravovkaKontaktovState extends State<ObravovkaKontaktov> {
  late MeshtasticSluzba meshService;
  String _mojaPrezyvka = HardwareConfig.DEVICE_NAME;
  String _connectionStatus = "Inicializácia...";
  String _bleConnectionStatus = 'Bluetooth: Nepripojené';
  List<MeshNode> _uzly = [];
  static List<Map<String, dynamic>> vystrahyVlny = [];

  @override
  void initState() {
    super.initState();
    _initializeMeshtastic();
    //_initDemoVystrahy();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _spustiBluetoothOdposluch();
    });
  }

  void _spustiBluetoothOdposluch() async {
    try {
      // Overíme, či zariadenie vôbec podporuje Bluetooth
      if (!await FlutterBluePlus.isSupported) {
        debugPrint("Bluetooth nie je na tomto zariadení podporované");
        return;
      }

      // Sledujeme zmeny stavu Bluetooth adaptéra (zapnutý/vypnutý/pripájanie)
      FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
        if (state == BluetoothAdapterState.on) {
          if (mounted) {
            setState(() {
              _bleConnectionStatus = 'Bluetooth: Zapnuté / Pripravené';
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _bleConnectionStatus = 'Bluetooth: Nepripojené / Vypnuté';
            });
          }
        }
      });
    } catch (e) {
      debugPrint("Bluetooth error: $e");
    }
  }

  void _initializeMeshtastic() async {
    meshService = MeshtasticSluzba();
    meshService.onConnectionChanged = (status) {
      if (mounted) {
        setState(() => _connectionStatus = status);
        logger.i("Stav: $status");
      }
    };
    meshService.onNodesUpdated = (nodes) {
      if (mounted) {
        setState(() => _uzly = nodes);
        logger.d("Uzly aktualizované: ${nodes.length}");
      }
    };
    meshService.initialize();
  }

  //void _initDemoVystrahy() {
  //if (vystrahyVlny.isEmpty) {
  //vystrahyVlny = [
  //{"vzdialenost": 5.5, "citatelny": true, "obsah": "Signal z Blizko"},
  //{"vzdialenost": 25.3, "citatelny": false, "obsah": ""},
  //{"vzdialenost": 85.7, "citatelny": false, "obsah": ""},
  //{"vzdialenost": 12.1, "citatelny": true, "obsah": "Neznama frekvencia"},
  //];
  //}
  //}

  List<PolohaBodu> _getMapoveBody() {
    List<PolohaBodu> body = [];

    final myNode = meshService.getMyNode();
    if (myNode != null) {
      body.add(
        PolohaBodu(
          nazov: myNode.longName,
          lat: myNode.latitude,
          lon: myNode.longitude,
          casovy_razitko: DateTime.now().millisecondsSinceEpoch,
          typ: "moj_uzol",
          farba: Colors.cyanAccent,
          meno: myNode.longName,
          rssi: myNode.rssi,
        ),
      );
    }

    for (var node in _uzly) {
      Color farba = node.isOnline
          ? (node.rssi.abs() <= 100 ? Colors.greenAccent : Colors.yellowAccent)
          : Colors.redAccent;

      body.add(
        PolohaBodu(
          nazov: node.longName,
          lat: node.latitude,
          lon: node.longitude,
          casovy_razitko: node.lastHeard?.millisecondsSinceEpoch ??
              DateTime.now().millisecondsSinceEpoch,
          typ: "kontakt",
          farba: farba,
          meno: node.longName,
          rssi: node.rssi,
        ),
      );
    }

    return body;
  }

  String _formatujCas(int timestamp) {
    DateTime cas = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return "${cas.day}.${cas.month}.${cas.year} ${cas.hour}:${cas.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📡 Radiovi Kamarati - Meshtastic'),
        backgroundColor: Colors.blueGrey,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.black26,
            child: Row(
              children: [
                const Icon(Icons.radio, color: Colors.greenAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tvoj volací znak: $_mojaPrezyvka',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Stav: $_connectionStatus',
                        style: TextStyle(
                          fontSize: 12,
                          color: _connectionStatus.contains('Pripojené')
                              ? Colors.greenAccent
                              : Colors.redAccent,
                        ),
                      ),
                      Text(
                        _bleConnectionStatus,
                        style: TextStyle(
                          fontSize: 12,
                          color: _bleConnectionStatus.contains('Pripojené')
                              ? Colors.greenAccent
                              : Colors.redAccent,
                        ),
                      ),
                    ],
                  ), // Column
                ), // Expanded
                IconButton(
                  icon: Icon(Icons.bluetooth,
                      color: _bleConnectionStatus.contains('Pripojené')
                          ? Colors.greenAccent
                          : Colors.blueAccent),
                  tooltip: 'Spárovať Bluetooth',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BleMenuScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                // MAPA
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.amber,
                    child: Icon(Icons.map, color: Colors.black),
                  ),
                  title: const Text('MAP - Mapy'),
                  subtitle: const Text('Polohy kontaktov a výstrahy'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MapovyScreen(
                        body: _getMapoveBody(),
                        formatCas: _formatujCas,
                      ),
                    ),
                  ),
                ),
                const Divider(),

                // VÝSTRAHY
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.red,
                    child: Icon(Icons.warning, color: Colors.white),
                  ),
                  title: const Text('VYSTRAHA'),
                  subtitle: Text('Nezname pakety (${vystrahyVlny.length})'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ObrazovkaVystrah(vystrahy: vystrahyVlny),
                    ),
                  ),
                ),
                const Divider(),

                // KONTAKTY
                ..._uzly.map(
                  (node) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          node.isOnline ? Colors.greenAccent : Colors.redAccent,
                      child: const Icon(Icons.person),
                    ),
                    title: Text(node.longName),
                    subtitle: Text(
                      '${node.isOnline ? "Online" : "Offline"} • RSSI: ${node.rssi} • SNR: ${node.snr.toStringAsFixed(1)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ObrazovkaCatu(
                          menoKamaranda: node.longName,
                          meshService: meshService,
                          nodeNum: node.nodeNum,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    meshService.dispose();
    super.dispose();
  }
}

// ============ OBRAZOVKA - MAPA ============
class MapovyScreen extends StatelessWidget {
  final List<PolohaBodu> body;
  final Function(int) formatCas;

  const MapovyScreen({super.key, required this.body, required this.formatCas});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Mapa - Polohy a Vystrahy'),
        backgroundColor: Colors.amber,
      ),
      body: body.isEmpty
          ? const Center(child: Text('Žiadne polohy na mape'))
          : Column(
              children: [
                Expanded(
                  child: Container(
                    color: Colors.grey[800],
                    child: Stack(
                      children: [
                        // Pozadie mapy
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.map,
                                size: 80,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Offline mapa - Pariz',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Body na mape
                        ...body.map((bod) {
                          double x = ((bod.lon - 2.25) / 0.45) * 100;
                          double y = ((bod.lat - 48.75) / 0.25) * 100;
                          x = x.clamp(5, 95);
                          y = y.clamp(5, 95);

                          return Positioned(
                            left: (x / 100) * MediaQuery.of(context).size.width,
                            top: (y / 100) *
                                (MediaQuery.of(context).size.height - 200),
                            child: Column(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: bod.farba,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: bod.farba.withOpacity(0.5),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: bod.typ == "moj_uzol"
                                        ? const Icon(
                                            Icons.home,
                                            size: 20,
                                            color: Colors.black,
                                          )
                                        : (bod.typ == "kontakt"
                                            ? const Icon(
                                                Icons.person,
                                                size: 20,
                                                color: Colors.white,
                                              )
                                            : const Icon(
                                                Icons.warning,
                                                size: 20,
                                                color: Colors.black,
                                              )),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        bod.meno ?? bod.nazov,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (bod.rssi != null)
                                        Text(
                                          'RSSI: ${bod.rssi}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 8,
                                          ),
                                        ),
                                      Text(
                                        formatCas(bod.casovy_razitko),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 8,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ),
                // Legenda
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.black26,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Legenda:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.cyanAccent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Môj uzol',
                            style: TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 24),
                          Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blueAccent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Kontakty',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.greenAccent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Online - Dobrý signál',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.yellowAccent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Online - Slabý signál',
                            style: TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 20),
                          Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.redAccent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('Offline', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ============ OBRAZOVKA - VÝSTRAHY ============
class ObrazovkaVystrah extends StatelessWidget {
  final List<Map<String, dynamic>> vystrahy;

  const ObrazovkaVystrah({super.key, required this.vystrahy});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Radar: Neznamé signály'),
        backgroundColor: const Color(0xFFB71C1C),
      ),
      body: vystrahy.isEmpty
          ? const Center(child: Text('V éteru je pokoj.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: vystrahy.length,
              itemBuilder: (context, index) {
                final v = vystrahy[index];
                double dist = v["vzdialenost"];
                bool cit = v["citatelny"];
                Color farba = dist <= 15
                    ? Colors.redAccent
                    : (dist <= 50 ? Colors.orangeAccent : Colors.greenAccent);

                return Card(
                  color: Colors.black38,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Výstraha ${index + 1}'),
                            Text(
                              '${dist.toStringAsFixed(2)} km',
                              style: TextStyle(
                                color: farba,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          cit ? 'Obsah: "${v["obsah"]}"' : 'Paket je šifrovaný',
                          style: TextStyle(color: farba),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ============ OBRAZOVKA - CHAT ============
class ObrazovkaCatu extends StatefulWidget {
  final String menoKamaranda;
  final MeshtasticSluzba meshService;
  final int nodeNum;

  const ObrazovkaCatu({
    super.key,
    required this.menoKamaranda,
    required this.meshService,
    required this.nodeNum,
  });

  @override
  State<ObrazovkaCatu> createState() => _ObrazovkaCatuState();
}

class _ObrazovkaCatuState extends State<ObrazovkaCatu> {
  final TextEditingController _messageController = TextEditingController();
  List<Map<String, dynamic>> _zobrazovaneSpravy = [];
  String _vzdialenostVListe = "Poloha neznama";
  double? _mojaLat;
  double? _mojaLon;
  double? _kamarandLat;
  double? _kamarandLon;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _initLocation();
  }

  void _loadHistory() {
    _zobrazovaneSpravy = HistoriaKontaktov.getZobrazovaneSpravy(
      widget.menoKamaranda,
    );
  }

  void _initLocation() async {
    final position = await SluzbaPolohy.getCurrentPosition();
    if (position != null && mounted) {
      setState(() {
        _mojaLat = position.latitude;
        _mojaLon = position.longitude;
      });
    }
  }

  String _generujID() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  String _formatujCas(int timestamp) {
    DateTime cas = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return "${cas.day}.${cas.month}.${cas.year} ${cas.hour}:${cas.minute.toString().padLeft(2, '0')}";
  }

  void _odoslatPolohu() async {
    try {
      final position = await SluzbaPolohy.getCurrentPosition();
      if (position == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nie je možné získať polohu'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      String polohaText = "GPS:${position.latitude},${position.longitude}";
      String sifrovanaPoloha = SifrovaciaSluzba.sifrovajAES(polohaText);
      String hash = SifrovaciaSluzba.generujHash(polohaText);
      int casNow = DateTime.now().millisecondsSinceEpoch;

      SpravaZaznam zaznam = SpravaZaznam(
        id: _generujID(),
        sifrovanyObsah: SifrovaciaSluzba.sifrovajAES("Zdielam moju polohu"),
        sifrovanaPoloha: sifrovanaPoloha,
        typ: "poloha",
        smer: "odoslana",
        casovy_razitko: casNow,
        hash: hash,
        kontakt: widget.menoKamaranda,
        lat: position.latitude,
        lon: position.longitude,
      );

      setState(() {
        HistoriaKontaktov.addSifrovanaSprava(widget.menoKamaranda, zaznam);
        HistoriaKontaktov.addZobrazovanaSprava(widget.menoKamaranda, {
          "typ": "poloha",
          "smer": "odoslana",
          "obsah": "Zdielam moju polohu",
          "sifra": sifrovanaPoloha.substring(0, 30) + "...",
          "desifrovaneSifra": sifrovanaPoloha,
          "casovy_razitko": casNow,
          "lat": position.latitude,
          "lon": position.longitude,
        });
        _zobrazovaneSpravy = HistoriaKontaktov.getZobrazovaneSpravy(
          widget.menoKamaranda,
        );
        _mojaLat = position.latitude;
        _mojaLon = position.longitude;
      });

      // Poslanie cez Meshtastic
      await widget.meshService.sendPosition(
        position.latitude,
        position.longitude,
        widget.nodeNum,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Poloha odoslaná cez Meshtastic LoRa'),
          backgroundColor: Colors.greenAccent,
        ),
      );

      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _simulateLocationResponse();
        }
      });
    } catch (e) {
      logger.e("Chyba pri odosielaní polohy: $e");
    }
  }

  void _simulateLocationResponse() {
    if (_kamarandLat == null || _kamarandLon == null) {
      _kamarandLat = 48.8944;
      _kamarandLon = 2.3912;
    }

    if (_mojaLat != null && _mojaLon != null) {
      double vzdialenost = SluzbaPolohy.calculateDistance(
        _mojaLat!,
        _mojaLon!,
        _kamarandLat!,
        _kamarandLon!,
      );

      setState(() {
        _vzdialenostVListe = "${vzdialenost.toStringAsFixed(2)} km";
      });
    }

    int casKamarada = DateTime.now().millisecondsSinceEpoch;
    String kamaradPoloha = "GPS:$_kamarandLat,$_kamarandLon";
    String sifrovanaKamaradLokal = SifrovaciaSluzba.sifrovajAES(kamaradPoloha);
    String hashKamarad = SifrovaciaSluzba.generujHash(kamaradPoloha);

    SpravaZaznam zaznnamKamarad = SpravaZaznam(
      id: _generujID(),
      sifrovanyObsah: SifrovaciaSluzba.sifrovajAES("Kamarád poslal polohu"),
      sifrovanaPoloha: sifrovanaKamaradLokal,
      typ: "poloha",
      smer: "prijata",
      casovy_razitko: casKamarada,
      hash: hashKamarad,
      kontakt: widget.menoKamaranda,
      lat: _kamarandLat,
      lon: _kamarandLon,
    );

    setState(() {
      HistoriaKontaktov.addSifrovanaSprava(
        widget.menoKamaranda,
        zaznnamKamarad,
      );
      HistoriaKontaktov.addZobrazovanaSprava(widget.menoKamaranda, {
        "typ": "poloha",
        "smer": "prijata",
        "obsah": "Kamarád poslal polohu",
        "sifra": sifrovanaKamaradLokal.substring(0, 30) + "...",
        "desifrovaneSifra": sifrovanaKamaradLokal,
        "casovy_razitko": casKamarada,
        "lat": _kamarandLat,
        "lon": _kamarandLon,
      });
      _zobrazovaneSpravy = HistoriaKontaktov.getZobrazovaneSpravy(
        widget.menoKamaranda,
      );
    });
  }

  void _otvoritOfflineMapu(double lat, double lon, String kto) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Offline Mapa - $kto'),
        content: Container(
          width: 300,
          height: 200,
          color: Colors.grey,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.map, size: 48, color: Colors.greenAccent),
                const SizedBox(height: 10),
                const Text(
                  'Načítané offline dlaždice z disku',
                  style: TextStyle(color: Colors.black, fontSize: 12),
                ),
                Text(
                  "Lat: ${lat.toStringAsFixed(4)}, Lon: ${lon.toStringAsFixed(4)}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zatvoriť'),
          ),
        ],
      ),
    );
  }

  void _zobrazitMazanieHistorie() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vymaž História'),
        content: const Text('Vyber čo chceš vymazať:'),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                HistoriaKontaktov.clearSifrovanaHistoria(widget.menoKamaranda);
                HistoriaKontaktov.clearZobrazovaneSpravy(widget.menoKamaranda);
                _zobrazovaneSpravy = [];
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Celá história bola vymazaná'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            },
            child: const Text(
              'Vymaž Všetko',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
          TextButton(
            onPressed: () {
              int sedemDniMs = 7 * 24 * 60 * 60 * 1000;
              int casLimit = DateTime.now().millisecondsSinceEpoch - sedemDniMs;

              setState(() {
                HistoriaKontaktov.removeWhereFromSifrovana(
                  widget.menoKamaranda,
                  (z) => z.casovy_razitko > casLimit,
                );
                HistoriaKontaktov.removeWhereFromZobrazovane(
                  widget.menoKamaranda,
                  (z) =>
                      (z['casovy_razitko'] ??
                          DateTime.now().millisecondsSinceEpoch) >
                      casLimit,
                );
                _zobrazovaneSpravy = HistoriaKontaktov.getZobrazovaneSpravy(
                  widget.menoKamaranda,
                );
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Správy za posledných 7 dní boli vymazané'),
                  backgroundColor: Colors.orangeAccent,
                ),
              );
            },
            child: const Text(
              'Vymazať posledných 7 Dní',
              style: TextStyle(color: Colors.orangeAccent),
            ),
          ),
          TextButton(
            onPressed: () {
              int jedanDenMs = 24 * 60 * 60 * 1000;
              int casLimit = DateTime.now().millisecondsSinceEpoch - jedanDenMs;

              setState(() {
                HistoriaKontaktov.removeWhereFromSifrovana(
                  widget.menoKamaranda,
                  (z) => z.casovy_razitko > casLimit,
                );
                HistoriaKontaktov.removeWhereFromZobrazovane(
                  widget.menoKamaranda,
                  (z) =>
                      (z['casovy_razitko'] ??
                          DateTime.now().millisecondsSinceEpoch) >
                      casLimit,
                );
                _zobrazovaneSpravy = HistoriaKontaktov.getZobrazovaneSpravy(
                  widget.menoKamaranda,
                );
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Správy za posledných 24 hodín boli vymazané'),
                  backgroundColor: Colors.amberAccent,
                ),
              );
            },
            child: const Text(
              'Vymazať posledných 24 Hodín',
              style: TextStyle(color: Colors.amberAccent),
            ),
          ),
          TextButton(
            onPressed: () {
              int jednaHodinaMs = 60 * 60 * 1000;
              int casLimit =
                  DateTime.now().millisecondsSinceEpoch - jednaHodinaMs;

              setState(() {
                HistoriaKontaktov.removeWhereFromSifrovana(
                  widget.menoKamaranda,
                  (z) => z.casovy_razitko > casLimit,
                );
                HistoriaKontaktov.removeWhereFromZobrazovane(
                  widget.menoKamaranda,
                  (z) =>
                      (z['casovy_razitko'] ??
                          DateTime.now().millisecondsSinceEpoch) >
                      casLimit,
                );
                _zobrazovaneSpravy = HistoriaKontaktov.getZobrazovaneSpravy(
                  widget.menoKamaranda,
                );
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Správy za poslednú 1 hodinu boli vymazané'),
                  backgroundColor: Colors.greenAccent,
                ),
              );
            },
            child: const Text(
              'Vymazať poslednú 1 Hodinu',
              style: TextStyle(color: Colors.greenAccent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zrušiť', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  void _zobrazitHistoriu() {
    final sifrovanaHistoria = HistoriaKontaktov.getSifrovanaHistoria(
      widget.menoKamaranda,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Šifrovaná História - AES-256'),
        content: SizedBox(
          width: 350,
          height: 400,
          child: sifrovanaHistoria.isEmpty
              ? const Center(child: Text('Žiadna história'))
              : ListView.builder(
                  itemCount: sifrovanaHistoria.length,
                  itemBuilder: (context, index) {
                    final zaznam = sifrovanaHistoria[index];
                    final desifrovany = SifrovaciaSluzba.desifrovajAES(
                      zaznam.sifrovanyObsah,
                    );
                    final desifrovanaPoloha = zaznam.sifrovanaPoloha.isNotEmpty
                        ? SifrovaciaSluzba.desifrovajAES(zaznam.sifrovanaPoloha)
                        : "";

                    return Card(
                      color: Colors.black38,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '[${zaznam.smer}] ${zaznam.typ}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.amberAccent,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Obsah: $desifrovany',
                              style: const TextStyle(fontSize: 11),
                            ),
                            if (zaznam.typ == "poloha" &&
                                desifrovanaPoloha.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Poloha: $desifrovanaPoloha',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.greenAccent,
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              'Hash: ${zaznam.hash.substring(0, min(16, zaznam.hash.length))}...',
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              'Čas: ${_formatujCas(zaznam.casovy_razitko)}',
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zatvoriť'),
          ),
        ],
      ),
    );
  }

  void _simulujCudziPaket(
    double lat,
    double lon,
    bool citatelny,
    String obsah,
  ) {
    double vzdialenost = _mojaLat != null && _mojaLon != null
        ? SluzbaPolohy.calculateDistance(_mojaLat!, _mojaLon!, lat, lon)
        : Random().nextDouble() * 100;

    setState(() {
      _zobrazovaneSpravy.add({
        "typ": "vystraha",
        "smer": "prijata",
        "obsah": citatelny ? obsah : "Šifrovaná výstraha",
        "vzdialenost": vzdialenost.toStringAsFixed(2),
        "citatelny": citatelny,
        "casovy_razitko": DateTime.now().millisecondsSinceEpoch,
      });
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Zachytený neznamý rádiový paket! (${vzdialenost.toStringAsFixed(1)} km)',
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Čet: ${widget.menoKamaranda}'),
            Text(
              'Vzdialenosť: $_vzdialenostVListe',
              style: const TextStyle(fontSize: 12, color: Colors.amberAccent),
            ),
          ],
        ),
        backgroundColor: Colors.blueGrey,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            onPressed: _zobrazitMazanieHistorie,
            tooltip: 'Vymaž históriu',
          ),
          IconButton(
            icon: const Icon(Icons.history, color: Colors.lightBlueAccent),
            onPressed: _zobrazitHistoriu,
            tooltip: 'Šifrovaná história',
          ),
          IconButton(
            icon: const Icon(Icons.radar, color: Colors.greenAccent),
            onPressed: () => _simulujCudziPaket(49.5000, 2.9000, false, ""),
            tooltip: 'Simulovať paket 1',
          ),
          IconButton(
            icon: const Icon(Icons.radar, color: Colors.orangeAccent),
            onPressed: () =>
                _simulujCudziPaket(48.9500, 2.4500, true, "Mystery Signal"),
            tooltip: 'Simulovať paket 2',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _zobrazovaneSpravy.isEmpty
                ? const Center(
                    child: Text(
                      'Zatiaľ žiadne správy.\nKlikni na polohu aby ste zdielali polohu.',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _zobrazovaneSpravy.length,
                    itemBuilder: (context, index) {
                      final msg = _zobrazovaneSpravy[index];
                      bool isOdoslana = msg['smer'] == "odoslana";
                      bool isPoloha = msg['typ'] == "poloha";
                      bool isVystraha = msg['typ'] == "vystraha";

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Align(
                          alignment: isOdoslana
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isVystraha
                                  ? Colors.red[800]
                                  : (isPoloha
                                      ? Colors.deepPurple
                                      : (isOdoslana
                                          ? Colors.blueAccent
                                          : Colors.teal)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: isOdoslana
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg['obsah'] ?? '',
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(height: 4),
                                if (msg['sifra'] != null)
                                  Text(
                                    '${msg['sifra']!}',
                                    style: const TextStyle(
                                      fontSize: 8,
                                      color: Colors.white60,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                if (msg['vzdialenost'] != null)
                                  Text(
                                    'Vzdialenosť: ${msg['vzdialenost']} km',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white60,
                                    ),
                                  ),
                                if (msg['casovy_razitko'] != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_formatujCas(msg['casovy_razitko'])}',
                                    style: const TextStyle(
                                      fontSize: 8,
                                      color: Colors.white60,
                                    ),
                                  ),
                                ],
                                if (isPoloha && msg['lat'] != null) ...[
                                  const SizedBox(height: 8),
                                  ElevatedButton(
                                    onPressed: () => _otvoritOfflineMapu(
                                      msg['lat'],
                                      msg['lon'],
                                      isOdoslana ? "Ja" : widget.menoKamaranda,
                                    ),
                                    child: const Text('Zobraziť mapu'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.black26,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.location_on,
                    color: Colors.amberAccent,
                  ),
                  onPressed: _odoslatPolohu,
                  tooltip: 'Zdielaj polohu',
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Napíš správu...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blueAccent),
                  onPressed: () {
                    if (_messageController.text.trim().isEmpty) return;

                    String sifrovanaSprava = SifrovaciaSluzba.sifrovajAES(
                      _messageController.text,
                    );
                    String hash = SifrovaciaSluzba.generujHash(
                      _messageController.text,
                    );
                    int casNow = DateTime.now().millisecondsSinceEpoch;

                    SpravaZaznam zaznam = SpravaZaznam(
                      id: _generujID(),
                      sifrovanyObsah: sifrovanaSprava,
                      sifrovanaPoloha: "",
                      typ: "text",
                      smer: "odoslana",
                      casovy_razitko: casNow,
                      hash: hash,
                      kontakt: widget.menoKamaranda,
                    );

                    setState(() {
                      HistoriaKontaktov.addSifrovanaSprava(
                        widget.menoKamaranda,
                        zaznam,
                      );
                      HistoriaKontaktov.addZobrazovanaSprava(
                        widget.menoKamaranda,
                        {
                          "typ": "text",
                          "smer": "odoslana",
                          "obsah": _messageController.text,
                          "sifra": sifrovanaSprava.substring(0, 30) + "...",
                          "desifrovaneSifra": sifrovanaSprava,
                          "casovy_razitko": casNow,
                        },
                      );
                      _zobrazovaneSpravy =
                          HistoriaKontaktov.getZobrazovaneSpravy(
                        widget.menoKamaranda,
                      );
                    });

                    String textForResponse = _messageController.text;
                    _messageController.clear();

                    // Poslanie cez Meshtastic
                    widget.meshService.sendMessage(
                      textForResponse,
                      widget.nodeNum,
                    );

/*
                    Future.delayed(const Duration(seconds: 1), () {
                      if (mounted) {
                        setState(() {
                          String response =
                              "Potvrdenie: Správa prijatá cez Meshtastic";
                          String sifrovanaOdpoved =
                              SifrovaciaSluzba.sifrovajAES(response);
                          int casOdpovede =
                              DateTime.now().millisecondsSinceEpoch;

                          HistoriaKontaktov.addZobrazovanaSprava(
                            widget.menoKamaranda,
                            {
                              "typ": "text",
                              "smer": "prijata",
                              "obsah": response,
                              "sifra":
                                  sifrovanaOdpoved.substring(0, 30) + "...",
                              "casovy_razitko": casOdpovede,
                            },
                          );

                          SpravaZaznam zaznamOdpoved = SpravaZaznam(
                            id: _generujID(),
                            sifrovanyObsah: sifrovanaOdpoved,
                            sifrovanaPoloha: "",
                            typ: "text",
                            smer: "prijata",
                            casovy_razitko: casOdpovede,
                            hash: SifrovaciaSluzba.generujHash(response),
                            kontakt: widget.menoKamaranda,
                          );
                          HistoriaKontaktov.addSifrovanaSprava(
                            widget.menoKamaranda,
                            zaznamOdpoved,
                          );
                          _zobrazovaneSpravy =
                              HistoriaKontaktov.getZobrazovaneSpravy(
                            widget.menoKamaranda,
                          );
                        });
                      }
                    });
                    */
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
}
