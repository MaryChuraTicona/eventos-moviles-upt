import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OrganizerChatService {
  final _db = FirebaseFirestore.instance;

  Stream<List<OrganizerChatMessage>> streamMessages(
      String eventId, String sessionId) {
    return _db
        .collection('eventos')
        .doc(eventId)
        .collection('sesiones')
        .doc(sessionId)
        .collection('chat')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => OrganizerChatMessage.fromFirestore(doc))
            .toList());
  }

  Future<void> sendMessage({
    required String eventId,
    required String sessionId,
    required String text,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw 'Debes iniciar sesión para chatear.';
    final displayName = user.displayName?.trim();

    await _db
        .collection('eventos')
        .doc(eventId)
        .collection('sesiones')
        .doc(sessionId)
        .collection('chat')
        .add({
      'text': text.trim(),
      'senderId': user.uid,
      'senderName': displayName?.isNotEmpty == true ? displayName : 'Organizador',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

class OrganizerChatMessage {
  final String id;
  final String text;
  final String senderId;
  final String senderName;
  final DateTime? createdAt;

  OrganizerChatMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.senderName,
    required this.createdAt,
  });

  factory OrganizerChatMessage.fromFirestore(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return OrganizerChatMessage(
      id: doc.id,
      text: (data['text'] ?? '').toString(),
      senderId: (data['senderId'] ?? '').toString(),
      senderName: (data['senderName'] ?? 'Participante').toString(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}