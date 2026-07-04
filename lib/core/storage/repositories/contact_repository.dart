// lib/core/storage/repositories/contact_repository.dart
import '../../../objectbox.g.dart';
import '../entities/contact_entity.dart';
import '../objectbox/store.dart';

class ContactRepository {
  final ObjectBoxStore _db;
  Box<ContactEntity>? _boxCached;

  ContactRepository(this._db);

  Box<ContactEntity> get _box => _boxCached ??= _db.getBox<ContactEntity>();

  List<ContactEntity> all() => _box.getAll()..sort((a, b) => a.name.compareTo(b.name));

  bool isContact(String publicKey) =>
      _box.query(ContactEntity_.publicKey.equals(publicKey)).build().findFirst() != null;

  void add(String publicKey, {String? name}) {
    if (isContact(publicKey)) return;
    _box.put(ContactEntity(publicKey: publicKey, name: name ?? _shortId(publicKey)));
  }

  void remove(String publicKey) {
    final existing =
        _box.query(ContactEntity_.publicKey.equals(publicKey)).build().findFirst();
    if (existing != null) _box.remove(existing.id);
  }

  String _shortId(String key) =>
      key.length > 14 ? "${key.substring(0, 8)}…${key.substring(key.length - 4)}" : key;
}