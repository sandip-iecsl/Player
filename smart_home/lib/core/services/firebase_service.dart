import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../constants/app_constants.dart';
import '../models/user_model.dart';

/// Centralised Firebase access — one singleton per service.
class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FirebaseDatabase database = FirebaseDatabase.instance;
  final FirebaseMessaging messaging = FirebaseMessaging.instance;

  // ── Auth helpers ─────────────────────────────────────────────────────────

  User? get currentUser => auth.currentUser;
  String? get currentUid => auth.currentUser?.uid;

  Stream<User?> get authStateChanges => auth.authStateChanges();

  Future<UserCredential> signIn(String email, String password) =>
      auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<UserCredential> register(String email, String password) =>
      auth.createUserWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> signOut() => auth.signOut();

  Future<void> sendPasswordReset(String email) =>
      auth.sendPasswordResetEmail(email: email.trim());

  // ── Firestore helpers ─────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get usersRef =>
      firestore.collection(AppConstants.usersCollection);

  CollectionReference<Map<String, dynamic>> get adminsRef =>
      firestore.collection(AppConstants.adminsCollection);

  CollectionReference<Map<String, dynamic>> get roomsRef =>
      firestore.collection(AppConstants.roomsCollection);

  CollectionReference<Map<String, dynamic>> get logsRef =>
      firestore.collection(AppConstants.logsCollection);

  CollectionReference<Map<String, dynamic>> get automationsRef =>
      firestore.collection(AppConstants.automationsCollection);

  Future<UserModel?> fetchUser(String uid) async {
    final doc = await usersRef.doc(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return UserModel.fromFirestore(doc.data()!, uid);
  }

  Future<void> createUser(UserModel user) =>
      usersRef.doc(user.uid).set(user.toFirestore());

  Future<void> updateUser(String uid, Map<String, dynamic> data) =>
      usersRef.doc(uid).update(data);

  Stream<UserModel?> userStream(String uid) => usersRef.doc(uid).snapshots().map(
        (s) => s.exists ? UserModel.fromFirestore(s.data()!, uid) : null,
      );

  Future<bool> isAdmin(String uid) async {
    final doc = await adminsRef.doc(uid).get();
    return doc.exists;
  }

  // ── Realtime Database helpers ─────────────────────────────────────────────

  DatabaseReference get relaysRef =>
      database.ref(AppConstants.relaysPath);

  DatabaseReference get espStatusRef =>
      database.ref(AppConstants.espStatusPath);

  DatabaseReference relayRef(String relayId) =>
      database.ref('${AppConstants.relaysPath}/$relayId');

  Stream<DatabaseEvent> get relaysStream => relaysRef.onValue;

  Future<void> toggleRelay(String relayId, bool state) =>
      relayRef(relayId).update({'state': state});

  Future<void> updateRelayData(String relayId, Map<String, dynamic> data) =>
      relayRef(relayId).update(data);

  // ── FCM helpers ──────────────────────────────────────────────────────────

  Future<void> initFcm() async {
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await messaging.getToken();
    if (token != null && currentUid != null) {
      await updateUser(currentUid!, {'fcmToken': token});
    }
    messaging.onTokenRefresh.listen((newToken) {
      if (currentUid != null) {
        updateUser(currentUid!, {'fcmToken': newToken});
      }
    });
  }

  // ── Audit log ────────────────────────────────────────────────────────────

  Future<void> logAudit(String action, {String? targetUid, Map<String, dynamic>? details}) async {
    final uid = currentUid;
    if (uid == null) return;
    await logsRef.add({
      'actorUid': uid,
      'action': action,
      'targetUid': targetUid,
      'details': details,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
