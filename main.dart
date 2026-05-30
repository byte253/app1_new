import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;

void main() => runApp(const BezpecnyChatApp());

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

// Šifrovacia utility trieda s AES-256
class SifrovaciaSluzba {
  static const String _defaultKluc =
      "tajnyKlucPre256bitovuSifruAES!!"; // min 32 znakov

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

// Trieda pre uloženie šifrovanej histórie
class SpravaZaznam {
  final String id;
  final String sifrovanyObsah;
  final String sifrovanaPoloha;
  final String typ;
  final String smer;
  final int casovy_razitko;
  final String hash;
  final String? kontakt; // pre skúpňovanie podľa kontaktu
  double? lat;
  double? lon;

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
    );
  }
}

// Trieda pre mapu - poloha bodu
class PolohaBodu {
  final String nazov;
  final double lat;
  final double lon;
  final int casovy_razitko;
  final String typ; // "kontakt" alebo "vystraha"
  final Color farba;
  final String? meno;

  PolohaBodu({
    required this.nazov,
    required this.lat,
    required this.lon,
    required this.casovy_razitko,
    required this.typ,
    required this.farba,
    this.meno,
  });
}

class ObravovkaKontaktov extends StatefulWidget {
  const ObravovkaKontaktov({super.key});
  @override
  State<ObravovkaKontaktov> createState() => _ObravovkaKontaktovState();
}

class _ObravovkaKontaktovState extends State<ObravovkaKontaktov> {
  String _mojaPrezyvka = "Novy_Pouzivatel";
  static List<Map<String, dynamic>> vystrahyVlny = [];

  // Polohy kontaktov
  final Map<String, Map<String, dynamic>> _polohy = {
    "Kamarát 1 (ALFA)": {"lat": 48.8566, "lon": 2.3522, "cas": null},
    "Kamarát 2 (BETA)": {"lat": 48.8944, "lon": 2.3912, "cas": null},
    "Základňa DOM": {"lat": 48.8700, "lon": 2.3550, "cas": null},
  };

  final List<Map<String, String>> _kamarati = [
    {"meno": "Kamarát 1 (ALFA)", "status": "Online v Mesh sieti"},
    {"meno": "Kamarát 2 (BETA)", "status": "Vzdialený cez opakovač"},
    {"meno": "Základňa DOM", "status": "Stabilný uzol"},
  ];

  @override
  void initState() {
    super.initState();
    _initDemoVystrahy();
  }

  void _initDemoVystrahy() {
    if (vystrahyVlny.isEmpty) {
      vystrahyVlny = [
        {"vzdialenost": 5.5, "citatelny": true, "obsah": "Signal z Blizko"},
        {"vzdialenost": 25.3, "citatelny": false, "obsah": ""},
        {"vzdialenost": 85.7, "citatelny": false, "obsah": ""},
        {"vzdialenost": 12.1, "citatelny": true, "obsah": "Neznama frekvencia"},
      ];
    }
  }

  List<PolohaBodu> _getMapoveBody() {
    List<PolohaBodu> body = [];

    // Kontakty
    _polohy.forEach((meno, data) {
      if (data['lat'] != null && data['lon'] != null) {
        body.add(
          PolohaBodu(
            nazov: meno,
            lat: data['lat'],
            lon: data['lon'],
            casovy_razitko:
                data['cas'] ?? DateTime.now().millisecondsSinceEpoch,
            typ: "kontakt",
            farba: Colors.blueAccent,
            meno: meno,
          ),
        );
      }
    });

    // Výstrahy (posledné 3)
    List<Map<String, dynamic>> posledneVystrahy = List.from(vystrahyVlny);
    posledneVystrahy.sort(
      (a, b) => (b['vzdialenost'] ?? 0).compareTo(a['vzdialenost'] ?? 0),
    );

    for (int i = 0; i < min(3, posledneVystrahy.length); i++) {
      final v = posledneVystrahy[i];
      double dist = v["vzdialenost"] ?? 0;
      Color farba = dist <= 15
          ? Colors.redAccent
          : (dist <= 50 ? Colors.yellowAccent : Colors.greenAccent);

      body.add(
        PolohaBodu(
          nazov: "Vystraha ${i + 1}",
          lat: 48.8566 + (Random().nextDouble() * 0.1 - 0.05),
          lon: 2.3522 + (Random().nextDouble() * 0.1 - 0.05),
          casovy_razitko: DateTime.now().millisecondsSinceEpoch,
          typ: "vystraha",
          farba: farba,
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
        title: const Text('Radiovi Kamaradi'),
        backgroundColor: Colors.blueGrey,
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
                Text('Tvoj volaci znak: $_mojaPrezyvka'),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                // MAPA - ZLTÁ FARBA
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.amber,
                    child: Icon(Icons.map, color: Colors.black),
                  ),
                  title: const Text(
                    'MAP - Mapy',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber,
                    ),
                  ),
                  subtitle: const Text('Polohy kontaktov a vystraho'),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.amber,
                  ),
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

                // VYSTRAHY
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.red,
                    child: Icon(Icons.warning, color: Colors.white),
                  ),
                  title: const Text(
                    'VYSTRAHA - Nezname pakety',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  subtitle: const Text('Pasivny radar eteru'),
                  trailing: const Icon(Icons.chevron_right, color: Colors.red),
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
                ..._kamarati.map(
                  (k) => ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.blueAccent,
                      child: Icon(Icons.person),
                    ),
                    title: Text(
                      k["meno"]!,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(k["status"]!),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.blueAccent,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ObrazovkaCatu(
                          menoKamaranda: k["meno"]!,
                          onCudziPaketZachyteny: (nv) =>
                              setState(() => vystrahyVlny.add(nv)),
                          onPolohaZachytena: (lat, lon, cas) {
                            setState(() {
                              _polohy[k["meno"]!] = {
                                "lat": lat,
                                "lon": lon,
                                "cas": cas,
                              };
                            });
                          },
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
}

// NOVA OBRAZOVKA - OFFLINE MAPA
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
          ? const Center(child: Text('Ziadne polohy na mape.'))
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
                        // Body na mape (simulacia pozicii)
                        ...body.map((bod) {
                          // Simulacia pozicii na mape (0-100%)
                          double x = ((bod.lon - 2.25) / 0.45) * 100;
                          double y = ((bod.lat - 48.75) / 0.25) * 100;

                          x = x.clamp(5, 95);
                          y = y.clamp(5, 95);

                          return Positioned(
                            left: (x / 100) * MediaQuery.of(context).size.width,
                            top:
                                (y / 100) *
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
                                    child: bod.typ == "kontakt"
                                        ? const Icon(
                                            Icons.person,
                                            size: 20,
                                            color: Colors.white,
                                          )
                                        : const Icon(
                                            Icons.warning,
                                            size: 20,
                                            color: Colors.black,
                                          ),
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
                              color: Colors.blueAccent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Kontakty',
                            style: TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 24),
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
                            'Vystraha - Daleko',
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
                            'Vystraha - Stredno',
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
                          const Text(
                            'Vystraha - Blizko',
                            style: TextStyle(fontSize: 12),
                          ),
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

class ObrazovkaCatu extends StatefulWidget {
  final String menoKamaranda;
  final Function(Map<String, dynamic>) onCudziPaketZachyteny;
  final Function(double, double, int) onPolohaZachytena;

  const ObrazovkaCatu({
    super.key,
    required this.menoKamaranda,
    required this.onCudziPaketZachyteny,
    required this.onPolohaZachytena,
  });

  @override
  State<ObrazovkaCatu> createState() => _ObrazovkaCatuState();
}

class _ObrazovkaCatuState extends State<ObrazovkaCatu> {
  final TextEditingController _textController = TextEditingController();
  final List<SpravaZaznam> _sifrovanaHistoria = [];
  final List<Map<String, dynamic>> _zobrazovaneSpravy = [];
  final double _mojeLat = 48.8566;
  final double _mojeLon = 2.3522;
  double? _kamarandLat;
  double? _kamarandLon;
  String _vzdialenostVListe = "Poloha neznama";

  String _generujID() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  double _vypocitajVzdialenostCislo(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    var p = 0.017453292519943295;
    var c = cos;
    var a =
        0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  String _formatujCas(int timestamp) {
    DateTime cas = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return "${cas.day}.${cas.month}.${cas.year} ${cas.hour}:${cas.minute.toString().padLeft(2, '0')}";
  }

  void _odoslatPolohu() {
    String polohaText = "GPS:$_mojeLat,$_mojeLon";
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
      lat: _mojeLat,
      lon: _mojeLon,
    );

    setState(() {
      _sifrovanaHistoria.add(zaznam);
      _zobrazovaneSpravy.add({
        "typ": "poloha",
        "smer": "odoslana",
        "obsah": "Zdielam moju polohu",
        "sifra": sifrovanaPoloha.substring(0, 30) + "...",
        "desifrovaneSifra": sifrovanaPoloha,
        "casovy_razitko": casNow,
      });
    });

    widget.onPolohaZachytena(_mojeLat, _mojeLon, casNow);

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _kamarandLat = 48.8944;
          _kamarandLon = 2.3912;
          int casKamarada = DateTime.now().millisecondsSinceEpoch;

          _vzdialenostVListe =
              "${_vypocitajVzdialenostCislo(_mojeLat, _mojeLon, _kamarandLat!, _kamarandLon!).toStringAsFixed(2)} km";

          String kamaradPoloha = "GPS:$_kamarandLat,$_kamarandLon";
          String sifrovanaKamaradLokal = SifrovaciaSluzba.sifrovajAES(
            kamaradPoloha,
          );
          String hashKamarad = SifrovaciaSluzba.generujHash(kamaradPoloha);

          SpravaZaznam zaznnamKamarad = SpravaZaznam(
            id: _generujID(),
            sifrovanyObsah: SifrovaciaSluzba.sifrovajAES(
              "Kamarad poslal polohu",
            ),
            sifrovanaPoloha: sifrovanaKamaradLokal,
            typ: "poloha",
            smer: "prijata",
            casovy_razitko: casKamarada,
            hash: hashKamarad,
            kontakt: widget.menoKamaranda,
            lat: _kamarandLat,
            lon: _kamarandLon,
          );

          _sifrovanaHistoria.add(zaznnamKamarad);
          _zobrazovaneSpravy.add({
            "typ": "poloha",
            "smer": "prijata",
            "obsah": "Kamarad poslal polohu",
            "sifra": sifrovanaKamaradLokal.substring(0, 30) + "...",
            "desifrovaneSifra": sifrovanaKamaradLokal,
            "casovy_razitko": casKamarada,
          });

          widget.onPolohaZachytena(_kamarandLat!, _kamarandLon!, casKamarada);
        });
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Poloha odoslana'),
        backgroundColor: Colors.greenAccent,
      ),
    );
  }

  void _otvoritOfflineMapu(String kto) {
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
                  'Nacitane offline dlazidce z disku',
                  style: TextStyle(color: Colors.black, fontSize: 12),
                ),
                Text(
                  kto == "Ja"
                      ? "Lat: $_mojeLat, Lon: $_mojeLon"
                      : "Lat: $_kamarandLat, Lon: $_kamarandLon",
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
            child: const Text('Zatvorit'),
          ),
        ],
      ),
    );
  }

  // ✅ OPRAVENÁ FUNKCIA NA MAZANIE HISTÓRIE - VYMAŽ NOVÉ!
  void _zobrazitMazanieHistorie() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vymaz Historiu'),
        content: const Text('Vyber co chces vymaza:'),
        actions: [
          // TLACITKO 1 - Vymaz Vsetko
          TextButton(
            onPressed: () {
              setState(() {
                _sifrovanaHistoria.clear();
                _zobrazovaneSpravy.clear();
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cela historia bola vymazana'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            },
            child: const Text(
              'Vymaz Vsetko',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
          // TLACITKO 2 - Vymaž posledných 7 dní (NOVÉ sprievania z posledných 7 dní)
          TextButton(
            onPressed: () {
              int sedemDniMs = 7 * 24 * 60 * 60 * 1000;
              int casLimit = DateTime.now().millisecondsSinceEpoch - sedemDniMs;

              setState(() {
                // ✅ OPRAVA: Vymazuj sprievania ktoré sú NOVŠIE ako 7 dní
                _sifrovanaHistoria.removeWhere(
                  (z) => z.casovy_razitko > casLimit,
                );
                _zobrazovaneSpravy.removeWhere(
                  (z) =>
                      (z['casovy_razitko'] ??
                          DateTime.now().millisecondsSinceEpoch) >
                      casLimit,
                );
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sprievania z poslednich 7 dni boli vymazane'),
                  backgroundColor: Colors.orangeAccent,
                ),
              );
            },
            child: const Text(
              'Poslednych 7 Dni',
              style: TextStyle(color: Colors.orangeAccent),
            ),
          ),
          // TLACITKO 3 - Vymaž posledných 24 hodín (NOVÉ sprievania z posledného dňa)
          TextButton(
            onPressed: () {
              int jedanDenMs = 24 * 60 * 60 * 1000;
              int casLimit = DateTime.now().millisecondsSinceEpoch - jedanDenMs;

              setState(() {
                // ✅ OPRAVA: Vymazuj sprievania ktoré sú NOVŠIE ako 24 hodín
                _sifrovanaHistoria.removeWhere(
                  (z) => z.casovy_razitko > casLimit,
                );
                _zobrazovaneSpravy.removeWhere(
                  (z) =>
                      (z['casovy_razitko'] ??
                          DateTime.now().millisecondsSinceEpoch) >
                      casLimit,
                );
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sprievania z poslednich 24 hodin boli vymazane'),
                  backgroundColor: Colors.amberAccent,
                ),
              );
            },
            child: const Text(
              'Poslednych 24 Hodin',
              style: TextStyle(color: Colors.amberAccent),
            ),
          ),
          // TLACITKO 4 - Vymaž poslednú 1 hodinu (NOVÉ sprievania z poslednej hodiny)
          TextButton(
            onPressed: () {
              int jednaHodinaMs = 60 * 60 * 1000;
              int casLimit =
                  DateTime.now().millisecondsSinceEpoch - jednaHodinaMs;

              setState(() {
                // ✅ OPRAVA: Vymazuj sprievania ktoré sú NOVŠIE ako 1 hodina
                _sifrovanaHistoria.removeWhere(
                  (z) => z.casovy_razitko > casLimit,
                );
                _zobrazovaneSpravy.removeWhere(
                  (z) =>
                      (z['casovy_razitko'] ??
                          DateTime.now().millisecondsSinceEpoch) >
                      casLimit,
                );
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sprievania z poslednei 1 hodiny boli vymazane'),
                  backgroundColor: Colors.greenAccent,
                ),
              );
            },
            child: const Text(
              'Posledna 1 Hodina',
              style: TextStyle(color: Colors.greenAccent),
            ),
          ),
          // ZRUSIT
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zrusit', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  void _zobrazitHistoriu() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sifrovana Historia - AES-256'),
        content: SizedBox(
          width: 350,
          height: 400,
          child: _sifrovanaHistoria.isEmpty
              ? const Center(child: Text('Ziadna historia'))
              : ListView.builder(
                  itemCount: _sifrovanaHistoria.length,
                  itemBuilder: (context, index) {
                    final zaznam = _sifrovanaHistoria[index];
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
                              'Hash: ${zaznam.hash.substring(0, 16)}...',
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              'Cas: ${_formatujCas(zaznam.casovy_razitko)}',
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
            child: const Text('Zatvorit'),
          ),
        ],
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
            Text('Cet: ${widget.menoKamaranda}'),
            Text(
              'Vzdialenost: $_vzdialenostVListe',
              style: const TextStyle(fontSize: 12, color: Colors.amberAccent),
            ),
          ],
        ),
        backgroundColor: Colors.blueGrey,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            onPressed: _zobrazitMazanieHistorie,
            tooltip: 'Vymaz historiu',
          ),
          IconButton(
            icon: const Icon(Icons.history, color: Colors.lightBlueAccent),
            onPressed: _zobrazitHistoriu,
            tooltip: 'Sifrovana historia',
          ),
          IconButton(
            icon: const Icon(Icons.radar, color: Colors.greenAccent),
            onPressed: () => _simulujCudziPaket(49.5000, 2.9000, false, ""),
          ),
          IconButton(
            icon: const Icon(Icons.radar, color: Colors.orangeAccent),
            onPressed: () => _simulujCudziPaket(48.9500, 2.4500, false, ""),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _zobrazovaneSpravy.isEmpty
                ? const Center(
                    child: Text(
                      'Zatial ziadne spravy.\nKlikni na polohu aby ste zdielali polohu.',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _zobrazovaneSpravy.length,
                    itemBuilder: (context, index) {
                      final msg = _zobrazovaneSpravy[index];
                      bool isOdoslana = msg['smer'] == "odoslana";
                      bool isPoloha = msg['typ'] == "poloha";

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Align(
                          alignment: isOdoslana
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isPoloha
                                  ? Colors.deepPurple
                                  : (isOdoslana
                                        ? Colors.blueAccent
                                        : Colors.teal),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: isOdoslana
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg['obsah']!,
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${msg['sifra']!}',
                                  style: const TextStyle(
                                    fontSize: 8,
                                    color: Colors.white60,
                                    fontStyle: FontStyle.italic,
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
                                if (isPoloha) ...[
                                  const SizedBox(height: 8),
                                  ElevatedButton(
                                    onPressed: () => _otvoritOfflineMapu(
                                      isOdoslana ? "Ja" : widget.menoKamaranda,
                                    ),
                                    child: const Text('Zobraz mapu'),
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
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Napis spravu...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blueAccent),
                  onPressed: () {
                    if (_textController.text.trim().isEmpty) return;

                    String sifrovanaSprava = SifrovaciaSluzba.sifrovajAES(
                      _textController.text,
                    );
                    String hash = SifrovaciaSluzba.generujHash(
                      _textController.text,
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
                      _sifrovanaHistoria.add(zaznam);
                      _zobrazovaneSpravy.add({
                        "typ": "text",
                        "smer": "odoslana",
                        "obsah": _textController.text,
                        "sifra": sifrovanaSprava.substring(0, 30) + "...",
                        "desifrovaneSifra": sifrovanaSprava,
                        "casovy_razitko": casNow,
                      });
                    });

                    _textController.clear();

                    Future.delayed(const Duration(seconds: 1), () {
                      if (mounted) {
                        setState(() {
                          String response = "Potvrdenie: Sprava prijata";
                          String sifrovanaOdpoved =
                              SifrovaciaSluzba.sifrovajAES(response);
                          int casOdpovede =
                              DateTime.now().millisecondsSinceEpoch;

                          _zobrazovaneSpravy.add({
                            "typ": "text",
                            "smer": "prijata",
                            "obsah": response,
                            "sifra": sifrovanaOdpoved.substring(0, 30) + "...",
                            "casovy_razitko": casOdpovede,
                          });

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
                          _sifrovanaHistoria.add(zaznamOdpoved);
                        });
                      }
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _simulujCudziPaket(double lat, double lon, bool cit, String obs) {
    widget.onCudziPaketZachyteny({
      "vzdialenost": _vypocitajVzdialenostCislo(_mojeLat, _mojeLon, lat, lon),
      "citatelny": cit,
      "obsah": obs,
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Zachyteny neznamny radiovy paket!'),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
}

class ObrazovkaVystrah extends StatelessWidget {
  final List<Map<String, dynamic>> vystrahy;
  const ObrazovkaVystrah({super.key, required this.vystrahy});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Radar: Nezname signaly'),
        backgroundColor: const Color(0xFFB71C1C),
      ),
      body: vystrahy.isEmpty
          ? const Center(child: Text('V eteri je pokoj.'))
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
                            const Text('Signal'),
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
                          cit ? 'Obsah: "${v["obsah"]}"' : 'Paket je sifrovany',
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
