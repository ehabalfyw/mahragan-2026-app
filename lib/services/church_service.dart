import 'dart:convert';
import 'package:http/http.dart' as http;

class Church {
  final String id;
  final String name;
  final String location;


  Church({required this.id, required this.name, required this.location});


  factory Church.fromJson(Map<String, dynamic> json) {
    return Church(
      id: json['id'].toString(),
      name: json['name'] ?? 'Unnamed',
      location: json['location'] ?? 'Unknown',
    );
  }
}


Future<List<Church>> fetchChurches() async {
  final url = Uri.parse('https://mahragan.ngrok.app/api/churches.php');
  final response = await http.get(url);

  if (response.statusCode == 200) {
    final List<dynamic> data = json.decode(response.body);
    return data.map((json) => Church.fromJson(json)).toList();
  } else {
    throw Exception('Failed to load churches');
  }
}